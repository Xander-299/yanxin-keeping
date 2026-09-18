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
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';
import 'package:yanxin/features/search/presentation/search_overlay.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

import '../application/ledger_controller.dart';
import 'widgets/budget_card.dart';
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
                  const SliverToBoxAdapter(child: BudgetCard()),
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
    // 统计页同理（常驻 Notifier，不会自己感知删除）
    unawaited(ref.read(statsProvider.notifier).refresh());
    // 资产页 watch 数据版本号，bump 即重算
    ref.read(dataEpochProvider.notifier).bump();
  }
}

/// 顶部栏：左侧账本名（点开抽屉）+ 右侧搜索 / 报表（占位）/ 统计。
class _Header extends StatelessWidget {
  const _Header({required this.bookName});

  final String bookName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ToonPress(
              dx: 0,
              dy: 0,
              onTap: Scaffold.maybeOf(context)?.openDrawer,
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
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: Tok.ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 24, color: Tok.ink),
                ],
              ),
            ),
          ),
          ToonIconButton(
            icon: Icons.search_rounded,
            tooltip: '搜索',
            boxed: true,
            // F7.5：不再是独立路由，改为覆盖在首页之上的浮层（首页留在底下当背景）
            onPressed: () => unawaited(showSearchOverlay(context)),
          ),
          ToonIconButton(
            icon: Icons.receipt_long_rounded,
            tooltip: '报表（建设中）',
            boxed: true,
            muted: true,
            onPressed: () => _toast(context, '报表 · 建设中'),
          ),
          ToonIconButton(
            icon: Icons.bar_chart_rounded,
            tooltip: '统计',
            boxed: true,
            onPressed: () => context.push('/stats'),
          ),
        ],
      ),
    );
  }
}

/// 「本月账单」区头 + 全部账单占位入口。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return ToonSectionTitle(
      title: '本月账单',
      trailing: ToonPress(
        dx: 2,
        dy: 2,
        onTap: () => _toast(context, '全部账单 · 建设中'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Tok.paper,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Tok.ink, width: 2),
            boxShadow: Tok.hard(d: 2.5),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '全部账单',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              Icon(Icons.chevron_right, size: 15, color: Tok.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// 统一的占位提示。
void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 16, 16),
      child: Row(
        children: <Widget>[
          const Icon(Icons.receipt_long_rounded, size: 22, color: Tok.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$year年$month月还没有记账',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                const Text(
                  '已有微信 / 支付宝账单？到「我的 → 导入账单」一键导入',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/record'),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('记一笔'),
            style: TextButton.styleFrom(
              foregroundColor: Tok.brandDeep,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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
