/// 导入账单页：选文件 → 解析预览（可单条取消）→ 确认导入 → 结果报告。
///
/// [pickBytesOverride] 供测试注入文件字节（绕过平台文件选择器）。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/book_providers.dart';
import '../../../core/providers/database.dart';
import '../../../core/utils/money.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../ledger/application/ledger_controller.dart';
import '../../stats/application/stats_controller.dart';
import '../application/bill_importer.dart';
import '../data/bill_normalize.dart';
import '../data/bill_parse.dart';
import '../data/category_rules.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.pickBytesOverride});

  final Future<List<int>?> Function()? pickBytesOverride;

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  bool _parsing = false;
  bool _importing = false;
  BillParseResult? _parsed;
  List<bool> _cancelled = const [];

  Future<void> _pickAndParse() async {
    setState(() {
      _parsing = true;
      _parsed = null;
    });
    try {
      List<int>? bytes;
      if (widget.pickBytesOverride != null) {
        bytes = await widget.pickBytesOverride!();
      } else {
        // file_picker 12：静态入口 + readAsBytes（withData 已废弃）
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['csv', 'xlsx'],
        );
        if (file != null) bytes = await file.readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _parsing = false);
        return; // 用户取消选择
      }
      final parsed = parseBillFileAuto(bytes);
      setState(() {
        _parsed = parsed;
        _cancelled = List<bool>.filled(parsed.rows.length, false);
        _parsing = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _parsing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _parsing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取文件失败：$e')),
      );
    }
  }

  Future<void> _confirmImport() async {
    final parsed = _parsed;
    if (parsed == null || _importing) return;
    setState(() => _importing = true);
    try {
      // activeBookIdProvider 首次构建是真实异步读库，必须 await future
      final book = await ref.read(currentBookProvider.future);
      if (book == null) throw StateError('当前账本未就绪');
      final db = ref.read(appDatabaseProvider);
      final accountId = await ensureImportAccount(AccountRepository(db), book.id);
      final maps = await buildCategoryMaps(CategoryRepository(db), book.id);
      final report = await importRows(
        db,
        bookId: book.id,
        accountId: accountId,
        categoryMaps: maps,
        rows: parsed.rows,
        options: [
          for (final c in _cancelled) RowOption(cancelled: c),
        ],
      );
      // 导入改变了首页数据，主动刷新（go_router push 的 .then 在壳路由下不兑现）
      await ref.read(ledgerProvider.notifier).refresh();
      // 统计页是常驻 Notifier，也要跟着刷新（导入常落历史月，翻回去才看得到）
      unawaited(ref.read(statsProvider.notifier).refresh());
      if (!mounted) return;
      setState(() => _importing = false);
      // 导入的账单几乎都属于历史月份，首页停在当前月会「看起来什么都没发生」
      // → 报告里说明数据落在哪个月，并给一个直达入口。
      final target = _latestMonthOf(parsed.rows, _cancelled);
      final activeRows = _cancelled.where((bool c) => !c).length;
      final hasNew = report.imported > 0;
      var goToLedger = false;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          // 幂等重复导入时「导入完成 / 成功导入 0 笔」自相矛盾 → 按结果分叉标题
          title: Text(hasNew ? '导入完成' : '没有新增'),
          content: Text(
            _reportText(
              report,
              hasNew: hasNew,
              activeRows: activeRows,
              target: target,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('完成'),
            ),
            if (target != null)
              FilledButton(
                onPressed: () {
                  goToLedger = true;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('去看账单'),
              ),
          ],
        ),
      );
      if (!mounted) return;
      if (goToLedger && target != null) {
        await ref
            .read(ledgerProvider.notifier)
            .jumpToMonth(target.year, target.month);
        if (!mounted) return;
        context.go('/');
      } else {
        context.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入账单'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: _parsing
          ? const Center(child: CircularProgressIndicator())
          : parsed == null
              ? _buildPickBody(context)
              : _buildPreviewBody(context, parsed),
    );
  }

  Widget _buildPickBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.file_upload_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text('支持微信 / 支付宝导出的账单文件'),
            const SizedBox(height: 4),
            Text(
              '微信支付 xlsx / CSV，支付宝 CSV（自动识别编码）',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pickAndParse,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('选择文件'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody(BuildContext context, BillParseResult parsed) {
    final stats = parsed.stats;
    final activeCount =
        _cancelled.where((c) => !c).length;
    final allSelected = activeCount == _cancelled.length;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '识别为「${parsed.source == 'wechat_csv' ? '微信支付' : '支付宝'}」账单',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '数据 ${stats.dataRows} 行 · 可导入 $activeCount · '
                    '自动跳过 ${stats.skipped} · 坏行 ${stats.malformed}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.check_box_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '勾选的条目会导入，点条目可取消它',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => _cancelled = List<bool>.filled(
                            _cancelled.length,
                            allSelected,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(allSelected ? '全不选' : '全选'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: parsed.rows.length,
            itemBuilder: (BuildContext context, int i) {
              final row = parsed.rows[i];
              final cancelled = _cancelled[i];
              final estimate = categorizeRow(row);
              return CheckboxListTile(
                value: !cancelled,
                onChanged: (bool? v) =>
                    setState(() => _cancelled[i] = !(v ?? false)),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '${row.counterparty}${row.product.isEmpty ? '' : ' · ${row.product}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cancelled
                      ? TextStyle(
                          color: Theme.of(context).disabledColor,
                          decoration: TextDecoration.lineThrough,
                        )
                      : null,
                ),
                subtitle: Text(
                  '${_fmtTime(row.occurredAt)} · 预估 ${estimate.categoryName}',
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: Text(
                  '${row.direction == 'expense' ? '-' : '+'}'
                  '${centsToYuan(row.amountCents)}',
                  style: TextStyle(
                    color: row.direction == 'expense'
                        ? const Color(0xFFEF5350)
                        : const Color(0xFF66BB6A),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: activeCount > 0 && !_importing ? _confirmImport : null,
                child: Text(_importing ? '导入中…' : '确认导入（$activeCount 笔）'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 报告正文：按「是否真的有新增」分叉，零新增时不出现与「没有新增」矛盾的数字。
  String _reportText(
    ImportReport report, {
    required bool hasNew,
    required int activeRows,
    required ({int year, int month})? target,
  }) {
    final lines = <String>[];
    if (hasNew) {
      lines.add('成功导入 ${report.imported} 笔');
      if (report.duplicates > 0) lines.add('重复跳过 ${report.duplicates} 笔');
      if (report.fileDuplicates > 0) {
        lines.add('文件内重复 ${report.fileDuplicates} 笔');
      }
      if (report.cancelled > 0) lines.add('已取消 ${report.cancelled} 笔');
      // 未匹配分类只对真正入库的行有意义（重复跳过时显示会自相矛盾）
      if (report.uncategorized > 0) {
        lines.add('未匹配分类 ${report.uncategorized} 笔（暂归「其他」）');
      }
      if (target != null) {
        lines.add('');
        lines.add(
          '其中 $activeRows 笔属于 ${_fmtMonth(target)}，点「去看账单」直接翻到该月',
        );
      }
    } else {
      lines.add('这 $activeRows 笔之前已经导入过了，没有重复记账。');
      if (report.duplicates > 0) lines.add('重复跳过 ${report.duplicates} 笔');
      if (report.fileDuplicates > 0) {
        lines.add('文件内重复 ${report.fileDuplicates} 笔');
      }
      if (report.cancelled > 0) lines.add('已取消 ${report.cancelled} 笔');
    }
    return lines.join('\n');
  }

  /// 未取消行中最晚的账单月份（导入后跳到这个月，用户才看得到结果）。
  ({int year, int month})? _latestMonthOf(
    List<ParsedRow> rows,
    List<bool> cancelled,
  ) {
    int? latest;
    for (var i = 0; i < rows.length; i++) {
      if (i < cancelled.length && cancelled[i]) continue;
      final ms = rows[i].occurredAt;
      if (latest == null || ms > latest) latest = ms;
    }
    if (latest == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(latest);
    return (year: d.year, month: d.month);
  }

  String _fmtMonth(({int year, int month}) m) =>
      '${m.year}-${m.month.toString().padLeft(2, '0')}';

  String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd $hh:$mi';
  }
}
