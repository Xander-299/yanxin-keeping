/// 预算计算纯函数单测：进度 / 剩余额度 / 日均 / 剩余每日可消费 / 超支。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/ledger/application/budget_metrics.dart';

void main() {
  // 固定「现在」= 2026-09-12（9 月共 30 天，剩余 19 天含今天）
  final int nowMs = DateTime(2026, 9, 12, 10).millisecondsSinceEpoch;

  test('未设预算：进度与剩余额度为 0，但日均照算', () {
    final v = buildBudgetView(
      budgetCents: null,
      spentCents: 10152,
      year: 2026,
      month: 9,
      nowMs: nowMs,
    );
    expect(v.hasBudget, isFalse);
    expect(v.progress, 0);
    expect(v.percentPermille, 0);
    expect(v.remainingCents, 0);
    expect(v.overspent, isFalse);
    // 没预算也该知道自己每天花多少：101.52 / 12 天 = 8.46
    expect(v.dailyAvgCents, 846);
    expect(v.dailyRemainingCents, isNull);
  });

  test('预算 ≤ 0 视为未设置', () {
    for (final int? budget in <int?>[0, -100]) {
      final v = buildBudgetView(
        budgetCents: budget,
        spentCents: 100,
        year: 2026,
        month: 9,
        nowMs: nowMs,
      );
      expect(v.hasBudget, isFalse, reason: '预算 $budget 应视为未设置');
    }
  });

  test('正常：1000 预算花掉 101.52 → 10.2% / 剩余 898.48', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: 10152,
      year: 2026,
      month: 9,
      nowMs: nowMs,
    );
    expect(v.hasBudget, isTrue);
    expect(v.percentPermille, 102);
    expect(v.percentText, '10.2%');
    expect(v.remainingCents, 89848);
    expect(v.overspent, isFalse);
    expect(v.progress, closeTo(0.10152, 0.00001));
    // 剩余 898.48 摊到剩余 19 天（30 - 12 + 1）= 47.29
    expect(v.daysLeft, 19);
    expect(v.dailyRemainingCents, 4729);
  });

  test('超支：1000 预算花掉 1200 → 120.0% / 剩余 -200 / 进度封顶 1', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: 120000,
      year: 2026,
      month: 9,
      nowMs: nowMs,
    );
    expect(v.overspent, isTrue);
    expect(v.percentPermille, 1200);
    expect(v.percentText, '120.0%');
    expect(v.remainingCents, -20000);
    expect(v.overspentCents, 20000);
    // 环形不能画出 >100% 的圈
    expect(v.progress, 1.0);
    // 超支后「剩余每日可消费」归 0，不能是负数
    expect(v.dailyRemainingCents, 0);
  });

  test('刚好花完：100.0% / 剩余 0 / 不算超支', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: 100000,
      year: 2026,
      month: 9,
      nowMs: nowMs,
    );
    expect(v.percentText, '100.0%');
    expect(v.remainingCents, 0);
    expect(v.overspent, isFalse);
    expect(v.overspentCents, 0);
    expect(v.dailyRemainingCents, 0);
  });

  test('历史月：日均按整月天数，且不给「剩余每日可消费」', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: 10152,
      year: 2026,
      month: 8, // 31 天
      nowMs: nowMs,
    );
    // 101.52 / 31 = 3.27
    expect(v.dailyAvgCents, 327);
    // 月已结束，「剩余天数」无意义 → null（界面显示「—」而不是 0）
    expect(v.daysLeft, isNull);
    expect(v.dailyRemainingCents, isNull);
    expect(v.percentText, '10.2%');
  });

  test('未来月：按整月天数摊剩余额度', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: 0,
      year: 2026,
      month: 10, // 31 天
      nowMs: nowMs,
    );
    expect(v.daysLeft, 31);
    expect(v.dailyRemainingCents, 3226); // (100000 + 15) ~/ 31
    expect(v.dailyAvgCents, 0);
  });

  test('跨年月份判断正确（12 月 / 次年 1 月）', () {
    final decMs = DateTime(2026, 12, 20).millisecondsSinceEpoch;
    final dec = buildBudgetView(
      budgetCents: 310000,
      spentCents: 0,
      year: 2026,
      month: 12,
      nowMs: decMs,
    );
    expect(dec.daysLeft, 12); // 31 - 20 + 1
    expect(dec.dailyRemainingCents, 25833); // (310000 + 6) ~/ 12

    final jan = buildBudgetView(
      budgetCents: 310000,
      spentCents: 0,
      year: 2027,
      month: 1,
      nowMs: decMs,
    );
    expect(jan.daysLeft, 31); // 未来月 = 整月
    expect(jan.dailyRemainingCents, 10000);
  });

  test('当月最后一天：剩余天数含今天，只算 1 天', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: 0,
      year: 2026,
      month: 9,
      nowMs: DateTime(2026, 9, 30, 12).millisecondsSinceEpoch,
    );
    expect(v.daysLeft, 1);
    expect(v.dailyRemainingCents, 100000);
  });

  test('负的已消费被钳为 0（防御性：不该出现）', () {
    final v = buildBudgetView(
      budgetCents: 100000,
      spentCents: -1,
      year: 2026,
      month: 9,
      nowMs: nowMs,
    );
    expect(v.spentCents, 0);
    expect(v.remainingCents, 100000);
  });
}
