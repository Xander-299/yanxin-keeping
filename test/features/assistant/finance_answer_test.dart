/// 「意图 + 数据 → 中文回答」的纯函数测试（M1 的嘴）。
///
/// 这里断言的是**具体金额与文案要点**：模型会编数，模板不会 —— 所以每一分钱都要对上。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/features/assistant/application/finance_answer.dart';
import 'package:yanxin/features/assistant/application/finance_intent.dart';

final int _nowMs = DateTime(2026, 10, 25, 15).millisecondsSinceEpoch;

const Map<String, String> _names = <String, String>{
  'c-food': '餐饮',
  'c-shop': '购物',
  'c-trans': '交通',
  'c-salary': '工资',
};

TxRow _tx({
  required String id,
  required String type,
  required int cents,
  required DateTime at,
  String? categoryId,
  String note = '',
}) => TxRow(
  id: id,
  bookId: 'b1',
  accountId: 'a1',
  categoryId: categoryId,
  type: type,
  amountCents: cents,
  note: note,
  occurredAt: at.millisecondsSinceEpoch,
  source: 'manual',
  createdAt: at.millisecondsSinceEpoch,
  updatedAt: at.millisecondsSinceEpoch,
  dirty: 1,
);

/// 10 月：餐饮 1280.50 + 购物 980 + 交通 460 = 2720.50；收入 12000
/// 9 月：餐饮 890 + 购物 400 = 1290
final List<TxRow> _rows = <TxRow>[
  _tx(id: 'o1', type: 'expense', cents: 128050, at: DateTime(2026, 10, 3), categoryId: 'c-food', note: '午饭'),
  _tx(id: 'o2', type: 'expense', cents: 98000, at: DateTime(2026, 10, 8), categoryId: 'c-shop', note: '外套'),
  _tx(id: 'o3', type: 'expense', cents: 46000, at: DateTime(2026, 10, 12), categoryId: 'c-trans', note: '打车'),
  _tx(id: 'o4', type: 'income', cents: 1200000, at: DateTime(2026, 10, 1), categoryId: 'c-salary', note: '工资'),
  _tx(id: 's1', type: 'expense', cents: 89000, at: DateTime(2026, 9, 10), categoryId: 'c-food'),
  _tx(id: 's2', type: 'expense', cents: 40000, at: DateTime(2026, 9, 20), categoryId: 'c-shop'),
];

FinanceData _data({int? budget, List<TxRow>? rows}) => FinanceData(
  rows: rows ?? _rows,
  categoryNames: _names,
  budgetCents: budget,
  nowMs: _nowMs,
);

final Period _oct = Period.month(2026, 10);
final Period _sep = Period.month(2026, 9);

