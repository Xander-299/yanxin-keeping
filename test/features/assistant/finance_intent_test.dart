/// 「一句话 → 查询意图」的纯函数测试（M1 的理解层）。
///
/// 每个用例都对应一句**真实会有人这么问**的话；改规则前先看这些断言为什么这么写
/// （顺序即优先级，见 `finance_intent.dart` 头注释）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/assistant/application/finance_intent.dart';

const List<String> _expense = <String>['餐饮', '购物', '交通', '居住', '娱乐', '其他'];
const List<String> _income = <String>['工资', '奖金', '其他'];

/// 固定"现在" = 2026-10-25 15:00，保证「本月 / 上月 / 今年」可复现。
final int _nowMs = DateTime(2026, 10, 25, 15).millisecondsSinceEpoch;

FinanceIntent _parse(String q) => parseFinanceIntent(
  q,
  expenseCategories: _expense,
  incomeCategories: _income,
  nowMs: _nowMs,
);

void main() {
  group('时间区间', () {
    test('这个月 = 当月自然月', () {
      final FinanceIntent i = _parse('这个月花了多少');
      expect(i, isA<MonthSummaryIntent>());
      final Period p = (i as MonthSummaryIntent).period;
      expect(p.label, '2026年10月');
      expect(p.year, 2026);
      expect(p.month, 10);
      expect(p.startMs, DateTime(2026, 10, 1).millisecondsSinceEpoch);
      expect(p.endMs, DateTime(2026, 11, 1).millisecondsSinceEpoch);
    });

    test('上个月跨年（1 月问上月 = 去年 12 月）', () {
      final FinanceIntent i = parseFinanceIntent(
        '上月花了多少',
        expenseCategories: _expense,
        incomeCategories: _income,
        nowMs: DateTime(2026, 1, 5).millisecondsSinceEpoch,
      );
      final Period p = (i as MonthSummaryIntent).period;
      expect(p.year, 2025);
      expect(p.month, 12);
    });

    test('显式年月', () {
      final Period p = (_parse('2026年7月花了多少') as MonthSummaryIntent).period;
      expect(p.label, '2026年7月');
    });

    test('只写月份：不晚于当前月 → 今年；晚于 → 去年', () {
      expect((_parse('10月花了多少') as MonthSummaryIntent).period.year, 2026);
      expect((_parse('12月花了多少') as MonthSummaryIntent).period.year, 2025);
    });

    test('今年 → 整年区间', () {
      final Period p = (_parse('今年收入多少') as MonthSummaryIntent).period;
      expect(p.label, '2026年');
      expect(p.startMs, DateTime(2026).millisecondsSinceEpoch);
      expect(p.endMs, DateTime(2027).millisecondsSinceEpoch);
    });

    test('最近 30 天是滚动区间，标签里写清起止', () {
      final Period p = (_parse('最近30天花了多少') as MonthSummaryIntent).period;
      expect(p.label, contains('近 30 天'));
      expect(p.label, contains('9月26日'));
      expect(p.label, contains('10月25日'));
      expect(p.startMs, DateTime(2026, 9, 26).millisecondsSinceEpoch);
    });

    test('中文数字也认：「最近三个月」', () {
      final FinanceIntent i = _parse('最近三个月哪个分类增长最多');
      final Period p = (i as CompareIntent).current;
      expect(p.label, contains('近 3 个月'));
      expect(p.startMs, DateTime(2026, 8, 1).millisecondsSinceEpoch);
    });
  });

  group('口径选择（顺序即优先级）', () {
    test('「为什么比上个月多」→ 对比，而不是本月汇总', () {
      final FinanceIntent i = _parse('这个月为什么比上个月多');
      expect(i, isA<CompareIntent>());
      final CompareIntent c = i as CompareIntent;
      expect(c.current.label, '2026年10月');
      expect(c.previous.label, '2026年9月');
      expect(c.categoryFocus, isFalse);
    });

    test('「哪个分类增长最多」→ 对比 + categoryFocus', () {
      final CompareIntent c = _parse('最近三个月哪个分类增长最多') as CompareIntent;
      expect(c.categoryFocus, isTrue);
    });

    test('「这个月餐饮花了多少」→ 分类，不能被汇总吞掉', () {
      final FinanceIntent i = _parse('这个月餐饮花了多少');
      expect(i, isA<CategorySpendingIntent>());
      final CategorySpendingIntent c = i as CategorySpendingIntent;
      expect(c.categoryName, '餐饮');
      expect(c.kind, 'expense');
      expect(c.period.label, '2026年10月');
    });

    test('别名：「吃饭」→ 餐饮', () {
      final CategorySpendingIntent c = _parse('这个月吃饭花了多少') as CategorySpendingIntent;
      expect(c.categoryName, '餐饮');
    });

    test('收入类分类带方向：「工资」', () {
      final CategorySpendingIntent c = _parse('这个月工资收入多少') as CategorySpendingIntent;
      expect(c.categoryName, '工资');
      expect(c.kind, 'income');
    });

    test('「预算」优先于汇总', () {
      final FinanceIntent i = _parse('本月预算还剩多少');
      expect(i, isA<BudgetIntent>());
      expect((i as BudgetIntent).period.label, '2026年10月');
    });

    test('「大额支出」默认看近 90 天', () {
      final FinanceIntent i = _parse('最近有哪些大额支出');
      expect(i, isA<TopExpensesIntent>());
      final TopExpensesIntent t = i as TopExpensesIntent;
      expect(_days(t.period), 90);
    });

    test('结余 → both（同时要收入和支出）', () {
      final MonthSummaryIntent m = _parse('这个月结余多少') as MonthSummaryIntent;
      expect(m.kind, 'both');
    });

    test('问收入 → income', () {
      expect((_parse('这个月收入多少') as MonthSummaryIntent).kind, 'income');
    });

    test('什么都问 → 默认支出', () {
      expect((_parse('这个月花了多少') as MonthSummaryIntent).kind, 'expense');
    });
  });

  group('储蓄目标（纯算术，不查库）', () {
    test('「每个月存2000元，多久能攒够2万」', () {
      final FinanceIntent i = _parse('我每个月存2000元，多久能攒够2万');
      expect(i, isA<SavingsGoalIntent>());
      final SavingsGoalIntent s = i as SavingsGoalIntent;
      expect(s.monthlyCents, 200000); // ¥2000
      expect(s.targetCents, 2000000); // ¥20000
      expect(windowOf(i), isNull, reason: '储蓄是纯算术，不该去查流水');
    });

    test('只有「存」没说多久 → 不算储蓄问题', () {
      expect(_parse('这个月存了多少钱'), isNot(isA<SavingsGoalIntent>()));
    });
  });

  group('不该瞎答', () {
    test('完全无关 → UnknownIntent', () {
      expect(_parse('今天天气怎么样'), isA<UnknownIntent>());
    });

    test('Unknown 的 window 为 null（不查库）', () {
      expect(windowOf(_parse('帮我写首诗')), isNull);
    });
  });

  group('对比区间覆盖两个月', () {
    test('windowOf(compare) 从上一期开始、到本期结束', () {
      final CompareIntent c = _parse('这个月为什么比上个月多') as CompareIntent;
      final Period w = windowOf(c)!;
      expect(w.startMs, DateTime(2026, 9, 1).millisecondsSinceEpoch);
      expect(w.endMs, DateTime(2026, 11, 1).millisecondsSinceEpoch);
    });
  });
}

/// 从区间的起止天数反推「近 N 天」（测试里用来读 90 天那个默认值）。
int _days(Period p) {
  final DateTime s = DateTime.fromMillisecondsSinceEpoch(p.startMs);
  final DateTime e = DateTime.fromMillisecondsSinceEpoch(p.endMs);
  return e.difference(s).inDays;
}
