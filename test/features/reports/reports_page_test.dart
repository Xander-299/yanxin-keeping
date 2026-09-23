/// 报表页 widget 测试：4 处入口、三档切换、展开、转账段、翻月、空态。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/pump_app.dart';

/// 造数据（全部落在**当月**，另加一笔上月用于翻月）：
/// - 现金：餐饮 33.50（午餐）、交通 12.00（打车）、工资 200.00（发工资）
/// - 招行：转账 50.00
/// - 上月：交通 66.00（上月打车）
Future<void> _seed(AppDatabase db) async {
  final book = await BookRepository(db).ensureDefaultBook();
  final accountRepo = AccountRepository(db);
  final cash = (await accountRepo.listByBook(book.id)).first;
  final bank = await accountRepo.create(
    bookId: book.id,
    name: '招行',
    type: 'bank',
    sortOrder: 1,
  );
  final catRepo = CategoryRepository(db);
  Future<Category> cat(String name, String kind) async =>
      (await catRepo.listByBook(book.id, kind: kind)).firstWhere(
        (Category c) => c.name == name,
      );
  final food = await cat('餐饮', 'expense');
  final traffic = await cat('交通', 'expense');
  final salary = await cat('工资', 'income');
  final repo = TransactionRepository(db);
  final now = DateTime.now();

  Future<void> add({
    required String accountId,
    String? categoryId,
    String type = 'expense',
    required int cents,
    required int day,
    int monthDelta = 0,
    required String note,
  }) => repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: categoryId,
    type: type,
    amountCents: cents,
    occurredAt: DateTime(
      now.year,
      now.month + monthDelta,
      day,
      9,
    ).millisecondsSinceEpoch,
    note: note,
  );

  await add(accountId: cash.id, categoryId: food.id, cents: 3350, day: 5, note: '午餐');
  await add(accountId: cash.id, categoryId: traffic.id, cents: 1200, day: 6, note: '打车');
  await add(
    accountId: cash.id,
    categoryId: salary.id,
    type: 'income',
    cents: 20000,
    day: 7,
    note: '发工资',
  );
  await add(
    accountId: bank.id,
    type: 'transfer',
    cents: 5000,
    day: 8,
    note: '转到招行',
  );
  await add(
    accountId: cash.id,
    categoryId: traffic.id,
    cents: 6600,
    day: 15,
    monthDelta: -1,
    note: '上月打车',
  );
}

/// 从首页 header 的「报表」图标进（默认「分类」档）。
Future<void> _openFromHeader(WidgetTester tester, AppDatabase db) async {
  await pumpApp(tester, database: db);
  await tester.tap(find.byTooltip('报表'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页「报表」图标 → 报表页，默认「分类」档', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openFromHeader(tester, db);

    expect(find.text('报表'), findsOneWidget); // AppBar 标题
    // 「支出 / 收入」段标题只在分类档出现（明细档没有段标题）
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('收入'), findsOneWidget);
    expect(find.text('¥45.50'), findsOneWidget); // 支出段合计
    expect(find.text('¥200.00'), findsOneWidget); // 收入段合计
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('33.50'), findsOneWidget); // 餐饮行金额
    expect(find.text('73.6%'), findsOneWidget); // 33.50 / 45.50
  });

  testWidgets('首页「全部账单 ›」→ 报表页，默认「明细」档（按天分组）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await pumpApp(tester, database: db);
    await tester.tap(find.text('全部账单'));
    await tester.pumpAndSettle();

    expect(find.textContaining('笔 · 支出 ¥'), findsWidgets); // 组头带笔数与支出合计
    expect(find.text('午餐'), findsOneWidget); // 组内复用流水行
    expect(find.text('支出'), findsNothing); // 明细档没有段标题
  });

  testWidgets('切「账户」档 → 一行一个账户（支出 / 收入 / 转账 + 笔数）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openFromHeader(tester, db);
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();

    expect(find.text('现金'), findsOneWidget);
    expect(find.text('招行'), findsOneWidget);
    expect(find.textContaining('支出 ¥'), findsWidgets);
    expect(find.textContaining('转账 ¥'), findsWidgets);
    expect(find.textContaining('已删除账户的历史流水'), findsOneWidget);
  });

  testWidgets('分类档点分类行 → 展开该分类的流水；只展开被点的那一个', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openFromHeader(tester, db);
    expect(find.text('午餐'), findsNothing); // 折叠态默认收起

    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('打车'), findsNothing); // 交通那组仍收起
  });

  testWidgets('转账单列一段（不计入支出 / 收入）', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openFromHeader(tester, db);

    expect(find.text('转账'), findsOneWidget);
    expect(find.text('1 笔 · ¥50.00'), findsOneWidget);
    expect(find.textContaining('转账不计入支出 / 收入'), findsOneWidget);
  });

  testWidgets('翻到上月 → 换数据；再翻一月 → 空态', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openFromHeader(tester, db);
    final DateTime now = DateTime.now();
    final DateTime prev = DateTime(now.year, now.month - 1, 1);

    await tester.tap(find.byTooltip('上一月'));
    await tester.pumpAndSettle();

    expect(find.text('${prev.year}年${prev.month}月'), findsOneWidget);
    expect(find.text('66.00'), findsOneWidget); // 上月那笔交通
    expect(find.text('餐饮'), findsNothing);

    await tester.tap(find.byTooltip('上一月'));
    await tester.pumpAndSettle();

    expect(find.text('这个月还没有记账'), findsOneWidget);
    expect(find.text('去记一笔'), findsOneWidget);
  });

  testWidgets('日历页 header「报表」→ 明细档 + 月份对齐日历页', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await pumpApp(tester, database: db);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('报表'));
    await tester.pumpAndSettle();

    final DateTime now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    expect(find.textContaining('笔 · 支出 ¥'), findsWidgets);
    expect(find.text('支出'), findsNothing); // 明细档
  });
}
