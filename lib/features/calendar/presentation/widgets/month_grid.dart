/// 月历网格：表头「日一二三四五六」+ 日期格（日期下方标当天支出/收入）。
///
/// 视觉参考 app_template/calendar.jpg：有支出的格子给淡红底，今天用琥珀色，
/// 选中日用琥珀描边。金额为紧凑写法（-23.1 / +20.8）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/features/calendar/application/calendar_aggregate.dart';

/// 支出红 / 收入绿（与中国习惯一致的配色，与流水列表同源）。
const Color kExpenseRed = Tok.red;
const Color kIncomeGreen = Tok.green;

/// 品牌琥珀（选中 / 今天）。
const Color kCalendarAccent = Tok.brand;

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
    this.maxDate,
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

  /// 晚于该日期的格子灰显且不可点（原型 calGrid 的 `disableFuture`；
  /// 记一笔选日期用它挡住「记未来的账」）。为空 = 全部可选。
  final DateTime? maxDate;

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
                      fontWeight: FontWeight.w800,
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
    final DateTime? limit = maxDate;
    final bool disabled =
        limit != null &&
        DateTime(date.year, date.month, date.day).isAfter(
          DateTime(limit.year, limit.month, limit.day),
        );

    // 原型 `.day.tint-e / .tint-i`：支出优先于收入；`.day.sel` 写在后面
    // 覆盖 tint 底色 → 选中日一定是品牌浅底 + 墨色描边 + 硬阴影。
    final Color? cellBg = selected
        ? Tok.brandTint
        : agg == null
        ? null
        : agg.hasExpense
        ? Tok.redTint
        : agg.hasIncome
        ? Tok.greenTint
        : null;

    return InkWell(
      onTap: inMonth && !disabled ? () => onSelectDay(date.day) : null,
      borderRadius: BorderRadius.circular(Tok.rSm),
      child: Opacity(
        // 跨月格子与「超过上限」的格子（原型 `.day.out` / `disableFuture`）
        opacity: inMonth && !disabled ? 1 : 0.3,
        child: Container(
          height: 62,
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(2, 5, 2, 4),
          decoration: BoxDecoration(
            color: cellBg,
            borderRadius: BorderRadius.circular(Tok.rSm),
            border: Border.all(
              color: selected ? Tok.ink : Colors.transparent,
              width: 2,
            ),
            // 选中态给硬阴影（原型 `.day.sel` 的 `--sh-sm`）
            boxShadow: selected ? Tok.hard(d: 2.5) : null,
          ),
          child: Column(
            children: <Widget>[
              // 固定 24 高：今天要从文字变成圆底，不固定会让整行跳一下
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: isToday
                      ? Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: kCalendarAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Tok.ink, width: 2),
                          ),
                          child: _dayNumber(date, isToday: true),
                        )
                      : _dayNumber(date, isToday: false),
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
      ),
    );
  }

  /// 日期数字：今天用品牌深色 + 900 字重（原型 `.day.today .dnum`）。
  Widget _dayNumber(DateTime date, {required bool isToday}) => Text(
    '${date.day}',
    style: TextStyle(
      fontSize: 13,
      height: 1.1,
      fontWeight: isToday ? FontWeight.w900 : FontWeight.w800,
      color: isToday ? Tok.brandInk : Tok.ink,
    ),
  );

  Widget _amountText(String text, Color color) => FittedBox(
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        fontSize: 9,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );
}
