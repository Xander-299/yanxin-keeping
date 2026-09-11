/// 预算计算（纯函数，便于单测）。
///
/// 首页预算卡要的数字全在这里算：进度百分比、剩余额度、本月日均消费、
/// 剩余每日可消费。口径与日历页保持一致（日均按「当月已过天数 / 历史月整月」），
/// 直接复用 `calendar_aggregate.dart` 里已单测过的 [dailyAverageExpenseCents]。
library;

import 'package:yanxin/core/utils/date.dart';

import '../../calendar/application/calendar_aggregate.dart';

/// 预算卡要渲染的全部数值（一次性算完，UI 只负责排版）。
class BudgetView {
  const BudgetView({
    required this.hasBudget,
    required this.budgetCents,
    required this.spentCents,
    required this.remainingCents,
    required this.overspent,
    required this.progress,
    required this.percentPermille,
    required this.dailyAvgCents,
    required this.dailyRemainingCents,
    required this.daysLeft,
  });

  /// 是否设过预算（未设置 / 预算 ≤ 0 → false）。
  final bool hasBudget;

  /// 预算金额（分）。未设置时为 0。
  final int budgetCents;

  /// 已消费（分，该月 expense 合计）。
  final int spentCents;

  /// 剩余额度（分，可为负；未设置时为 0）。
  final int remainingCents;

  /// 是否已超支。
  final bool overspent;

  /// 环形进度 0.0–1.0（只用于绘制，真实占比见 [percentPermille]）。
  final double progress;

  /// 真实占比的千分比（可 > 1000，即超支）。
  final int percentPermille;

  /// 本月日均消费（分）。
  final int dailyAvgCents;

  /// 剩余每日可消费（分）；不适用时为 null（未设预算 / 已结束的月份）。
  final int? dailyRemainingCents;

  /// 剩余天数（含今天）；不适用时为 null。
  final int? daysLeft;

  /// 展示用占比：`10.2%` / `128.5%`。
  String get percentText => '${(percentPermille / 10).toStringAsFixed(1)}%';

  /// 超支金额（分，恒 >= 0）。
  int get overspentCents => overspent ? spentCents - budgetCents : 0;
}

/// 组装预算卡视图。
///
/// [budgetCents] 为 null 或 ≤ 0 视为「未设置预算」；此时进度与剩余额度均为 0，
/// 但「本月日均消费」照常计算（没预算也该能看到自己每天花多少）。
BudgetView buildBudgetView({
  required int? budgetCents,
  required int spentCents,
  required int year,
  required int month,
  required int nowMs,
}) {
  final hasBudget = budgetCents != null && budgetCents > 0;
  final budget = hasBudget ? budgetCents : 0;
  final spent = spentCents > 0 ? spentCents : 0;

  final remaining = hasBudget ? budget - spent : 0;
  final overspent = hasBudget && spent > budget;

  var permille = 0;
  var progress = 0.0;
  if (hasBudget) {
    // 四舍五入到千分之一（即展示的一位小数百分比），全程整数运算。
    permille = (spent * 1000 + budget ~/ 2) ~/ budget;
    progress = spent / budget;
    if (progress > 1) progress = 1;
    if (progress < 0) progress = 0;
  }

  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final isCurrentMonth = year == now.year && month == now.month;
  final isFutureMonth = year * 12 + month > now.year * 12 + now.month;

  int? daysLeft;
  int? dailyRemaining;
  if (hasBudget) {
    if (isCurrentMonth) {
      daysLeft = daysInMonth(year, month) - now.day + 1;
    } else if (isFutureMonth) {
      // 未来月：整月都还没开始，按整月天数摊。
      daysLeft = daysInMonth(year, month);
    }
    // 历史月：月已结束，「剩余每日可消费」没有意义 → 保持 null（界面显示「—」）。
    if (daysLeft != null && daysLeft > 0) {
      dailyRemaining =
          remaining <= 0 ? 0 : (remaining + daysLeft ~/ 2) ~/ daysLeft;
    }
  }

  return BudgetView(
    hasBudget: hasBudget,
    budgetCents: budget,
    spentCents: spent,
    remainingCents: remaining,
    overspent: overspent,
    progress: progress,
    percentPermille: permille,
    dailyAvgCents: dailyAverageExpenseCents(
      expenseCents: spent,
      year: year,
      month: month,
      nowMs: nowMs,
    ),
    dailyRemainingCents: dailyRemaining,
    daysLeft: daysLeft,
  );
}
