/// 「选择日期」底部弹层（F7.6 P3，对齐原型 `ovlDate`）。
///
/// 替代 Material `showDatePicker`：视觉与其他弹层统一（抓手 + 墨色描边 + 硬阴影），
/// 并且**上限为今天** —— 未来月份首页翻不过去，记未来的账会「记了看不见」。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/features/calendar/application/calendar_aggregate.dart';
import 'package:yanxin/features/calendar/presentation/widgets/month_grid.dart';

/// 弹出日期选择弹层，返回选中的日期（取消返回 null）。
Future<DateTime?> showDatePickerSheet(
  BuildContext context, {
  required DateTime initial,
}) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  // 编辑历史流水时 initial 可能比今天早，上限仍是「今天」，但绝不能小于 initial 本身
  final DateTime maxDate = initial.isAfter(today) ? initial : today;
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext _) =>
        _DateSheet(initial: initial, maxDate: maxDate),
  );
}

class _DateSheet extends StatelessWidget {
  const _DateSheet({required this.initial, required this.maxDate});

  final DateTime initial;
  final DateTime maxDate;

  @override
  Widget build(BuildContext context) {
    // 只有当月才存在「灰显不可选」的格子（翻到历史月时整月都可选）
    final bool sameMonth =
        maxDate.year == initial.year && maxDate.month == initial.month;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 抓手
            Center(
              child: Container(
                width: 46,
                height: 6,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Tok.ink,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const Text(
              '选择日期',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              '上限为今天，不能记未来的账',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
            const SizedBox(height: 12),
            MonthGrid(
              year: initial.year,
              month: initial.month,
              // 记一笔只需要日期，不显示当天收支（原型这里也是同一个 calGrid，
              // 但金额标注对「选日期」是干扰）
              byDay: const <int, DayAgg>{},
              selectedDay: initial.day,
              maxDate: maxDate,
              onSelectDay: (int day) => Navigator.of(context).pop(
                DateTime(initial.year, initial.month, day),
              ),
            ),
            const SizedBox(height: 4),
            if (sameMonth)
              Center(
                child: Text(
                  '${maxDate.day} 日之后灰显不可选',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
