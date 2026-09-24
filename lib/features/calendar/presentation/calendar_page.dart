/// 日历页：月份 header + 月历（每天标支出/收入）+ 月结余/日均支出 + 选中日账单。
///
/// 视觉参考 app_template/calendar.jpg（布局对齐，配色沿用 App 深色 + 琥珀）。
/// 页面无 Scaffold（壳路由 AppShell 提供抽屉与底栏）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_delete_dialog.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_group_list.dart';
import 'package:yanxin/features/reports/application/reports_controller.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

import '../application/calendar_controller.dart';
import 'widgets/month_grid.dart';

/// 日历页。
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CalendarState> calendar = ref.watch(calendarProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final nameOf = _categoryNameResolver(categoriesAsync.value);

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          const _HeaderBody(),
          Expanded(
            child: calendar.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
              data: (CalendarState state) => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      // 原型 `.cal { padding: 6px 8px 0 }`
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: MonthGrid(
                        year: state.year,
                        month: state.month,
                        byDay: state.byDay,
                        selectedDay: state.selectedDay,
                        onSelectDay: (int day) =>
                            ref.read(calendarProvider.notifier).selectDay(day),
                        // F7.7 E 批：长按某天 → 直接记这一天的账（顺带把那天选中，
                        // 回来就能看到刚记的那笔）；左右滑动 → 翻月
                        onLongPressDay: (DateTime day) {
                          ref.read(calendarProvider.notifier).selectDay(day.day);
                          context.push(
                            '/record?date=${day.millisecondsSinceEpoch}',
                          );
                        },
                        onShiftMonth: (int delta) =>
                            ref.read(calendarProvider.notifier).shiftMonth(delta),
                      ),
                    ),
                    // 网格与月结余卡之间不再另加间距：原型是 `.day` 的 2px 外边距
                    // + `.summary-bar` 的 10px margin（= 12px），由卡的 margin 承担。
                    _SummaryBar(state: state),
                    const SizedBox(height: 8),
                    _SelectedDaySection(
                      state: state,
                      categoryNameOf: nameOf,
                      onEdit: (TxRow tx) =>
                          context.push('/record', extra: tx.id),
                      onDelete: (TxRow tx) => _confirmDelete(context, ref, tx),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
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
      for (final Category c in categories) c.id: c.name,
    };
    return (String? id) => (id == null ? null : map[id]) ?? '未分类';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TxRow tx,
  ) async {
    if (!await confirmDeleteTx(context)) return;
    await ref.read(calendarProvider.notifier).removeTx(tx.id);
    ref.invalidate(yearDayIndexProvider);
    // 首页是同月数据的另一视图，保持一致
    unawaited(ref.read(ledgerProvider.notifier).refresh());
    // 统计页同理（常驻 Notifier，不会自己感知删除）
    unawaited(ref.read(statsProvider.notifier).refresh());
    // 资产页 watch 数据版本号，bump 即重算
    ref.read(dataEpochProvider.notifier).bump();
  }
}

/// 顶部栏：左侧侧面栏（抽屉）+ 中间年月（点开月份选择子页）+ 报表(建设中) + 统计。
///
/// 日历页 header 用的是原型 `.hdr`（不是 `.appbar`），所以图标是**带框**的。
class _HeaderBody extends ConsumerWidget {
  const _HeaderBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int year =
        ref.watch(
          calendarProvider.select(
            (AsyncValue<CalendarState> v) => v.value?.year,
          ),
        ) ??
        DateTime.now().year;
    final int month =
        ref.watch(
          calendarProvider.select(
            (AsyncValue<CalendarState> v) => v.value?.month,
          ),
        ) ??
        DateTime.now().month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: <Widget>[
          ToonIconButton(
            icon: Icons.menu_rounded,
            tooltip: '账本',
            boxed: true,
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
          ),
          Expanded(
            child: Center(
              child: ToonPress(
                dx: 0,
                dy: 0,
                onTap: () => context.push('/month-picker'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$year年$month月',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ToonIconButton(
            icon: Icons.receipt_long_rounded,
            tooltip: '报表',
            boxed: true,
            // 「明细」档 + 月份对齐日历页当前月（SPEC-F7.7 §A.2.3）
            onPressed: () => context.push(
              '/reports',
              extra: ReportsArgs(
                tab: kReportTabDetail,
                year: year,
                month: month,
              ),
            ),
          ),
          ToonIconButton(
            icon: Icons.pie_chart_outline_rounded,
            tooltip: '统计',
            boxed: true,
            onPressed: () => context.push('/stats'),
          ),
        ],
      ),
    );
  }
}

