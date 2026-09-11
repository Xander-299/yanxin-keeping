/// 日历聚合纯函数单测（按天汇总 / 日均支出 / 紧凑金额）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/calendar/application/calendar_aggregate.dart';

import '../../helpers/test_database.dart';

void main() {
  group('aggregateByDay', () {
    late AppDatabase db;
    late TransactionRepository repo;

    setUp(() {
      db = openTestDatabase();
      addTearDown(db.close);
      repo = TransactionRepository(db);
    });

    Future<void> add(String type, int cents, DateTime at) => repo.create(
      bookId: 'b1',
      accountId: 'a1',
      categoryId: 'c1',
      type: type,
      amountCents: cents,
      occurredAt: at.millisecondsSinceEpoch,
    );

    test('同一天的支出累加、收入另算', () async {
      await add('expense', 2350, DateTime(2026, 8, 3, 9));
      await add('expense', 1150, DateTime(2026, 8, 3, 20));
      await add('income', 2080, DateTime(2026, 8, 3, 12));

      final agg = aggregateByDay(await repo.listByMonth('b1', 2026, 8));
      expect(agg.keys, <int>[3]);
      expect(agg[3]!.expenseCents, 3500);
      expect(agg[3]!.incomeCents, 2080);
      expect(agg[3]!.hasExpense, isTrue);
      expect(agg[3]!.hasIncome, isTrue);
    });

    test('不同天分开，且键升序', () async {
      await add('expense', 100, DateTime(2026, 8, 20, 8));
      await add('expense', 200, DateTime(2026, 8, 5, 8));

      final agg = aggregateByDay(await repo.listByMonth('b1', 2026, 8));
      expect(agg.keys.toList(), <int>[5, 20]);
      expect(agg[5]!.expenseCents, 200);
      expect(agg[20]!.expenseCents, 100);
    });

    test('transfer 不计收支', () async {
      await add('transfer', 5000, DateTime(2026, 8, 7, 8));
      final agg = aggregateByDay(await repo.listByMonth('b1', 2026, 8));
      expect(agg, isEmpty);
    });

    test('hasAnyTx 只认当月传入的流水', () async {
      await add('expense', 100, DateTime(2026, 8, 9, 8));
      final items = await repo.listByMonth('b1', 2026, 8);
      expect(hasAnyTx(items, 9), isTrue);
      expect(hasAnyTx(items, 10), isFalse);
    });
  });

  group('dailyAvgExpenseCents', () {
    test('历史月按整月天数折算', () {
      // 2026-08 有 31 天；支出 1017.42 元 = 101742 分 → 3282 分（32.82）
      final avg = dailyAverageExpenseCents(
        expenseCents: 101742,
        year: 2026,
        month: 8,
        nowMs: DateTime(2026, 9, 11).millisecondsSinceEpoch,
      );
      expect(avg, 3282);
      expect(centsToYuan(avg), '32.82');
    });

    test('当月按已过天数折算（含今天）', () {
      // 2026-09-11：11 天；支出 1100 分 → 100 分
      final avg = dailyAverageExpenseCents(
        expenseCents: 1100,
        year: 2026,
        month: 9,
        nowMs: DateTime(2026, 9, 11, 10).millisecondsSinceEpoch,
      );
      expect(avg, 100);
    });

    test('零支出为 0；二月闰年按 29 天', () {
      expect(
        dailyAverageExpenseCents(
          expenseCents: 0,
          year: 2026,
          month: 8,
          nowMs: DateTime(2026, 9, 11).millisecondsSinceEpoch,
        ),
        0,
      );
      // 2028 是闰年：2 月 29 天，支出 2900 分 → 100 分
      expect(
        dailyAverageExpenseCents(
          expenseCents: 2900,
          year: 2028,
          month: 2,
          nowMs: DateTime(2028, 3, 5).millisecondsSinceEpoch,
        ),
        100,
      );
    });
  });

  group('compactYuan', () {
    test('去掉末尾多余的 0', () {
      expect(compactYuan(-2310), '-23.1');
      expect(compactYuan(2080), '20.8');
      expect(compactYuan(-7324), '-73.24');
      expect(compactYuan(100), '1');
    });
  });
}
