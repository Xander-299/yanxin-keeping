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
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_delete_dialog.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_group_list.dart';

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
              error: (Object e, StackTrace _) =>
                  Center(child: Text('加载失败：$e')),
              data: (CalendarState state) => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: MonthGrid(
                        year: state.year,
                        month: state.month,
                        byDay: state.byDay,
                        selectedDay: state.selectedDay,
                        onSelectDay: (int day) =>
                            ref.read(calendarProvider.notifier).selectDay(day),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SummaryBar(state: state),
                    const SizedBox(height: 8),
                    _SelectedDaySection(
                      state: state,
                      categoryNameOf: nameOf,
                      onEdit: (TxRow tx) => context.push('/record', extra: tx.id),
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
    final map = <String, String>{for (final Category c in categories) c.id: c.name};
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
  }
}

/// 顶部栏：左侧侧面栏（抽屉）+ 中间年月（点开月份选择子页）+ 右侧两个占位。
class _HeaderBody extends ConsumerWidget {
  const _HeaderBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int year = ref.watch(
      calendarProvider.select((AsyncValue<CalendarState> v) => v.value?.year),
    ) ?? DateTime.now().year;
    final int month = ref.watch(
      calendarProvider.select((AsyncValue<CalendarState> v) => v.value?.month),
    ) ?? DateTime.now().month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '账本',
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
          Expanded(
            child: Center(
              child: InkWell(
                onTap: () => context.push('/month-picker'),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$year年$month月',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const _HeaderIcon(icon: Icons.receipt_long_rounded, tooltip: '报表（建设中）'),
          const _HeaderIcon(icon: Icons.pie_chart_outline_rounded, tooltip: '统计（建设中）'),
        ],
      ),
    );
  }
}

/// header 占位图标：点击提示建设中（与首页一致）。
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: () {
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
        : Colors.white;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(14),
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 15,
                decoration: BoxDecoration(
                  color: kCalendarAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _dayHeader(day),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                for (final TxRow tx in items)
                  TxTile(
                    tx: tx,
                    categoryName: categoryNameOf(tx.categoryId),
                    onTap: () => onEdit(tx),
                    onLongPress: () => onDelete(tx),
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
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.dayMs});

  final int dayMs;

  @override
  Widget build(BuildContext context) {
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: <Widget>[
          const Icon(Icons.event_note_rounded, size: 48, color: Colors.white12),
          const SizedBox(height: 10),
          Text(
            '这天没有账单哦，赶紧记一笔吧~',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/record?date=$dayMs'),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('记一笔'),
          ),
        ],
      ),
    );
  }
}