/// 月结余 + 日均支出。
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.state});

  final CalendarState state;

  @override
  Widget build(BuildContext context) {
    final int balance = state.summary.balanceCents;
    final Color balanceColor = balance < 0
        ? kExpenseRed
        : balance > 0
        ? kIncomeGreen
        : Tok.ink;
    return Container(
      // 原型 `.summary-bar { margin: 10px 16px; padding: 13px 16px }`
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: Tok.cardDeco(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _SummaryItem(
            label: '月结余',
            value: centsToYuan(balance),
            valueColor: balanceColor,
          ),
          _SummaryItem(
            label: '日均支出',
            value: centsToYuan(state.dailyAvgExpenseCents),
            valueColor: kExpenseRed,
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// 选中日期的账单区：日期头 + 账单列表 / 空态。
class _SelectedDaySection extends StatelessWidget {
  const _SelectedDaySection({
    required this.state,
    required this.categoryNameOf,
    required this.onEdit,
    required this.onDelete,
  });

  final CalendarState state;
  final String Function(String?) categoryNameOf;
  final ValueChanged<TxRow> onEdit;
  final ValueChanged<TxRow> onDelete;

  @override
  Widget build(BuildContext context) {
    final DateTime day = DateTime(state.year, state.month, state.selectedDay);
    final List<TxRow> items = state.selectedItems;
    final int dayExpenseCents = items
        .where((TxRow t) => t.type == 'expense')
        .fold(0, (int a, TxRow t) => a + t.amountCents);

    return Column(
      // stretch（不是 start）：空态块自己只有「最宽子项」那么宽，
      // 用 start 会被顶到左边 —— 它内部的居中就成了「块内居中、整块偏左」。
      // 原型 `.empty-block` 是块级 div（占满宽 + text-align:center），这里靠拉伸对齐。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: <Widget>[
              // 原型 `.dayhead .bar`：品牌色小圆点（不是竖条）
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: kCalendarAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Tok.ink, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _dayHeader(day),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${items.length} 笔 · 支出 ¥${centsToYuan(dayExpenseCents)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          _EmptyDay(dayMs: state.selectedDayMs)
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Column(
                    children: <Widget>[
                      if (i > 0) const ToonDashedLine(),
                      TxTile(
                        tx: items[i],
                        categoryName: categoryNameOf(items[i].categoryId),
                        onTap: () => onEdit(items[i]),
                        onLongPress: () => onDelete(items[i]),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 「今天 9月11日 周五」/「昨天 …」/「2025年12月3日 周三」。
  String _dayHeader(DateTime d) {
    final DateTime now = DateTime.now();
    final String core = '${d.month}月${d.day}日 ${weekdayLabel(d)}';
    final bool isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (isToday) return '今天 $core';
    final DateTime yesterday = DateTime(now.year, now.month, now.day - 1);
    final bool isYesterday =
        d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day;
    if (isYesterday) return '昨天 $core';
    return d.year == now.year ? core : '${d.year}年$core';
  }
}

/// 当天没有账单时的空态 + 「记一笔」（默认日期 = 选中日）。
///
/// 原型 `.empty-block`：虚线圆底里放小猪 + 两行文案 + tonal 按钮。
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.dayMs});

  final int dayMs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 30),
      child: Column(
        children: <Widget>[
          const ToonDashedBorder(
            circle: true,
            color: Tok.ink,
            thickness: Tok.bw,
            dash: 7,
            gap: 5,
            background: Tok.brandTint,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Center(child: PigMascot(size: 52)),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '这天没有账单哦，赶紧记一笔吧~',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '长按日历里任意一天，也能直接记这一天的账',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Tok.ink2,
            ),
          ),
          const SizedBox(height: 16),
          ToonButton(
            label: '记一笔',
            icon: Icons.add,
            kind: ToonButtonKind.tonal,
            small: true,
            onPressed: () => context.push('/record?date=$dayMs'),
          ),
        ],
      ),
    );
  }
}
