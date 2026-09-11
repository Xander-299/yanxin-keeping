/// 「设置本月预算」底部弹窗。
///
/// 就地设置，不新增路由：常用额度快捷键 + 金额输入 + 保存 / 删除。
/// 保存走 [MonthBudgetController]，成功后只刷新预算卡（不重查流水）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/utils/money.dart';

import '../../application/budget_controller.dart';
import '../../application/budget_metrics.dart';
import '../../application/ledger_controller.dart';

/// 常用额度快捷键（元）。
const List<int> kBudgetPresets = <int>[1000, 2000, 3000, 5000];

/// 弹出设置预算弹窗。[view] 用于回填当前预算。
Future<void> showBudgetEditSheet(
  BuildContext context,
  WidgetRef ref, {
  required BudgetView view,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B1B1D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext _) => _BudgetEditSheet(initialCents: view.budgetCents),
  );
}

class _BudgetEditSheet extends ConsumerStatefulWidget {
  const _BudgetEditSheet({required this.initialCents});

  final int initialCents;

  @override
  ConsumerState<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<_BudgetEditSheet> {
  late final TextEditingController _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 回填：1000.00 → 1000（去掉无意义的 .00，方便直接改）
    final String prefill = widget.initialCents > 0
        ? centsToYuan(widget.initialCents).replaceFirst(RegExp(r'\.00$'), '')
        : '';
    _controller = TextEditingController(text: prefill);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前弹窗对应的月份（取首页真实状态，避免弹窗开着时首页翻月导致写错月份）。
  ({int year, int month}) _month() {
    final LedgerState? ledger = ref.read(ledgerProvider).value;
    final DateTime now = DateTime.now();
    return (
      year: ledger?.year ?? now.year,
      month: ledger?.month ?? now.month,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final String raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请输入预算金额');
      return;
    }
    final int cents;
    try {
      cents = yuanToCents(raw);
    } on FormatException {
      setState(() => _error = '金额格式不对，最多两位小数');
      return;
    }
    if (cents <= 0) {
      setState(() => _error = '金额要大于 0');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // pop 之后 widget 会被销毁，月份与 Navigator 都要先取出来
    final int month = _month().month;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(monthBudgetProvider.notifier).setAmount(cents);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败：$e';
      });
      return;
    }
    if (!mounted) return;
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已设置$month月预算 ¥${centsToYuan(cents, group: true)}'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _clear() async {
    if (_busy) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除本月预算'),
        content: const Text('删除后将不再跟踪本月预算进度，确定删除？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(monthBudgetProvider.notifier).clear();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '删除失败：$e';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ({int year, int month}) ym = _month();
    final bool hasExisting = widget.initialCents > 0;
    return Padding(
      // 键盘弹起时把内容顶上来
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '设置 ${ym.year}年${ym.month}月 预算',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '用于在首页看到本月花销进度与剩余额度',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  prefixText: '¥ ',
                  prefixStyle: const TextStyle(fontSize: 20),
                  hintText: '0.00',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final int preset in kBudgetPresets)
                    ActionChip(
                      label: Text('$preset'),
                      onPressed: () {
                        setState(() {
                          _controller.text = '$preset';
                          _error = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  if (hasExisting)
                    TextButton(
                      onPressed: _busy ? null : _clear,
                      child: const Text('删除预算'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
