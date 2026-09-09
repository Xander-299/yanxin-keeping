/// 首页：结余主卡（月份切换）+ 按天分组的流水列表 + 记一笔入口。
///
/// 对应旧栈 `pages/index/index.vue`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';

import '../application/ledger_controller.dart';
import 'widgets/month_hero.dart';
import 'widgets/tx_group_list.dart';

/// 首页。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    final bookAsync = ref.watch(currentBookProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final nameOf = _categoryNameResolver(categoriesAsync.value);

    return Scaffold(
      appBar: AppBar(
        title: Text(bookAsync.value?.name ?? '颜芯记账'),
        actions: <Widget>[
          IconButton(
            tooltip: '账本管理',
            icon: const Icon(Icons.import_contacts_outlined),
            onPressed: () => context.push<bool?>('/books').then((bool? changed) {
              if (changed ?? false) ref.invalidate(ledgerProvider);
            }),
          ),
          IconButton(
            tooltip: '分类管理',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => context.push('/categories'),
          ),
        ],
      ),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
        data: (LedgerState state) {
          return Column(
            children: <Widget>[
              MonthHero(
                year: state.year,
                month: state.month,
                summary: state.summary,
                canNext: canGoNext(state.year, state.month),
                onPrevMonth: () =>
                    ref.read(ledgerProvider.notifier).shiftMonth(-1),
                onNextMonth: () =>
                    ref.read(ledgerProvider.notifier).shiftMonth(1),
              ),
              Expanded(
                child: state.items.isEmpty
                    ? _EmptyMonth(year: state.year, month: state.month)
                    : TxGroupList(
                        items: state.items,
                        categoryNameOf: nameOf,
                        onEdit: (TxRow tx) => context
                            .push<bool?>('/record', extra: tx.id)
                            .then((bool? changed) {
                              if (changed ?? false) {
                                ref.read(ledgerProvider.notifier).refresh();
                              }
                            }),
                        onDelete: (TxRow tx) => _confirmDelete(context, ref, tx),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '记一笔',
        onPressed: () => context.push<bool?>('/record').then((bool? changed) {
          if (changed ?? false) ref.read(ledgerProvider.notifier).refresh();
        }),
        child: const Icon(Icons.add),
      ),
    );
  }

  String Function(String?) _categoryNameResolver(List<Category>? categories) {
    if (categories == null) {
      return (String? _) => '未分类';
    }
    final map = <String, String>{
      for (final c in categories) c.id: c.name,
    };
    return (String? id) => (id == null ? null : map[id]) ?? '未分类';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TxRow tx,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除这笔'),
        content: const Text('删除后在回收站保留，确定删除？'),
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
    if (ok ?? false) {
      await ref.read(ledgerProvider.notifier).removeTx(tx.id);
    }
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth({required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircleAvatar(radius: 28, child: Text('记')),
          const SizedBox(height: 16),
          Text('$year年$month月还没有记账'),
          const SizedBox(height: 8),
          Text(
            '点右下角的 ＋ 记下第一笔吧',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
