/// 自动记账的编排（F7.15 SPEC §3.1）。
///
/// 流程：drain 队列 → 解析（纯函数）→ 按 source 分组 → `ensureSourceAccount` →
/// **复用 `importRows()`**（每组一次事务，指纹唯一索引兜底）→ 记批次 → 刷新视图 → 回执通知。
///
/// 为什么入账要绕回 Dart：drift 是唯一 DB writer，Kotlin 侧只落盘（见 SPEC §3.1）。
/// 代价是「入账延迟到下次打开 App」—— 用户本来就要打开 App 才看得到提示条，几乎无感。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/autobook/application/auto_book_accounts.dart';
import 'package:yanxin/features/autobook/application/auto_book_notice.dart';
import 'package:yanxin/features/autobook/data/auto_book_batches.dart';
import 'package:yanxin/features/autobook/data/auto_book_bridge.dart';
import 'package:yanxin/features/autobook/data/auto_book_rules.dart';
import 'package:yanxin/features/import/application/bill_importer.dart';
import 'package:yanxin/features/import/data/bill_normalize.dart' show ParsedRow;

/// 一次 drain 的结果（用于日志 / 测试断言；页面不直接消费）。
class AutoBookDrainResult {
  const AutoBookDrainResult({
    this.imported = 0,
    this.duplicates = 0,
    this.dropped = 0,
    this.undone = 0,
    this.batch,
  });

  /// 真正入账的笔数。
  final int imported;

  /// 指纹重复跳过的笔数。
  final int duplicates;

  /// 解析失败被丢弃的条数（坏数据 / 非消费通知）。
  final int dropped;

  /// 本次 drain 顺带执行的通知栏「撤销」笔数。
  final int undone;

  /// 本批（imported > 0 时非空）。
  final AutoBookBatch? batch;

  bool get touched => imported > 0 || undone > 0;
}

final autoBookControllerProvider = Provider<AutoBookController>(
  AutoBookController.new,
);

class AutoBookController {
  AutoBookController(this._ref);

  final Ref _ref;

  /// 防重入：首帧后与生命周期 resumed 可能几乎同时触发。
  bool _draining = false;

  /// 取队列 → 入账。**任何异常都被吞掉**（静默失败不得阻断冷启动）。
  Future<AutoBookDrainResult> drain() async {
    if (_draining) return const AutoBookDrainResult();
    _draining = true;
    try {
      return await _drain();
    } catch (_) {
      return const AutoBookDrainResult();
    } finally {
      _draining = false;
    }
  }

  Future<AutoBookDrainResult> _drain() async {
    final AutoBookBridge bridge = _ref.read(autoBookBridgeProvider);
    final AutoBookBatchStore store = _ref.read(autoBookBatchStoreProvider);

    // A. 先处理通知栏「撤销」命令 —— 队列空也要处理（命令可能在冷启动前就落下）
    var undone = 0;
    final String? command = await bridge.takeCommand();
    if (command != null && command.isNotEmpty) {
      undone = await _handleCommand(command, bridge);
    }

    // B. 取队列
    final List<String> raw = await bridge.drainQueue();
    if (raw.isEmpty) {
      return AutoBookDrainResult(undone: undone);
    }

    final List<ParsedRow> rows = <ParsedRow>[];
    var dropped = 0;
    for (final String line in raw) {
      final ParsedRow? row = _parseLine(line);
      if (row == null) {
        dropped++;
      } else {
        rows.add(row);
      }
    }

    if (rows.isEmpty) {
      // 全是坏数据 / 非消费通知：清掉「识别到 N 笔」，别让通知一直挂着
      await bridge.cancelReceipt();
      return AutoBookDrainResult(dropped: dropped, undone: undone);
    }

    final String? bookId = await _ref.read(activeBookIdProvider.future);
    if (bookId == null) {
      return AutoBookDrainResult(dropped: dropped, undone: undone);
    }

    final BillCategoryMaps categoryMaps = await buildCategoryMaps(
      _ref.read(categoryRepositoryProvider),
      bookId,
    );
    final db = _ref.read(appDatabaseProvider);
    final accountRepo = _ref.read(accountRepositoryProvider);

    // 按 source 分组：每组一次事务，账户独立
    final Map<String, List<ParsedRow>> groups = <String, List<ParsedRow>>{};
    for (final ParsedRow r in rows) {
      groups.putIfAbsent(r.source, () => <ParsedRow>[]).add(r);
    }

    var imported = 0;
    var duplicates = 0;
    var amountCents = 0;
    final List<String> txIds = <String>[];
    final List<String> receiptLines = <String>[];

    for (final MapEntry<String, List<ParsedRow>> entry in groups.entries) {
      final String accountId = await ensureSourceAccount(
        accountRepo,
        bookId,
        entry.key,
      );
      final ImportReport report = await importRows(
        db,
        bookId: bookId,
        accountId: accountId,
        categoryMaps: categoryMaps,
        rows: entry.value,
      );
      imported += report.imported;
      duplicates += report.duplicates + report.fileDuplicates;
      amountCents += report.importedAmountCents;
      txIds.addAll(report.importedIds);
      if (report.imported > 0) {
        receiptLines.add(
          '${kSourceLabel[entry.key] ?? entry.key} ${report.imported} 笔',
        );
      }
    }

    if (imported == 0) {
      // 全是重复（同一通知被监听两次 / 队列残留）：不发回执，收起旧提示
      await bridge.cancelReceipt();
      return AutoBookDrainResult(
        duplicates: duplicates,
        dropped: dropped,
        undone: undone,
      );
    }

    final AutoBookBatch batch = AutoBookBatch(
      batchId: 'b${DateTime.now().millisecondsSinceEpoch}',
      txIds: txIds,
      count: imported,
      totalCents: amountCents,
      atMs: DateTime.now().millisecondsSinceEpoch,
    );
    await store.remember(batch);
    _ref.read(autoBookNoticeProvider.notifier).show(batch);
    refreshAfterAutoBookWrite(_ref);
    unawaited(
      bridge.showReceipt(
        count: imported,
        amountText: centsToYuan(amountCents),
        batchId: batch.batchId,
        lines: receiptLines,
      ),
    );

    return AutoBookDrainResult(
      imported: imported,
      duplicates: duplicates,
      dropped: dropped,
      undone: undone,
      batch: batch,
    );
  }

  /// 通知按钮落下的命令（`{"action":"undo","batchId":"..."}`）。
  Future<int> _handleCommand(String command, AutoBookBridge bridge) async {
    try {
      final Object? decoded = jsonDecode(command);
      if (decoded is! Map) return 0;
      final Map<String, Object?> map = decoded.cast<String, Object?>();
      if (map['action'] != kAutoBookActionUndo) return 0;
      final Object? batchId = map['batchId'];
      if (batchId is! String || batchId.isEmpty) return 0;
      final int deleted = await _ref
          .read(autoBookNoticeProvider.notifier)
          .undo(batchId);
      await bridge.cancelReceipt();
      return deleted;
    } catch (_) {
      return 0;
    }
  }

  /// 单行 JSONL → ParsedRow（通知或分享；坏行返回 null）。
  ParsedRow? _parseLine(String line) {
    final RawNotification? n = RawNotification.tryParse(line);
    if (n != null) return parseNotification(n);
    final RawShare? s = RawShare.tryParse(line);
    if (s != null) return parseSharedText(s);
    return null;
  }
}