void main() {
  group('月度汇总', () {
    test('支出：金额、分类、占比都对', () {
      final FinanceAnswer a = buildFinanceAnswer(
        MonthSummaryIntent(period: _oct, kind: 'expense'),
        _data(),
      );
      expect(a.headline, '¥2,720.50');
      expect(a.title, contains('2026年10月'));
      expect(a.narrative, contains('¥2,720.50'));
      expect(a.narrative, contains('餐饮'));
      expect(a.narrative, contains('47.1%')); // 128050 / 272050
      expect(a.facts.any((AnswerFact f) => f.label == '支出'), isTrue);
      expect(a.facts.any((AnswerFact f) => f.label == '结余'), isTrue);
    });

    test('收入口径：大字是收入，且同时给出支出与结余', () {
      final FinanceAnswer a = buildFinanceAnswer(
        MonthSummaryIntent(period: _oct, kind: 'income'),
        _data(),
      );
      expect(a.headline, '¥12,000.00');
      expect(a.facts.any((AnswerFact f) => f.label == '支出'), isTrue);
      expect(a.narrative, contains('结余'));
    });

    test('空账本：明说没有记录，不返回 0 元结论', () {
      final FinanceAnswer a = buildFinanceAnswer(
        MonthSummaryIntent(period: _oct, kind: 'expense'),
        _data(rows: const <TxRow>[]),
      );
      expect(a.narrative, contains('还没有记账记录'));
      expect(a.headline, isNull);
    });
  });

  group('分类支出', () {
    test('命中：金额 + 笔数 + 占比', () {
      final FinanceAnswer a = buildFinanceAnswer(
        CategorySpendingIntent(period: _oct, categoryName: '餐饮', kind: 'expense'),
        _data(),
      );
      expect(a.headline, '¥1,280.50');
      expect(a.narrative, contains('1 笔'));
      expect(a.narrative, contains('47.1%'));
    });

    test('没这个分类的支出：明说没有，不伪造 0 元', () {
      final FinanceAnswer a = buildFinanceAnswer(
        CategorySpendingIntent(period: _oct, categoryName: '娱乐', kind: 'expense'),
        _data(),
      );
      expect(a.narrative, contains('没有「娱乐」'));
      expect(a.headline, isNull);
    });
  });

  group('预算', () {
    test('没超支：剩余、日均、每日可花', () {
      final FinanceAnswer a = buildFinanceAnswer(
        BudgetIntent(period: _oct),
        _data(budget: 300000),
      );
      expect(a.headline, '¥279.50');
      expect(a.narrative, contains('还剩 ¥279.50'));
      expect(a.narrative, contains('90.7%'));
      expect(a.narrative, contains('每天还能花'));
      expect(a.tone, AnswerTone.good);
    });

    test('超支：给超支额与「不要再花」的结论', () {
      final FinanceAnswer a = buildFinanceAnswer(
        BudgetIntent(period: _oct),
        _data(budget: 200000),
      );
      expect(a.tone, AnswerTone.warn);
      expect(a.narrative, contains('超支 ¥720.50'));
      expect(a.headline, '¥720.50');
    });

    test('没设预算：说清楚，并给已花金额', () {
      final FinanceAnswer a = buildFinanceAnswer(
        BudgetIntent(period: _oct),
        _data(),
      );
      expect(a.narrative, contains('还没设预算'));
      expect(a.narrative, contains('已经花了 ¥2,720.50'));
    });
  });

  group('环比对比', () {
    test('涨了：差额、百分比、涨最多的两个分类', () {
      final FinanceAnswer a = buildFinanceAnswer(
        CompareIntent(current: _oct, previous: _sep, categoryFocus: true),
        _data(),
      );
      expect(a.headline, '+¥1,430.50'); // 2720.50 - 1290.00
      expect(a.narrative, contains('多 ¥1,430.50'));
      expect(a.narrative, contains('110.9%'));
      expect(a.narrative, contains('餐饮'));
      expect(a.narrative, contains('购物'));
    });

    test('上期没有数据：明说没法比较', () {
      final FinanceAnswer a = buildFinanceAnswer(
        CompareIntent(current: _oct, previous: _sep, categoryFocus: false),
        _data(rows: _rows.where((TxRow t) => t.occurredAt >= _oct.startMs).toList()),
      );
      expect(a.narrative, contains('没有支出记录，没法比较'));
      expect(a.headline, isNull);
    });
  });

  group('大额支出', () {
    test('按金额降序取前 N 笔，并给出占比', () {
      final FinanceAnswer a = buildFinanceAnswer(
        TopExpensesIntent(period: _oct, limit: 2),
        _data(),
      );
      expect(a.facts.length, 2);
      expect(a.facts.first.value, '¥1,280.50');
      expect(a.facts[1].value, '¥980.00');
      expect(a.narrative, contains('¥2,260.50')); // 1280.50 + 980
      expect(a.narrative, contains('83.1%'));
    });
  });

  group('储蓄目标', () {
    test('纯算术：月数向上取整 + 大约几月', () {
      final FinanceAnswer a = buildFinanceAnswer(
        const SavingsGoalIntent(monthlyCents: 200000, targetCents: 2000000),
        FinanceData(nowMs: _nowMs),
      );
      expect(a.headline, '10 个月');
      expect(a.narrative, contains('2027 年 8 月'));
      expect(a.narrative, contains('不含利息'));
    });

    test('除不尽时向上取整', () {
      final FinanceAnswer a = buildFinanceAnswer(
        const SavingsGoalIntent(monthlyCents: 300000, targetCents: 2000000),
        FinanceData(nowMs: _nowMs),
      );
      expect(a.headline, '7 个月'); // 20000 / 3000 = 6.67 → 7
    });
  });

  group('不认识', () {
    test('给示例问题，不编答案', () {
      final FinanceAnswer a = buildFinanceAnswer(
        const UnknownIntent('帮我写首诗'),
        FinanceData(nowMs: _nowMs),
      );
      expect(a.suggestions, kExampleQuestions);
      expect(a.headline, isNull);
      expect(a.narrative, contains('只能答「账本里的数」'));
    });
  });
}
