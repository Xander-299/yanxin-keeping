/// 日历页 widget 测试：月历标注、选中日账单、月汇总、月份选择子页、按日期记一笔。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/record/presentation/record_page.dart';

import '../../helpers/pump_app.dart';

/// 等异步写库 + provider 重建到位。
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

void main() {
  /// 造一个「不是今天」的日号（各月都存在，且不等于今天）。
  int otherDay() {
    final int today = DateTime.now().day;
    return today == 15 ? 16 : 15;
  }

  Future<void> seedMonthTx(
    dynamic db, {
    required int day,
    int expense = 2350,
    int income = 2000,
  }) async {
    final book = await BookRepository(db).ensureDefaultBook();
    final catRepo = CategoryRepository(db);
    final expenseCat = (await catRepo.listByBook(book.id, kind: 'expense')).first;
    final incomeCat = (await catRepo.listByBook(book.id, kind: 'income')).first;
    final accountId = (await AccountRepository(db).listByBook(book.id)).first.id;
    final now = DateTime.now();
    final repo = TransactionRepository(db);
    if (expense > 0) {
      await repo.create(
        bookId: book.id,
        accountId: accountId,
        categoryId: expenseCat.id,
        type: 'expense',
        amountCents: expense,
        occurredAt: DateTime(now.year, now.month, day, 10).millisecondsSinceEpoch,
        note: '午餐',
      );
    }
    if (income > 0) {
      await repo.create(
        bookId: book.id,
        accountId: accountId,
        categoryId: incomeCat.id,
        type: 'income',
        amountCents: income,
        occurredAt: DateTime(now.year, now.month, day, 12).millisecondsSinceEpoch,
        note: '红包',
      );
    }
  }

  testWidgets('日历 tab：显示年月、表头、每日标注与月汇总', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final int day = otherDay();
    await seedMonthTx(db, day: day);

    await pumpApp(tester, database: db);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    final DateTime now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    // 表头（周日起始）
    for (final String w in <String>['日', '一', '二', '三', '四', '五', '六']) {
      expect(find.text(w), findsOneWidget);
    }
    // 当天支出负号、收入正号（紧凑写法）
    expect(find.text('-23.5'), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    // 月汇总条
    expect(find.text('月结余'), findsOneWidget);
    expect(find.text('日均支出'), findsOneWidget);
  });

  testWidgets('点日历某天 → 下方显示该天账单；今天默认选中且为空态', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final int day = otherDay();
    await seedMonthTx(db, day: day);

    await pumpApp(tester, database: db);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    // 默认选中今天 → 今天没有账单
    expect(find.textContaining('今天'), findsOneWidget);
    expect(find.text('这天没有账单哦，赶紧记一笔吧~'), findsOneWidget);

    // 点第 day 天 → 显示该天两笔（餐饮/红包由分类名呈现，金额两位小数）
    await tester.tap(find.text('$day'));
    await tester.pumpAndSettle();
    expect(find.textContaining('${DateTime.now().month}月$day日'), findsOneWidget);
    expect(find.text('-23.50'), findsOneWidget);
    expect(find.text('+20.00'), findsOneWidget);
    expect(find.text('这天没有账单哦，赶紧记一笔吧~'), findsNothing);
  });

  testWidgets('日历空态「记一笔」→ 记一笔页日期带入选中日', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();

    await pumpApp(tester, database: db);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    final int day = otherDay();
    await tester.tap(find.text('$day'));
    await tester.pumpAndSettle();
    // 800×600 测试视口下空态按钮在折叠下方 → 先滚进可视区
    await tester.ensureVisible(find.text('记一笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    final DateTime now = DateTime.now();
    expect(find.text('日期'), findsOneWidget);
    expect(find.textContaining('${now.year}年${now.month}月$day日'), findsOneWidget);
  });

  testWidgets('点 header 年月 → 月份选择子页；点缩略图某天 → 回到日历并切月选日', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();

    await pumpApp(tester, database: db);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    final int year = DateTime.now().year;
    await tester.tap(find.text('$year年${DateTime.now().month}月'));
    await tester.pumpAndSettle();

    // 子页：标题为年份，12 个月缩略图 + 年份切换
    expect(find.text('$year年'), findsOneWidget);
    for (int m = 1; m <= 12; m++) {
      expect(find.text('$m月'), findsOneWidget);
    }
    expect(find.text('‹ 上一年'), findsOneWidget);
    expect(find.text('下一年 ›'), findsOneWidget);

    // 点 3 月的 7 号 → 回日历页且切到 3 月并选中 7 日
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('mini-month-3')),
        matching: find.text('7'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('$year年3月'), findsOneWidget);
    expect(find.textContaining('3月7日'), findsOneWidget);
  });

  testWidgets('子页「上一年/下一年」切换年份', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();

    await pumpApp(tester, database: db);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    final int year = DateTime.now().year;
    await tester.tap(find.text('$year年${DateTime.now().month}月'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一年 ›'));
    await tester.pumpAndSettle();
    expect(find.text('${year + 1}年'), findsOneWidget);

    await tester.tap(find.text('‹ 上一年'));
    await tester.pumpAndSettle();
    expect(find.text('$year年'), findsOneWidget);
  });

  testWidgets('记一笔：传入 occurredAtMs 时按该日期入账', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final book = await BookRepository(db).ensureDefaultBook();
    final cat = (await CategoryRepository(db).listByBook(book.id, kind: 'expense')).first;
    final target = DateTime(2026, 3, 7, 9, 30);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: RecordPage(occurredAtMs: target.millisecondsSinceEpoch),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 日期字段展示目标日期
    expect(find.text('日期'), findsOneWidget);
    expect(find.textContaining('2026年3月7日'), findsOneWidget);

    // 录金额 5.00 + 选分类 + 保存
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('请选择分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cat.name).last);
    await tester.pumpAndSettle();
    // F7.6 起主按钮是 ToonButton（胶囊），不再是 FilledButton
    await tester.ensureVisible(find.widgetWithText(ToonButton, '记一笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ToonButton, '记一笔'));
    await tester.pumpAndSettle();

    final rows = await TransactionRepository(db).listByMonth(book.id, 2026, 3);
    expect(rows, hasLength(1));
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(rows.first.occurredAt);
    expect(at.year, 2026);
    expect(at.month, 3);
    expect(at.day, 7);
    expect(rows.first.amountCents, 500);
    // 3 月的账不该出现在 9 月
    expect(await TransactionRepository(db).listByMonth(book.id, 2026, 9), isEmpty);
  });
}
