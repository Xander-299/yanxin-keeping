/// 导入账单页：选文件 → 解析预览（可单条取消）→ 确认导入 → 结果报告。
///
/// F7.6 P3 按原型 `scrImport` 改为**三步页**（步骤条 + 虚线投放区 + 勾选列表 + 报告卡），
/// 报告由原来的 AlertDialog 变成第 3 步页面 —— 步骤条能把「现在到哪一步」说清楚。
///
/// [pickBytesOverride] 供测试注入文件字节（绕过平台文件选择器）。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/book_providers.dart';
import '../../../core/providers/data_epoch.dart';
import '../../../core/providers/database.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/toon.dart';
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
  String? _fileName;

  // ── 第 3 步（导入报告）的状态快照 ──
  ImportReport? _report;
  bool _hasNew = false;
  int _activeRows = 0;
  ({int year, int month})? _target;

  /// 当前步骤：有报告 = 3，有解析结果 = 2，否则 1。由数据推导，不额外存状态。
  int get _step => _report != null ? 3 : (_parsed != null ? 2 : 1);

  void _resetToPick() {
    setState(() {
      _parsed = null;
      _cancelled = const <bool>[];
      _fileName = null;
      _report = null;
      _target = null;
    });
  }

  /// 第 1 步返回 = 退出页面；第 2 / 3 步返回 = 回到选文件（重来一遍）。
  void _back() {
    if (_step == 1) {
      context.pop();
    } else {
      _resetToPick();
    }
  }

  Future<void> _pickAndParse() async {
    setState(() {
      _parsing = true;
      _parsed = null;
      _fileName = null;
    });
    try {
      List<int>? bytes;
      String? name;
      if (widget.pickBytesOverride != null) {
        bytes = await widget.pickBytesOverride!();
      } else {
        // file_picker 12：静态入口 + readAsBytes（withData 已废弃）
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['csv', 'xlsx'],
        );
        if (file != null) {
          bytes = await file.readAsBytes();
          name = file.name;
        }
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _parsing = false);
        return; // 用户取消选择
      }
      final parsed = parseBillFileAuto(bytes);
      setState(() {
        _parsed = parsed;
        _cancelled = List<bool>.filled(parsed.rows.length, false);
        _fileName = name;
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
      // 资产页 watch 数据版本号，bump 即重算
      ref.read(dataEpochProvider.notifier).bump();
      if (!mounted) return;
      setState(() {
        _importing = false;
        _report = report;
        _hasNew = report.imported > 0;
        _activeRows = _cancelled.where((bool c) => !c).length;
        // 导入的账单几乎都属于历史月份，首页停在当前月会「看起来什么都没发生」
        // → 报告里说明数据落在哪个月，并给一个直达入口。
        _target = _latestMonthOf(parsed.rows, _cancelled);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _goToLedger() async {
    final target = _target;
    if (target == null) return;
    await ref
        .read(ledgerProvider.notifier)
        .jumpToMonth(target.year, target.month);
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tok.paper,
      appBar: AppBar(
        title: const Text('导入账单'),
        leading: BackButton(onPressed: _back),
      ),
      body: _parsing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                _StepBar(step: _step),
                Expanded(
                  child: switch (_step) {
                    1 => _PickBody(onPick: _pickAndParse),
                    2 => _buildPreviewBody(context, _parsed!),
                    _ => _buildReportBody(context),
                  },
                ),
              ],
            ),
    );
  }

  // ────────────────────────────── 第 2 步：预览 ──────────────────────────────

  Widget _buildPreviewBody(BuildContext context, BillParseResult parsed) {
    final stats = parsed.stats;
    final int activeCount = _cancelled.where((bool c) => !c).length;
    final bool allSelected = activeCount == _cancelled.length;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ToonCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      '解析结果',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName ?? '账单文件',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tok.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '识别为「${parsed.source == 'wechat_csv' ? '微信支付' : '支付宝'}」账单',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text(
                      '可导入 $activeCount 笔',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '已跳过 ${stats.skipped} 笔（退款 / 不计收支）'
                        '${stats.malformed > 0 ? ' · 坏行 ${stats.malformed}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tok.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  children: <Widget>[
                    Icon(Icons.check_box_outlined, size: 16, color: Tok.ink2),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '勾选的条目会导入，点条目可取消它',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tok.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Row(
            children: <Widget>[
              Text(
                '已选 $activeCount / ${_cancelled.length} 条',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                ),
              ),
              const Spacer(),
              _LinkButton(
                label: allSelected ? '全不选' : '全选',
                onTap: () => setState(
                  () => _cancelled = List<bool>.filled(
                    _cancelled.length,
                    allSelected,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ToonCard(
              padding: EdgeInsets.zero,
              clip: true,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: parsed.rows.length,
                itemBuilder: (BuildContext context, int i) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (i > 0) const ToonDashedLine(),
                    _ImpRow(
                      index: i,
                      row: parsed.rows[i],
                      cancelled: _cancelled[i],
                      onToggle: () =>
                          setState(() => _cancelled[i] = !_cancelled[i]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Opacity(
                  opacity: activeCount > 0 && !_importing ? 1 : 0.5,
                  child: ToonButton(
                    block: true,
                    label: _importing ? '导入中…' : '确认导入（$activeCount 笔）',
                    onPressed: activeCount > 0 && !_importing
                        ? _confirmImport
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '单事务写入 + 指纹去重，失败整批回滚',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────── 第 3 步：报告 ──────────────────────────────

  Widget _buildReportBody(BuildContext context) {
    final BillParseResult parsed = _parsed!;
    final ImportReport report = _report!;
    final bool hasNew = _hasNew;
    final ({int year, int month})? target = _target;
    // 行间插虚线（原型 `.kv + .kv`）—— 条件行太多，先收集再交错
    final List<Widget> kvs = <Widget>[
      _Kv(label: '读取行数', value: '${parsed.stats.dataRows}'),
      _Kv(label: '跳过（退款 / 不计收支）', value: '${parsed.stats.skipped}'),
      _Kv(
        label: '未命中分类规则 → 其他',
        value: '${hasNew ? report.uncategorized : 0}',
      ),
      _Kv(label: '本次真正入库', value: '${report.imported}'),
      if (report.duplicates > 0)
        _Kv(label: '重复跳过（指纹一致）', value: '${report.duplicates}'),
      if (report.fileDuplicates > 0)
        _Kv(label: '文件内重复', value: '${report.fileDuplicates}'),
      if (report.cancelled > 0)
        _Kv(label: '已取消', value: '${report.cancelled}'),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ToonCard(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hasNew ? Tok.greenTint : Tok.track,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Tok.ink, width: 2),
                        boxShadow: Tok.hard(d: 2),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 24,
                        color: hasNew ? Tok.green : Tok.ink3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            hasNew ? '导入完成' : '没有新增',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasNew
                                ? '已写入当前账本'
                                      '${target == null ? '' : ' · ${_fmtMonth(target)}'}'
                                      ' · 成功导入 ${report.imported} 笔'
                                : '这 $_activeRows 笔之前已经导入过了，没有重复记账',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Tok.ink2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasNew)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '${report.imported}',
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Tok.green,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '笔新增',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Tok.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                for (int i = 0; i < kvs.length; i++) ...<Widget>[
                  if (i > 0) const ToonDashedLine(),
                  kvs[i],
                ],
              ],
            ),
          ),
        ),
        if (hasNew && target != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '其中 $_activeRows 笔属于 ${_fmtMonth(target)}，点「去看账单」直接翻到该月',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
                height: 1.7,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: <Widget>[
              if (target != null) ...<Widget>[
                ToonButton(
                  block: true,
                  label: '去看账单',
                  onPressed: _goToLedger,
                ),
                const SizedBox(height: 10),
              ],
              ToonButton(
                block: true,
                label: '再导入一个文件',
                kind: ToonButtonKind.ghost,
                onPressed: _resetToPick,
              ),
              const SizedBox(height: 10),
              const Text(
                '导入后自动跳到数据所在月份；重复导入不会产生任何重复流水',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
}

// ────────────────────────────── 步骤条 ──────────────────────────────

/// 三步进度条：已完成打勾、当前步填品牌色 + 硬阴影，步与步之间是虚线。
class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});

  final int step;

  static const List<String> _labels = <String>['选择文件', '预览确认', '导入报告'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _labels.length; i++) ...<Widget>[
            if (i > 0)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: ToonDashedLine(color: Tok.dash, dash: 5, gap: 4),
                ),
              ),
            _StepNode(
              n: i + 1,
              label: _labels[i],
              state: step == i + 1
                  ? _StepState.on
                  : (step > i + 1 ? _StepState.done : _StepState.off),
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { on, done, off }

class _StepNode extends StatelessWidget {
  const _StepNode({required this.n, required this.label, required this.state});

  final int n;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final bool done = state == _StepState.done;
    final bool on = state == _StepState.on;
    return Row(
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done
                ? Tok.greenTint
                : (on ? Tok.brand : Tok.paper),
            shape: BoxShape.circle,
            border: Border.all(color: Tok.ink, width: 2),
            boxShadow: on ? Tok.hard(d: 2) : null,
          ),
          child: done
              ? const Icon(Icons.check, size: 14, color: Tok.green)
              : Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: on ? Tok.brandInk : Tok.ink2,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w900 : FontWeight.w700,
            color: on ? Tok.ink : Tok.ink3,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────── 第 1 步：选文件 ──────────────────────────────

class _PickBody extends StatelessWidget {
  const _PickBody({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tok.rXl),
              boxShadow: Tok.hard(),
            ),
            child: ToonDashedBorder(
              radius: Tok.rXl,
              thickness: 3,
              color: Tok.ink,
              dash: 9,
              gap: 6,
              background: Tok.brandTint,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      Icons.description_outlined,
                      size: 38,
                      color: Tok.brandDeep,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '选择微信 / 支付宝账单文件',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '微信：微信支付账单流水文件（.xlsx，ZIP 解压后解析）\n'
                      '支付宝：支付宝交易明细（.csv，GBK 编码自动识别）',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Tok.ink2,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ToonButton(
                      icon: Icons.folder_open_rounded,
                      label: '选择文件',
                      small: true,
                      onPressed: onPick,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '导入规则',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '· 二次导入同一文件 → 0 新增（指纹幂等，PRD ADR-7）\n'
                '· 退款 / 不计收支行自动跳过\n'
                '· 关键词规则自动归类，未命中落「其他」\n'
                '· 金额按整数分入库，交易单号按字符串保留',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                  height: 1.9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────── 预览列表行 ──────────────────────────────

class _ImpRow extends StatelessWidget {
  const _ImpRow({
    required this.index,
    required this.row,
    required this.cancelled,
    required this.onToggle,
  });

  final int index;
  final ParsedRow row;
  final bool cancelled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bool income = row.direction == 'income';
    final String estimate = categorizeRow(row).categoryName;
    return ToonPress(
      key: ValueKey<String>('imp-row-$index'),
      dx: 2,
      dy: 2,
      onTap: onToggle,
      child: Container(
        color: cancelled ? Tok.canvas2 : Tok.paper,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            _CheckBox(on: !cancelled),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${row.counterparty}'
                    '${row.product.isEmpty ? '' : ' · ${row.product}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cancelled ? Tok.ink3 : Tok.ink,
                      decoration: cancelled
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtTime(row.occurredAt)} · $estimate',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Tok.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${income ? '+' : '-'}${centsToYuan(row.amountCents)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cancelled ? Tok.ink3 : (income ? Tok.green : Tok.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方勾选框（原型 `.cb`：22 网格 + 2.5px 描边 + 硬阴影）。
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? Tok.brand : Tok.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Tok.ink, width: 2.5),
        boxShadow: Tok.hard(d: 1.5),
      ),
      child: on ? const Icon(Icons.check, size: 14, color: Tok.brandInk) : null,
    );
  }
}

/// 文字链按钮（原型 `.linkbtn`）。
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 1.5,
      dy: 1.5,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Tok.brandDeep,
            decoration: TextDecoration.underline,
            decorationThickness: 2,
          ),
        ),
      ),
    );
  }
}

/// 报告里的键值行（原型 `.kv`，行间由调用方插虚线）。
class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// 预览行的时间格式（`2026-08-01 12:00`）。
String _fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd $hh:$mi';
}
