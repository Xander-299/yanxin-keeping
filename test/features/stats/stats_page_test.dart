/// 统计页 widget 测试：入口、分类占比、方向切换、趋势、空态、翻月。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/pump_app.dart';

class _Seed {
  const _Seed(this.book, this.expenseCat, this.incomeCat);

  final Book book;
  final Category expenseCat;
  final Category incomeCat;
}

Future<_Seed> _seed(AppDatabase db) async {
  final book = await BookRepository(db).ensureDefaultBook();
  final expenseCat = (await CategoryRepository(db).listByBook(
    book.id,
    kind: 'expense',
  )).first;
  final incomeCat = (await CategoryRepository(db).listByBook(
    book.id,
    kind: 'income',
  )).first;
  final accountId = (await AccountRepository(db).listByBook(book.id)).first.id;
  final repo = TransactionRepository(db);
  final now = DateTime.now();

  // 当月：餐饮 23.50 + 交通 11.50（支出）、红包 20.00（收入）
  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: expenseCat.id,
    type: 'expense',
    amountCents: 2350,
    occurredAt: DateTime(now.year, now.month, 8, 12).millisecondsSinceEpoch,
    note: '午餐',
  );
  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: expenseCat.id,
    type: 'expense',
    amountCents: 1150,
    occurredAt: DateTime(now.year, now.month, 9, 19).millisecondsSinceEpoch,
    note: '晚餐',
  );
  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: incomeCat.id,
    type: 'income',
    amountCents: 2000,
    occurredAt: DateTime(now.year, now.month, 10, 9).millisecondsSinceEpoch,
    note: '红包',
  );
  // 上月一笔，验证趋势里能看到历史月
  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: expenseCat.id,
    type: 'expense',
    amountCents: 5000,
    occurredAt: DateTime(now.year, now.month - 1, 15, 9).millisecondsSinceEpoch,
    note: '上月',
  );
  return _Seed(book, expenseCat, incomeCat);
}

Future<void> _openStats(WidgetTester tester, AppDatabase db) async {
  await pumpApp(tester, database: db);
  await tester.tap(find.byTooltip('统计'));
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页「统计」图标 → 统计页：占比 + 趋势 + 汇总', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final seed = await _seed(db);

    await _openStats(tester, db);

    expect(find.text('分类占比'), findsOneWidget);
    expect(find.text('近 6 个月趋势'), findsOneWidget);
    expect(find.text('合计（元）'), findsOneWidget);
    // 图例：分类名 + 金额（同分类两笔合并 23.50 + 11.50 = 35.00）
    expect(find.text(seed.expenseCat.name), findsWidgets);
    expect(find.text('35.00'), findsWidgets);
    // 汇总：收入 / 支出 / 结余（「收入」「支出」在切换器与图例里也出现，只断言存在）
    expect(find.text('收入'), findsWidgets);
    expect(find.text('支出'), findsWidgets);
    expect(find.text('结余'), findsOneWidget);
    expect(find.text('-15.00'), findsWidgets);
  });

  testWidgets('切到「收入」→ 只看收入分类', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final seed = await _seed(db);

    await _openStats(tester, db);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('stats-kind-toggle')),
        matching: find.text('收入'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(seed.incomeCat.name), findsWidgets);
    expect(find.text(seed.expenseCat.name), findsNothing);
    expect(find.text('20.00'), findsWidgets);
  });

  testWidgets('翻到上月 → 只剩历史月那一笔；再翻上月是空态', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openStats(tester, db);
    final DateTime now = DateTime.now();
    final DateTime prev = DateTime(now.year, now.month - 1, 1);

    await tester.tap(find.byTooltip('上一月'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('${prev.year}年${prev.month}月'), findsOneWidget);
    expect(find.text('50.00'), findsWidgets);

    await tester.tap(find.byTooltip('上一月'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final DateTime prev2 = DateTime(now.year, now.month - 2, 1);
    expect(
      find.text('${prev2.year}年${prev2.month}月还没有支出记录'),
      findsOneWidget,
    );
    expect(find.text('合计（元）'), findsNothing);
  });

  testWidgets('趋势区间：近 6 个月柱子（含跨年）都渲染出来', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openStats(tester, db);

    final DateTime now = DateTime.now();
    for (var i = 0; i < 6; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      final String label = d.year == now.year
          ? '${d.month}月'
          : '${d.year % 100}年${d.month}月';
      expect(find.text(label), findsOneWidget, reason: '缺少 $label 这根柱子');
    }
  });
}
