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
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
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

  /// 选分类。弹层内部可切支出/收入，故传全量分类，并以选中项的 kind 回写类型。
  Future<void> _pickCategory(List<Category> all) async {
    final picked = await showCategoryPicker(
      context,
      categories: all,
      kind: _type,
      selectedId: _categoryId,
    );
    if (picked == null) return;
    setState(() {
      _categoryId = picked.id;
      _type = picked.kind;
    });
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
        // 资产页 watch 数据版本号，bump 即重算
        ref.read(dataEpochProvider.notifier).bump();
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
    final selected = _selectedCategory(categories);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑流水' : '记一笔'),
        // 大屏（如横屏平板/模拟器）下底部按钮会被折叠到视口外，
        // AppBar 常驻保存入口保证「填完就能保存」；底部按钮保留作为主要入口。
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            style: TextButton.styleFrom(
              foregroundColor: Tok.brandDeep,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            children: <Widget>[
              Center(
                child: ToonSeg(
                  labels: const <String>['支出', '收入'],
                  index: _type == 'income' ? 1 : 0,
                  onChanged: (int i) {
                    setState(() {
                      _type = i == 1 ? 'income' : 'expense';
                      // 切类型后原分类不再适用，清空让用户重选
                      final bool stillValid = categories.any(
                        (Category c) => c.id == _categoryId && c.kind == _type,
                      );
                      if (!stillValid) _categoryId = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 14),
              AmountKeyboard(
                value: _amount,
                onKey: (String key) => setState(
                  () => _amount = applyAmountKey(_amount, key),
                ),
              ),
              const SizedBox(height: 6),
              ToonField(
                label: '分类',
                value: selected?.name ?? '请选择分类',
                placeholder: selected == null,
                onTap: () => _pickCategory(categories),
                trailing: selected == null
                    ? null
                    : ToonAvatar(
                        text: selected.name.isEmpty
                            ? '?'
                            : selected.name.substring(0, 1),
                        small: true,
                        bg: _type == 'income' ? Tok.greenTint : Tok.redTint,
                        fg: _type == 'income' ? Tok.green : Tok.red,
                      ),
              ),
              ToonField(
                label: '日期',
                value: formatFullDay(
                  DateTime.fromMillisecondsSinceEpoch(_occurredAtMs),
                ),
                onTap: _pickDate,
                dashedTop: true,
              ),
              ToonField(
                label: '备注',
                dashedTop: true,
                child: TextField(
                  controller: _noteController,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                  // 原型这里是裸 input（`style="border:0"`）：必须逐项关掉主题的
                  // 填充 + 描边，否则 `InputDecoration.collapsed` 仍会吃到
                  // `inputDecorationTheme.filled` 渲染出一个白框。
                  decoration: const InputDecoration(
                    hintText: '选填',
                    hintStyle: TextStyle(
                      color: Tok.ink3,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ToonButton(
                label: _isEdit ? '保存修改' : '记一笔',
                block: true,
                onPressed: _saving ? null : _save,
              ),
              const SizedBox(height: 10),
              const Text(
                '保存后首页 / 日历 / 统计 / 资产同步刷新',
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
    );
  }
}
