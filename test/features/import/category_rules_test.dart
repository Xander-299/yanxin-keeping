/// 移植自旧栈 tests/bill-import/categorize.test.js。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/import/data/bill_normalize.dart';
import 'package:yanxin/features/import/data/category_rules.dart';

ParsedRow _row({
  String counterparty = '',
  String product = '',
  String direction = 'expense',
}) {
  return ParsedRow(
    source: 'wechat_csv',
    externalId: '',
    occurredAt: 0,
    amountCents: 100,
    direction: direction,
    counterparty: counterparty,
    product: product,
    method: '',
    status: '',
    unknownStatus: false,
    rawIndex: 0,
  );
}

void main() {
  group('规则表完整性', () {
    test('规则总数约 40 条（20-60 之间）', () {
      expect(categoryRules.length, greaterThanOrEqualTo(20));
      expect(categoryRules.length, lessThanOrEqualTo(60));
    });

    test('规则只引用预置分类名，kind 只能是 expense/income', () {
      const expenseNames = ['餐饮', '交通', '购物', '居住', '娱乐', '医疗', '教育', '人情', '其他'];
      const incomeNames = ['工资', '奖金', '理财', '兼职', '红包', '其他'];
      for (final r in categoryRules) {
        expect(<String>['expense', 'income'], contains(r.kind));
        final valid = r.kind == 'expense' ? expenseNames : incomeNames;
        expect(
          valid,
          contains(r.category),
          reason: '分类「${r.category}」不在预置分类中',
        );
      }
    });
  });

  group('categorizeRow', () {
    test('关键词命中：美团 → 餐饮', () {
      final r = categorizeRow(
        _row(counterparty: '美团平台商户', product: '外卖订单'),
      );
      expect(r.categoryName, '餐饮');
      expect(r.matched, isTrue);
    });

    test('交易对方不命中时匹配商品名', () {
      expect(
        categorizeRow(_row(counterparty: '某某个体', product: '滴滴快车费')).categoryName,
        '交通',
      );
    });

    test('不区分大小写：steam → 娱乐', () {
      expect(
        categorizeRow(_row(counterparty: 'VALVE', product: 'steam purchase')).categoryName,
        '娱乐',
      );
    });

    test('先命中先赢：美团外卖不会被后面的「购物」抢走', () {
      expect(
        categorizeRow(_row(counterparty: '美团', product: '买菜')).categoryName,
        '餐饮',
      );
    });

    test('未命中落「其他」且 matched=false', () {
      final r = categorizeRow(_row(counterparty: '无关键词商户', product: '神秘商品'));
      expect(r.categoryName, '其他');
      expect(r.matched, isFalse);
    });

    test('收入走收入规则：工资代发 → 工资', () {
      final r = categorizeRow(
        _row(counterparty: '某某科技公司', product: '工资代发', direction: 'income'),
      );
      expect(r.categoryName, '工资');
      expect(r.matched, isTrue);
    });

    test('收入不命中 → 收入的「其他」', () {
      expect(
        categorizeRow(_row(counterparty: '某某', product: '返现', direction: 'income')).categoryName,
        '其他',
      );
    });

    test('同一关键词在支出/收入侧可映射不同分类', () {
      // 「转账/红包」在收入侧是红包；支出侧不命中这些词时仍按其他规则
      expect(
        categorizeRow(_row(counterparty: '张三', product: '转账', direction: 'income')).categoryName,
        '红包',
      );
    });
  });
}
