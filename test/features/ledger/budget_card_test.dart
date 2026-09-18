/// 预算卡 widget 测试：未设预算 / 真实数字 / 超支 / 设置弹窗端到端。
///
/// 回归：首次使用验收 P2 —— 卡上曾是写死的示例数字（101.52 / 10.2%），
/// 与同屏 hero 的真实月支出矛盾。这里盯着「不许再出现假数字」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/budget_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/ledger/presentation/widgets/budget_card.dart';

import '../../helpers/test_database.dart';
/// 等异步写库 + provider 重建到位。
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

Future<void> pumpCard(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BudgetCard())),
      ),
    ),
  );
  // 注意不能等「本月预算」：加载骨架里也有这行字，会在数据到位前就返回
  await pumpUntil(tester, find.text('本月日均消费'));
}

/// 造一笔当月支出（默认 101.52，与旧占位卡的假数字一致，便于对拍）。
/// 返回账本 id。
Future<String> seedExpense(AppDatabase db, {int amountCents = 10152}) async {
  final book = await BookRepository(db).ensureDefaultBook();
  final cat = (await CategoryRepository(db).listByBook(
    book.id,
    kind: 'expense',
  )).first;
  final accountId = (await AccountRepository(db).listByBook(book.id)).first.id;
  final now = DateTime.now();
  await TransactionRepository(db).create(
    bookId: book.id,
    accountId: accountId,
    categoryId: cat.id,
    type: 'expense',
    amountCents: amountCents,
    occurredAt: DateTime(now.year, now.month, 8, 12).millisecondsSinceEpoch,
    note: '午餐',
  );
  return book.id;
}

void main() {
  testWidgets('未设预算：给引导 + 不显示任何假数字', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await seedExpense(db); // 有真实支出，但没设预算
    await pumpCard(tester, db);

    expect(find.text('本月预算'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.textContaining('设一个月度预算'), findsOneWidget);
    expect(find.textContaining('设置'), findsWidgets); // 「设置N月预算」按钮

    // 旧占位卡的示例数字与标注必须彻底消失
    expect(find.text('示例'), findsNothing);
    expect(find.textContaining('预算功能建设中'), findsNothing);
    expect(find.text('1,000.00'), findsNothing);
    expect(find.text('898.48'), findsNothing);
    expect(find.text('10.2%'), findsNothing);

    // 没预算也能看到真实日均（101.52 / 当天几号）。
    // 「剩余每日可消费」自 F7.6 起按原型无条件保留，但没预算时值必须是「—」
    // 而不是 0（0 会被读成「今天不能花了」）。
    expect(find.text('本月日均消费'), findsOneWidget);
    expect(find.text('剩余每日可消费'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('已设预算 1000 + 支出 101.52 → 10.2% / 剩余 898.48', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final book = await BookRepository(db).ensureDefaultBook();
    await BudgetRepository(db).setForMonth(
      bookId: book.id,
      year: DateTime.now().year,
      month: DateTime.now().month,
      amountCents: 100000,
    );
    await seedExpense(db);
    await pumpCard(tester, db);

    expect(find.text('本月预算'), findsOneWidget);
    expect(find.text('1,000.00'), findsOneWidget);
    expect(find.text('10.2%'), findsOneWidget);
    expect(find.text('101.52'), findsOneWidget);
    expect(find.text('898.48'), findsOneWidget);
    expect(find.text('剩余额度'), findsOneWidget);
    expect(find.text('剩余每日可消费'), findsOneWidget);
    expect(find.text('已超支'), findsNothing);
    expect(find.text('未设置'), findsNothing);
  });

  testWidgets('超支：预算 1000 花 1200 → 120.0% / -200.00 / 「已超支」', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final book = await BookRepository(db).ensureDefaultBook();
    await BudgetRepository(db).setForMonth(
      bookId: book.id,
      year: DateTime.now().year,
      month: DateTime.now().month,
      amountCents: 100000,
    );
    await seedExpense(db, amountCents: 120000);
    await pumpCard(tester, db);

    expect(find.text('120.0%'), findsOneWidget);
    expect(find.text('-200.00'), findsOneWidget);
    expect(find.text('已超支'), findsOneWidget);
    // 超支后「剩余每日可消费」归 0，不能显示负数
    expect(find.text('0.00'), findsOneWidget);
  });

  testWidgets('点标题行 → 弹出设置弹窗（带当前月份与快捷键）', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await seedExpense(db);
    await pumpCard(tester, db);

    final now = DateTime.now();
    await tester.tap(find.text('本月预算'));
    await tester.pumpAndSettle();

    expect(find.text('设置 ${now.year}年${now.month}月 预算'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('5000'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    // 没设过预算 → 没有「删除预算」
    expect(find.text('删除预算'), findsNothing);
  });

  testWidgets('弹窗里设 2000 → 卡片立刻变成真实预算', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final String bookId = await seedExpense(db);
    await pumpCard(tester, db);

    await tester.tap(find.text('本月预算'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2000'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await pumpUntil(tester, find.text('2,000.00'));

    expect(find.text('2,000.00'), findsOneWidget);
    // 101.52 / 2000 = 5.1%
    expect(find.text('5.1%'), findsOneWidget);
    expect(find.text('1898.48'), findsOneWidget);

    // 落库了（不是只改内存）
    final now = DateTime.now();
    final row = await BudgetRepository(db).getForMonth(bookId, now.year, now.month);
    expect(row!.amountCents, 200000);

    // 走完 SnackBar 的定时器，避免测试结束时留下 pending timer
    await tester.pumpAndSettle();
  });

  testWidgets('金额非法：空 / 0 / 多个小数点 → 不保存并给提示', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final String bookId = await seedExpense(db);
    await pumpCard(tester, db);

    await tester.tap(find.text('本月预算'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入预算金额'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('金额要大于 0'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1.234');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('金额格式不对，最多两位小数'), findsOneWidget);

    // 一直没落库
    final now = DateTime.now();
    expect(await BudgetRepository(db).getForMonth(bookId, now.year, now.month), isNull);
  });
}
