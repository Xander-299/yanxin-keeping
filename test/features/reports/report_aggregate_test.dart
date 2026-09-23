/// 报表聚合纯函数测试（SPEC-F7.7 §A.5）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/features/reports/application/report_aggregate.dart';

/// 固定基准时间：2026-09-23 12:00（周三）。
final int _nowMs = DateTime(2026, 9, 23, 12).millisecondsSinceEpoch;

TxRow _tx({
  String id = 't1',
  String accountId = 'a1',
  String? categoryId,
  String type = 'expense',
  required int cents,
  String note = '',
  int? at,
}) {
  final int ts = at ?? _nowMs;
  return TxRow(
    id: id,
    bookId: 'b1',
    accountId: accountId,
    categoryId: categoryId,
    type: type,
    amountCents: cents,
    note: note,
    occurredAt: ts,
    source: 'manual',
    createdAt: ts,
    updatedAt: ts,
    dirty: 1,
  );
}

/// 分类名映射：拿不到名字的 id 返回「未分类」（与页面注入的解析器同口径）。
String _nameOf(String? id) => switch (id) {
  'c1' => '餐饮',
  'c2' => '交通',
  'c3' => '工资',
  _ => kUncategorized,
};

void main() {
  group('groupByCategory', () {
    test('只取指定方向，transfer 与另一方向都不计入', () {
      final items = <TxRow>[
        _tx(id: 'e1', categoryId: 'c1', cents: 3350),
        _tx(id: 'e2', categoryId: 'c2', cents: 1200),
        _tx(id: 'i1', categoryId: 'c3', type: 'income', cents: 20000),
        _tx(id: 'x1', type: 'transfer', cents: 5000),
      ];

      final expense = groupByCategory(items, type: 'expense', nameOf: _nameOf);
      expect(expense.length, 2);
      expect(expense.any((ReportGroup g) => g.title == '工资'), isFalse);
      expect(sumCentsOf(items, kReportExpense), 4550);

      final income = groupByCategory(items, type: 'income', nameOf: _nameOf);
      expect(income.length, 1);
      expect(income.first.title, '工资');
      expect(income.first.incomeCents, 20000);
      expect(income.first.expenseCents, 0);
      expect(income.first.totalCents, 20000);
    });

    test('金额降序；同分类多笔合并并给出笔数', () {
      final items = <TxRow>[
        _tx(id: 'e1', categoryId: 'c2', cents: 1200),
        _tx(id: 'e2', categoryId: 'c1', cents: 1000),
        _tx(id: 'e3', categoryId: 'c1', cents: 2350),
      ];

      final groups = groupByCategory(items, type: 'expense', nameOf: _nameOf);
      expect(groups.map((ReportGroup g) => g.title).toList(), <String>['餐饮', '交通']);
      expect(groups.first.txCount, 2);
      expect(groups.first.totalCents, 3350);
      expect(groups.last.txCount, 1);
      expect(groups.last.totalCents, 1200);
    });

    test('无分类与查不到名字的 id 合并成「未分类」一行', () {
      final items = <TxRow>[
        _tx(id: 'e1', categoryId: null, cents: 100),
        _tx(id: 'e2', categoryId: 'ghost', cents: 200),
      ];

      final groups = groupByCategory(items, type: 'expense', nameOf: _nameOf);
      expect(groups.length, 1);
      expect(groups.first.title, kUncategorized);
      expect(groups.first.totalCents, 300);
      expect(groups.first.txCount, 2);
    });

    test('空列表 → 空结果', () {
      expect(
        groupByCategory(<TxRow>[], type: 'expense', nameOf: _nameOf),
        isEmpty,
      );
    });
  });

  group('groupByAccount', () {
    test('按 accountId 聚合支出 / 收入 / 转账三向金额与笔数', () {
      final items = <TxRow>[
        _tx(id: 'e1', accountId: 'a1', categoryId: 'c1', cents: 3350),
        _tx(id: 'e2', accountId: 'a1', categoryId: 'c2', cents: 1200),
        _tx(id: 'i1', accountId: 'a1', categoryId: 'c3', type: 'income', cents: 20000),
        _tx(id: 'x1', accountId: 'a2', type: 'transfer', cents: 5000),
      ];

      final groups = groupByAccount(
        items,
        knownAccountIds: <String>{'a1', 'a2'},
        nameOf: (String id) => id == 'a1' ? '现金' : '招行',
      );
      // 合计降序：现金 24550 > 招行 5000
      expect(groups.map((ReportGroup g) => g.title).toList(), <String>['现金', '招行']);
      final cash = groups.first;
      expect(cash.expenseCents, 4550);
      expect(cash.incomeCents, 20000);
      expect(cash.transferCents, 0);
      expect(cash.txCount, 3);
      final bank = groups.last;
      expect(bank.expenseCents, 0);
      expect(bank.transferCents, 5000);
      expect(bank.txCount, 1);
    });

    test('已软删 / 空串账户的流水归到「其他账户」', () {
      final items = <TxRow>[
        _tx(id: 'e1', accountId: 'a1', cents: 1000),
        _tx(id: 'e2', accountId: 'deleted', cents: 2000),
        _tx(id: 'e3', accountId: '', cents: 3000),
      ];

      final groups = groupByAccount(
        items,
        knownAccountIds: <String>{'a1'},
        nameOf: (String _) => '现金',
      );
      expect(groups.length, 2);
      final other = groups.singleWhere(
        (ReportGroup g) => g.key == kOtherAccountKey,
      );
      expect(other.title, kOtherAccountTitle);
      expect(other.totalCents, 5000);
      expect(other.txCount, 2);
    });

    test('已知账户集合为空 → 全部归到「其他账户」', () {
      final groups = groupByAccount(
        <TxRow>[_tx(cents: 999)],
        knownAccountIds: const <String>{},
        nameOf: (String _) => '现金',
      );
      expect(groups.single.title, kOtherAccountTitle);
      expect(groups.single.totalCents, 999);
    });
  });

  group('transferRows / sumCentsOf', () {
    test('transferRows 只取转账；sumCentsOf 只累加指定方向', () {
      final items = <TxRow>[
        _tx(id: 'e1', cents: 3350),
        _tx(id: 'e2', cents: 1200),
        _tx(id: 'x1', type: 'transfer', cents: 5000),
      ];
      final transfers = transferRows(items);
      expect(transfers.length, 1);
      expect(transfers.first.id, 'x1');
      expect(sumCentsOf(items, kReportExpense), 4550);
      expect(sumCentsOf(items, kReportTransfer), 5000);
      expect(sumCentsOf(items, kReportIncome), 0);
    });
  });

  group('reportDayLabel', () {
    int at(int y, int m, int d) => DateTime(y, m, d, 9).millisecondsSinceEpoch;

    test('今天 / 昨天带星期；同年只写月日，跨年带年份', () {
      expect(reportDayLabel(at(2026, 9, 23), now: _nowMs), '今天 9月23日 周三');
      expect(reportDayLabel(at(2026, 9, 22), now: _nowMs), '昨天 9月22日 周二');
      expect(reportDayLabel(at(2026, 9, 8), now: _nowMs), '9月8日 周二');
      expect(reportDayLabel(at(2025, 12, 3), now: _nowMs), '2025年12月3日 周三');
    });
  });
}
