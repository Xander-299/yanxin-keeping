/// 首页：账本 header + hero 月支出卡 + 预算占位卡 + 本月账单列表。
///
/// 视觉对齐 app_template/home_ui.jpg；对应旧栈 `pages/index/index.vue`。
/// 页面本身无 Scaffold（壳路由 AppShell 提供抽屉与底栏）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';

import '../application/ledger_controller.dart';
import 'widgets/budget_card_placeholder.dart';
import 'widgets/month_hero.dart';
import 'widgets/tx_delete_dialog.dart';
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

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          _Header(bookName: bookAsync.value?.name ?? '…'),
          Expanded(
            child: ledger.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace _) =>
                  Center(child: Text('加载失败：$e')),
              data: (LedgerState state) => CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: MonthHero(
                      year: state.year,
                      month: state.month,
                      summary: state.summary,
                      canNext: canGoNext(state.year, state.month),
                      onPrevMonth: () =>
                          ref.read(ledgerProvider.notifier).shiftMonth(-1),
                      onNextMonth: () =>
                          ref.read(ledgerProvider.notifier).shiftMonth(1),
                    ),
                  ),
                  const SliverToBoxAdapter(child: BudgetCardPlaceholder()),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  const SliverToBoxAdapter(child: _SectionHeader()),
                  if (state.items.isEmpty)
                    SliverToBoxAdapter(
                      child: _EmptyMonth(
                        year: state.year,
                        month: state.month,
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: TxGroupList(
                        items: state.items,
                        categoryNameOf: nameOf,
                        shrinkWrap: true,
                        onEdit: (TxRow tx) =>
                            context.push('/record', extra: tx.id),
                        onDelete: (TxRow tx) => _confirmDelete(context, ref, tx),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ],
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
    if (!await confirmDeleteTx(context)) return;
    await ref.read(ledgerProvider.notifier).removeTx(tx.id);
    ref.invalidate(yearDayIndexProvider);
    // 日历是同月数据的另一视图，保持一致
    unawaited(ref.read(calendarProvider.notifier).refresh());
  }
}

/// 顶部栏：左侧账本名（点开抽屉）+ 右侧三个占位图标。
class _Header extends StatelessWidget {
  const _Header({required this.bookName});

  final String bookName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkResponse(
              onTap: Scaffold.maybeOf(context)?.openDrawer,
              radius: 28,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      bookName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 24),
                ],
              ),
            ),
          ),
          const _HeaderIcon(icon: Icons.search_rounded, tooltip: '搜索（建设中）'),
          const _HeaderIcon(
            icon: Icons.receipt_long_rounded,
            tooltip: '报表（建设中）',
          ),
          _HeaderIcon(
            icon: Icons.pie_chart_outline_rounded,
            tooltip: '统计',
            onPressed: () => context.push('/stats'),
          ),
        ],
      ),
    );
  }
}

/// header 图标：默认提示「建设中」，给了 [onPressed] 则执行真实动作。
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed:
          onPressed ??
          () {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('功能建设中，敬请期待'),
                  duration: Duration(seconds: 1),
                ),
              );
          },
      icon: Icon(icon, size: 22),
    );
  }
}

/// 「本月账单」区头 + 全部账单占位入口。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: <Widget>[
          const Text(
            '本月账单',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('全部账单 · 建设中'),
                    duration: Duration(seconds: 1),
                  ),
                );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '全部账单',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态：必须「不用滚动就能看到」。
///
/// 首页 hero + 预算卡已占满首屏（横屏/大屏尤其明显），因此这里走紧凑单行，
/// 而不是大图标居中块 —— 大块空态会被挤到折叠下方，用户只看到「本月账单」下一片空白。
class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth({required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 12),
      child: Row(
        children: <Widget>[
          Icon(Icons.receipt_long_rounded, size: 20, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$year年$month月还没有记账',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  '已有微信 / 支付宝账单？到「我的 → 导入账单」一键导入',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/record'),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('记一笔'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
