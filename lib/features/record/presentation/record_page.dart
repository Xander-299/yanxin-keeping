/// 记一笔 / 编辑流水。
///
/// 对应旧栈 `pages/record/edit.vue`：支出/收入切换 + 金额键盘 + 分类 + 备注。
/// 编辑模式由路由 extra 传入流水 id。
///
/// 性能约定：分类列表 watch 已缓存的 `categoriesProvider`（首页加载时就绪），
/// push 首帧即渲染完整页面——**不允许**再加 initState 异步门闩（spinner→二次
/// build 会在转场动画中途换内容，肉眼可见卡顿）；编辑模式的流水详情异步填充。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

import '../application/amount_input.dart';
import 'widgets/amount_keyboard.dart';
import 'widgets/category_picker.dart';

/// 记一笔页。[txId] 非空时为编辑模式。
///
/// [occurredAtMs] 为新建时的默认发生时间（日历页按选中日期带入）；
/// 为空取「现在」。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key, this.txId, this.occurredAtMs});

  /// 待编辑的流水 id；为空则新建。
  final String? txId;

  /// 新建时的默认发生时间（毫秒）；为空取当前时间。
  final int? occurredAtMs;

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  final TextEditingController _noteController = TextEditingController();
  String _type = 'expense';
  String _amount = '';
  String? _categoryId;
  late int _occurredAtMs;
  bool _saving = false;

  bool get _isEdit => widget.txId != null;

  @override
  void initState() {
    super.initState();
    _occurredAtMs =
        widget.occurredAtMs ?? DateTime.now().millisecondsSinceEpoch;
    // 仅编辑模式需要补流水详情；分类数据走缓存 provider，不挡首帧
    if (_isEdit) {
      unawaited(_loadTx());
    }
  }

  Future<void> _loadTx() async {
    final tx = await ref
        .read(transactionRepositoryProvider)
        .getById(widget.txId!);
    if (!mounted || tx == null) return;
    setState(() {
      _type = tx.type;
      _amount = centsToYuan(tx.amountCents);
      _noteController.text = tx.note;
      _categoryId = tx.categoryId;
      _occurredAtMs = tx.occurredAt;
    });
  }

  /// 选日期（上限为今天：未来月份首页翻不过去，记未来账会「看不见」）。
  Future<void> _pickDate() async {
    final DateTime initial = DateTime.fromMillisecondsSinceEpoch(_occurredAtMs);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime last = initial.isAfter(today) ? initial : today;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000, 1, 1),
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // 保留原有时分秒，只换年月日
      _occurredAtMs = DateTime(
        picked.year,
        picked.month,
        picked.day,
        initial.hour,
        initial.minute,
        initial.second,
      ).millisecondsSinceEpoch;
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Category? _selectedCategory(List<Category> categories) {
    for (final c in categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  Future<void> _pickCategory(List<Category> visible) async {
    final picked = await showCategoryPicker(context, categories: visible);
    if (picked != null) {
      setState(() => _categoryId = picked.id);
    }
  }

  Future<void> _save() async {
    if (!isParsableAmount(_amount) || yuanToCents(_amount) <= 0) {
      _toast('请输入金额');
      return;
    }
    if (_categoryId == null) {
      _toast('请选择分类');
      return;
    }
    final bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null) return;
    final accounts = await ref
        .read(accountRepositoryProvider)
        .listByBook(bookId);
    if (accounts.isEmpty) {
      _toast('账本无账户');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final amountCents = yuanToCents(_amount);
      if (_isEdit) {
        await repo.update(
          widget.txId!,
          type: _type,
          categoryId: _categoryId,
          amountCents: amountCents,
          occurredAt: _occurredAtMs,
          note: _noteController.text.trim(),
        );
      } else {
        await repo.create(
          bookId: bookId,
          accountId: accounts.first.id,
          type: _type,
          categoryId: _categoryId,
          amountCents: amountCents,
          occurredAt: _occurredAtMs,
          note: _noteController.text.trim(),
        );
      }
      // 刷新首页 / 日历（go_router push 的 Future 在壳路由下不兑现 .then，
      // 刷新必须在 pop 前由本页自己触发）
      if (ref.context.mounted) {
        unawaited(ref.read(ledgerProvider.notifier).refresh());
        unawaited(ref.read(calendarProvider.notifier).refresh());
        unawaited(ref.read(statsProvider.notifier).refresh());
        ref.invalidate(yearDayIndexProvider);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 首页加载时就已解析并缓存，push 首帧直接有数据；若真未就绪（冷启动直进
    // 编辑模式的极端情况），这一帧退化为轻量占位，provider 完成后自动重渲染
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final visible = categories
        .where((Category c) => c.kind == _type)
        .toList(growable: false);
    final selected = _selectedCategory(categories);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑流水' : '记一笔'),
        // 大屏（如横屏平板/模拟器）下底部按钮会被折叠到视口外，
        // AppBar 常驻保存入口保证「填完就能保存」；底部按钮保留作为主要入口。
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: <Widget>[
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'expense', label: Text('支出')),
                  ButtonSegment<String>(value: 'income', label: Text('收入')),
                ],
                selected: <String>{_type},
                onSelectionChanged: (Set<String> next) {
                  setState(() {
                    _type = next.first;
                    // 切类型后原分类不再适用，清空让用户重选
                    final stillValid = categories.any(
                      (Category c) => c.id == _categoryId && c.kind == _type,
                    );
                    if (!stillValid) _categoryId = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              AmountKeyboard(
                value: _amount,
                onKey: (String key) => setState(
                  () => _amount = applyAmountKey(_amount, key),
                ),
              ),
              const SizedBox(height: 16),
              _FieldTile(
                label: '分类',
                value: selected?.name,
                placeholder: '请选择分类',
                onTap: () => _pickCategory(visible),
              ),
              _FieldTile(
                label: '日期',
                value: formatFullDay(
                  DateTime.fromMillisecondsSinceEpoch(_occurredAtMs),
                ),
                placeholder: '',
                onTap: _pickDate,
              ),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '选填',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_isEdit ? '保存修改' : '记一笔'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value ?? placeholder,
            style: TextStyle(
              color: value == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
