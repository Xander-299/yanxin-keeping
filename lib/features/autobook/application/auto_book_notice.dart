/// 自动记账的「本批」状态与撤销（F7.15 SPEC §3.6）。
///
/// 首页顶部提示条只看这里的 state（**会话内**）；跨启动的撤销（通知栏按钮在冷启动后被点）
/// 走 `auto_book_batches.dart` 落库的 KV —— 两条入口最终都汇到 [AutoBookNoticeNotifier.undo]。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/autobook/data/auto_book_batches.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

/// 最近一批自动记账（null = 没有待提示的批次）。
///
/// 首页提示条的显示 / 隐藏**只看它** —— 不渲染占位高度。
final autoBookNoticeProvider =
    NotifierProvider<AutoBookNoticeNotifier, AutoBookBatch?>(
      AutoBookNoticeNotifier.new,
    );

class AutoBookNoticeNotifier extends Notifier<AutoBookBatch?> {
  @override
  AutoBookBatch? build() => null;

  /// 入账成功后记一批（提示条立刻出现）。
  void show(AutoBookBatch batch) => state = batch;

  /// 收起提示条（**不删账**）。
  void dismiss() => state = null;

  /// 最近一批（含跨启动的，用于 `/autobook` 页的兜底入口）。
  Future<AutoBookBatch?> latest() => ref.read(autoBookBatchStoreProvider).latest();

  /// 撤销一批：软删该批全部流水 + 摘除批次记录 + 收起提示条 + 刷新各视图。
  ///
  /// [batchId] 为空时撤销**当前提示条上的那批**。返回真正软删的条数
  /// （0 = 该批已撤销过 / 不复存在，调用方据此给出明确提示，不要假装成功）。
  Future<int> undo([String? batchId]) async {
    final String? id = batchId ?? state?.batchId;
    if (id == null) return 0;

    final AutoBookBatchStore store = ref.read(autoBookBatchStoreProvider);
    final AutoBookBatch? batch = await store.byId(id) ?? state;
    if (batch == null) return 0;

    final repo = ref.read(transactionRepositoryProvider);
    var deleted = 0;
    for (final String txId in batch.txIds) {
      deleted += await repo.softDelete(txId);
    }
    // 无论删到几笔都摘除记录：同一批不能被撤第二次
    await store.forget(id);
    if (state?.batchId == id) state = null;
    refreshAfterAutoBookWrite(ref);
    return deleted;
  }
}

/// 自动记账写库后的视图刷新（与首页删流水的口径一致 —— 逐个 provider 手工 refresh
/// 是已知脆弱点，这里集中一处）。
///
/// ⚠️ 三个 refresh 都**吞掉异常**：自动记账是后台路径，刷新失败绝不能冒泡成
/// 「未捕获的异步异常」（测试里库已 close、页面上 provider 还没建等场景都会命中）。
void refreshAfterAutoBookWrite(Ref ref) {
  ref.invalidate(yearDayIndexProvider);
  unawaited(ref.read(calendarProvider.notifier).refresh().catchError((Object _) {}));
  unawaited(ref.read(statsProvider.notifier).refresh().catchError((Object _) {}));
  unawaited(ref.read(ledgerProvider.notifier).refresh().catchError((Object _) {}));
  ref.read(dataEpochProvider.notifier).bump();
}
