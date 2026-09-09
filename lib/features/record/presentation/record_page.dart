/// 记一笔 / 编辑流水。
///
/// 对应旧栈 `pages/record/edit.vue`：支出/收入切换 + 金额键盘 + 分类 + 备注。
/// 编辑模式由路由 extra 传入流水 id。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/utils/money.dart';

import '../application/amount_input.dart';
import 'widgets/amount_keyboard.dart';
import 'widgets/category_picker.dart';

/// 记一笔页。[txId] 非空时为编辑模式。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key, this.txId});

  /// 待编辑的流水 id；为空则新建。
  final String? txId;

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  final TextEditingController _noteController = TextEditingController();
  String _type = 'expense';
  String _amount = '';
  String? _categoryId;
  bool _loading = true;
  bool _saving = false;
  List<Category> _categories = <Category>[];

  bool get _isEdit => widget.txId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final categories = await ref
        .read(categoryRepositoryProvider)
        .listByBook(bookId);
    if (widget.txId != null) {
      final tx = await ref
          .read(transactionRepositoryProvider)
          .getById(widget.txId!);
      if (tx != null) {
        _type = tx.type;
        _amount = centsToYuan(tx.amountCents);
        _noteController.text = tx.note;
        _categoryId = tx.categoryId;
      }
    }
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  List<Category> get _visibleCategories =>
      _categories.where((Category c) => c.kind == _type).toList();

  Category? get _selectedCategory {
    for (final c in _categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  Future<void> _pickCategory() async {
    final picked = await showCategoryPicker(
      context,
      categories: _visibleCategories,
    );
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
          note: _noteController.text.trim(),
        );
      } else {
        await repo.create(
          bookId: bookId,
          accountId: accounts.first.id,
          type: _type,
          categoryId: _categoryId,
          amountCents: amountCents,
          occurredAt: DateTime.now().millisecondsSinceEpoch,
          note: _noteController.text.trim(),
        );
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
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑流水' : '记一笔')),
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
                    final stillValid = _categories.any(
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
                value: _selectedCategory?.name,
                placeholder: '请选择分类',
                onTap: _pickCategory,
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
