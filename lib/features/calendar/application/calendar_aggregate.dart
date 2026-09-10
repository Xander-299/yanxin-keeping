/// 日历聚合（纯函数，便于单测）。
///
/// 日历格子要「日期下方标支出/收入」，需要把一个月流水按「当月第几天」聚合；
/// 汇总条要「月结余 / 日均支出」，日均按天折算（当月按已过天数，历史月按整月天数）。
library;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/core/utils/money.dart';

/// 某一天的收支合计（分）。transfer 不计收支。
class DayAgg {
  const DayAgg({required this.incomeCents, required this.expenseCents});

  /// 当天收入（分，恒 >= 0）。
  final int incomeCents;

  /// 当天支出（分，恒 >= 0）。
  final int expenseCents;

  bool get hasIncome => incomeCents > 0;

  bool get hasExpense => expenseCents > 0;

  bool get isEmpty => incomeCents == 0 && expenseCents == 0;
}

/// 把一批流水按「当月第几天」（1-31）聚合。
///
/// 入参应为**同一月份**的流水（`listByMonth` 的返回值）；只统计 income/expense。
Map<int, DayAgg> aggregateByDay(List<TxRow> items) {
  final income = <int, int>{};
  final expense = <int, int>{};
  for (final t in items) {
    if (t.type != 'income' && t.type != 'expense') continue;
    final day = DateTime.fromMillisecondsSinceEpoch(t.occurredAt).day;
    if (t.type == 'income') {
      income[day] = (income[day] ?? 0) + t.amountCents;
    } else {
      expense[day] = (expense[day] ?? 0) + t.amountCents;
    }
  }
  final days = <int>{...income.keys, ...expense.keys}.toList()..sort();
  return <int, DayAgg>{
    for (final d in days)
      d: DayAgg(incomeCents: income[d] ?? 0, expenseCents: expense[d] ?? 0),
  };
}

/// 某天是否有流水（供月份缩略图标出「有账的日期」）。
bool hasAnyTx(List<TxRow> items, int day) =>
    items.any((TxRow t) => DateTime.fromMillisecondsSinceEpoch(t.occurredAt).day == day);

/// 日均支出（分）= 月支出 / 天数。
///
/// 当天所在月按「已过天数」折算（今天也会计入），其他月按整月天数；
/// 全程整数运算，最后四舍五入到分，不引入浮点误差。
int dailyAverageExpenseCents({
  required int expenseCents,
  required int year,
  required int month,
  required int nowMs,
}) {
  if (expenseCents <= 0) return 0;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final int days = (year == now.year && month == now.month)
      ? now.day
      : daysInMonth(year, month);
  if (days <= 0) return 0;
  return (expenseCents + days ~/ 2) ~/ days;
}

/// 日历格子里的紧凑金额：去掉小数末尾多余的 0（23.10 → 23.1、20.80 → 20.8）。
///
/// 只用于格子内的小字标注；正式金额展示仍走 [centsToYuan] 保留两位。
String compactYuan(int cents) {
  var s = centsToYuan(cents);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}
