/// 月历网格：表头「日一二三四五六」+ 日期格（日期下方标当天支出/收入）。
///
/// 视觉参考 app_template/calendar.jpg：有支出的格子给淡红底，今天用琥珀色，
/// 选中日用琥珀描边。金额为紧凑写法（-23.1 / +20.8）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/features/calendar/application/calendar_aggregate.dart';

/// 支出红 / 收入绿（与中国习惯一致的配色，与流水列表同源）。
const Color kExpenseRed = Color(0xFFEF5350);
const Color kIncomeGreen = Color(0xFF66BB6A);

/// 品牌琥珀（选中 / 今天）。
const Color kCalendarAccent = Color(0xFFFFAF38);

/// 月历网格。
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.byDay,
    required this.selectedDay,
    required this.onSelectDay,
    this.now,
  });

  final int year;

  /// 1-12。
  final int month;

  /// 按「当月第几天」聚合的收支（跨月格子不显示金额）。
  final Map<int, DayAgg> byDay;

  final int selectedDay;

  final ValueChanged<int> onSelectDay;

  /// 覆盖「今天」（测试注入用；为空取真实当前时间）。
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final DateTime today = now ?? DateTime.now();
    final int leading = DateTime(year, month, 1).weekday % 7; // 周日起始
    final int total = daysInMonth(year, month);
    final int rows = ((leading + total) / 7).ceil();

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String w in weekdayHeaders)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (int r = 0; r < rows; r++)
          Row(
            children: <Widget>[
              for (int c = 0; c < 7; c++)
                Expanded(
                  child: _buildCell(
                    context,
                    // DateTime 的日号溢出/为 0 时会自动落到相邻月，正好用于补格
                    date: DateTime(year, month, 1 - leading + r * 7 + c),
                    today: today,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context, {
    required DateTime date,
    required DateTime today,
  }) {
    final bool inMonth = date.month == month && date.year == year;
    final bool isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final DayAgg? agg = inMonth ? byDay[date.day] : null;
    final bool selected = inMonth && date.day == selectedDay;

    return InkWell(
      onTap: inMonth ? () => onSelectDay(date.day) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 62,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: agg != null && agg.hasExpense
              ? kExpenseRed.withValues(alpha: 0.14)
              : Colors.transparent,
          border: selected ? Border.all(color: kCalendarAccent, width: 1.5) : null,
        ),
        child: Column(
          children: <Widget>[
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 13,
                height: 1.1,
                fontWeight: selected || isToday
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: !inMonth
                    ? Colors.white24
                    : isToday
                    ? kCalendarAccent
                    : Colors.white,
              ),
            ),
            const Spacer(),
            if (inMonth && agg != null) ...<Widget>[
              if (agg.hasExpense)
                _amountText('-${compactYuan(agg.expenseCents)}', kExpenseRed),
              if (agg.hasIncome)
                _amountText('+${compactYuan(agg.incomeCents)}', kIncomeGreen),
            ],
          ],
        ),
      ),
    );
  }

  Widget _amountText(String text, Color color) => FittedBox(
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(fontSize: 9, height: 1.2, color: color),
    ),
  );
}
