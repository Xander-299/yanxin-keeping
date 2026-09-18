/// 月份选择子页：按年展示 12 个月的缩略日历，点某天即跳到该月该日。
///
/// 视觉参考 app_template/calendar_select.jpg（布局对齐）。
/// 有账的日期用琥珀色标出；点任意日期 → 日历页切到该月并选中该日，随后返回。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/utils/date.dart';

import '../application/calendar_controller.dart';
import 'widgets/month_grid.dart';

/// 月份选择子页。
class MonthPickerPage extends ConsumerStatefulWidget {
  const MonthPickerPage({super.key});

  @override
  ConsumerState<MonthPickerPage> createState() => _MonthPickerPageState();
}

class _MonthPickerPageState extends ConsumerState<MonthPickerPage> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year =
        ref.read(calendarProvider).value?.year ?? DateTime.now().year;
  }

  Future<void> _pick(int month, int day) async {
    await ref.read(calendarProvider.notifier).jumpTo(_year, month, day: day);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final CalendarState? current = ref.watch(calendarProvider).value;
    final AsyncValue<Map<int, Set<int>>> index = ref.watch(
      yearDayIndexProvider(_year),
    );
    final Map<int, Set<int>> days = index.value ?? const <int, Set<int>>{};

    return Scaffold(
      appBar: AppBar(
        title: Text('$_year年'),
        actions: const <Widget>[
          _PickerIcon(icon: Icons.receipt_long_rounded, tooltip: '报表（建设中）'),
          _PickerIcon(icon: Icons.pie_chart_outline_rounded, tooltip: '统计（建设中）'),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                children: <Widget>[
                  for (int row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (int col = 0; col < 3; col++)
                            Expanded(
                              child: _MiniMonth(
                                year: _year,
                                month: row * 3 + col + 1,
                                daysWithTx:
                                    days[row * 3 + col + 1] ?? const <int>{},
                                selectedMonth: current?.month,
                                selectedDay: current?.selectedDay,
                                onPick: _pick,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _PillButton(
                    label: '‹ 上一年',
                    onTap: () => setState(() => _year--),
                  ),
                  const SizedBox(width: 24),
                  _PillButton(
                    label: '下一年 ›',
                    onTap: () => setState(() => _year++),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个月份缩略日历（3 列 × 4 行里的一格）。
class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.year,
    required this.month,
    required this.daysWithTx,
    required this.selectedMonth,
    required this.selectedDay,
    required this.onPick,
  });

  final int year;
  final int month;
  final Set<int> daysWithTx;
  final int? selectedMonth;
  final int? selectedDay;
  final void Function(int month, int day) onPick;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final int leading = DateTime(year, month, 1).weekday % 7;
    final int total = daysInMonth(year, month);
    final int rows = ((leading + total) / 7).ceil();
    final bool isSelectedMonth = selectedMonth == month;

    return Padding(
      key: ValueKey<String>('mini-month-$month'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$month月',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelectedMonth ? Tok.brandDeep : Tok.ink,
            ),
          ),
          const SizedBox(height: 4),
          for (int r = 0; r < rows; r++)
            SizedBox(
              height: 15,
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < 7; c++)
                    Expanded(
                      child: _miniCell(
                        context,
                        day: 1 - leading + r * 7 + c,
                        total: total,
                        now: now,
                        isSelectedMonth: isSelectedMonth,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniCell(
    BuildContext context, {
    required int day,
    required int total,
    required DateTime now,
    required bool isSelectedMonth,
  }) {
    if (day < 1 || day > total) return const SizedBox.shrink();
    final bool hasTx = daysWithTx.contains(day);
    final bool isToday =
        now.year == year && now.month == month && now.day == day;
    final bool isSelected = isSelectedMonth && selectedDay == day;

    return InkWell(
      onTap: () => onPick(month, day),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: isSelected ? kCalendarAccent : null,
          border: isToday && !isSelected
              ? Border.all(color: kCalendarAccent, width: 1)
              : null,
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 9,
            height: 1,
            color: isSelected
                ? Tok.brandInk
                : hasTx
                ? Tok.brandDeep
                : Tok.ink3,
            fontWeight: isSelected || hasTx ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 子页 appbar 占位图标。
class _PickerIcon extends StatelessWidget {
  const _PickerIcon({required this.icon, required this.tooltip});

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

/// 底部胶囊按钮（上一年 / 下一年）。
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tok.paper,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}
