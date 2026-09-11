/// 统计聚合纯函数测试：分类占比 / 趋势区间 / 按月趋势。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/features/stats/application/stats_aggregate.dart';

TxRow _tx({
  required String type,
  required int cents,
  required DateTime at,
  String? categoryId,
  String id = 't1',
}) {
  return TxRow(
    id: id,
    bookId: 'b1',
    accountId: 'a1',
    categoryId: categoryId,
    type: type,
    amountCents: cents,
    note: '',
    occurredAt: at.millisecondsSinceEpoch,
    source: 'manual',
    createdAt: at.millisecondsSinceEpoch,
    updatedAt: at.millisecondsSinceEpoch,
    dirty: 1,
  );
}

void main() {
  final DateTime sep = DateTime(2026, 9, 10, 12);

  group('categoryBreakdown', () {
    test('按分类汇总、按金额降序、算占比', () {
      final items = <TxRow>[
        _tx(type: 'expense', cents: 3000, at: sep, categoryId: 'c-food'),
        _tx(type: 'expense', cents: 1500, at: sep, categoryId: 'c-food'),
        _tx(type: 'expense', cents: 5500, at: sep, categoryId: 'c-trans'),
      ];
      final slices = categoryBreakdown(
        items,
        type: 'expense',
        nameOf: (String? id) => id == 'c-food' ? '餐饮' : '交通',
      );

      expect(slices, hasLength(2));
      expect(slices.first.id, 'c-trans');
      expect(slices.first.cents, 5500);
      expect(slices.first.name, '交通');
      expect(slices.first.percentText, '55.0%');
      expect(slices.last.cents, 4500);
      expect(slices.last.percentText, '45.0%');
    });

    test('只统计指定方向，transfer 不计入', () {
      final items = <TxRow>[
        _tx(type: 'expense', cents: 1000, at: sep, categoryId: 'c1'),
        _tx(type: 'income', cents: 9999, at: sep, categoryId: 'c2'),
        _tx(type: 'transfer', cents: 8888, at: sep, categoryId: 'c3'),
      ];

      final expense = categoryBreakdown(items, type: 'expense');
      expect(expense, hasLength(1));
      expect(expense.single.cents, 1000);
      expect(expense.single.ratio, 1.0);

      final income = categoryBreakdown(items, type: 'income');
      expect(income.single.cents, 9999);
    });

    test('无分类归到「未分类」；名字查不到也归未分类', () {
      final items = <TxRow>[
        _tx(type: 'expense', cents: 1200, at: sep),
        _tx(type: 'expense', cents: 800, at: sep, categoryId: 'c-gone'),
      ];
      final slices = categoryBreakdown(
        items,
        type: 'expense',
        nameOf: (String? id) => '未分类',
      );
      expect(slices, hasLength(2));
      expect(
        slices.every((CategorySlice s) => s.name == '未分类'),
        isTrue,
      );
      expect(slices.first.cents, 1200);
    });

    test('空输入返回空列表（页面据此显示空态）', () {
      expect(categoryBreakdown(<TxRow>[], type: 'expense'), isEmpty);
    });
  });

  group('trendRange', () {
    test('含当月往前推 months 个月（同年）', () {
      final r = trendRange(2026, 9, 6);
      expect(DateTime.fromMillisecondsSinceEpoch(r.start), DateTime(2026, 4, 1));
      expect(DateTime.fromMillisecondsSinceEpoch(r.end), DateTime(2026, 10, 1));
    });

    test('跨年时起始落在上一年', () {
      final r = trendRange(2026, 2, 6);
      expect(DateTime.fromMillisecondsSinceEpoch(r.start), DateTime(2025, 9, 1));
      expect(DateTime.fromMillisecondsSinceEpoch(r.end), DateTime(2026, 3, 1));
    });
  });

  group('monthlyTrend', () {
    test('缺月补 0，按时间升序，柱子数量恒为 months', () {
      final rows = <TxRow>[
        _tx(type: 'expense', cents: 5000, at: DateTime(2026, 4, 5)),
        _tx(type: 'income', cents: 12000, at: DateTime(2026, 9, 1)),
      ];
      final points = monthlyTrend(
        year: 2026,
        month: 9,
        months: 6,
        rows: rows,
      );

      expect(points, hasLength(6));
      expect(points.first.year, 2026);
      expect(points.first.month, 4);
      expect(points.first.expenseCents, 5000);
      expect(points.last.month, 9);
      expect(points.last.incomeCents, 12000);
      // 5-8 月没有数据 → 补 0
      expect(
        points.sublist(1, 5).every(
          (MonthPoint p) => p.incomeCents == 0 && p.expenseCents == 0,
        ),
        isTrue,
      );
    });

    test('跨年趋势月份换算正确', () {
      final rows = <TxRow>[
        _tx(type: 'expense', cents: 100, at: DateTime(2025, 12, 31, 23, 59)),
      ];
      final points = monthlyTrend(
        year: 2026,
        month: 2,
        months: 6,
        rows: rows,
      );
      expect(points.first.year, 2025);
      expect(points.first.month, 9);
      expect(points[3].year, 2025);
      expect(points[3].month, 12);
      expect(points[3].expenseCents, 100);
      expect(points.last.year, 2026);
      expect(points.last.month, 2);
      // 跨年标签带年份
      expect(points[3].labelOf(2026), '25年12月');
      expect(points.last.labelOf(2026), '2月');
    });

    test('区间外的流水被忽略', () {
      final rows = <TxRow>[
        _tx(type: 'expense', cents: 700, at: DateTime(2025, 1, 1)),
      ];
      final points = monthlyTrend(
        year: 2026,
        month: 9,
        months: 6,
        rows: rows,
      );
      expect(
        points.every((MonthPoint p) => p.expenseCents == 0),
        isTrue,
      );
    });
  });
}
