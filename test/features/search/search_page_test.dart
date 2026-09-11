/// 搜索页 widget 测试：入口、三类命中、结果汇总、一键清空、无结果、删除链路。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/pump_app.dart';

const Key _inputKey = ValueKey<String>('search-input');
const Key _clearKey = ValueKey<String>('search-clear');

/// 造三笔跨月数据：
/// - 餐饮 88.88 / 备注「午餐」（当月 5 日，支出）
/// - 交通 12.00 / 备注「打车」（上月 20 日，支出）
/// - 餐饮补贴 200.00 / 备注「工资」（当月 8 日，收入）
///
/// 收入那笔特意用「餐饮补贴」：搜「餐饮」能一次命中支出 + 收入两笔，
/// 顺便验证「分类名命中」的并集与汇总行的收支合计。
Future<void> _seed(AppDatabase db) async {
  final book = await BookRepository(db).ensureDefaultBook();
  final catRepo = CategoryRepository(db);
  final food = await catRepo.create(
    bookId: book.id,
    name: '餐饮',
    kind: 'expense',
  );
  final traffic = await catRepo.create(
    bookId: book.id,
    name: '交通',
    kind: 'expense',
  );
  final salary = await catRepo.create(
    bookId: book.id,
    name: '餐饮补贴',
    kind: 'income',
  );
  final accountId = (await AccountRepository(db).listByBook(book.id)).first.id;
  final repo = TransactionRepository(db);
  final now = DateTime.now();

  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: food.id,
    type: 'expense',
    amountCents: 8888,
    occurredAt: DateTime(now.year, now.month, 5, 12).millisecondsSinceEpoch,
    note: '午餐',
  );
  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: traffic.id,
    type: 'expense',
    amountCents: 1200,
    occurredAt: DateTime(now.year, now.month - 1, 20, 9).millisecondsSinceEpoch,
    note: '打车',
  );
  await repo.create(
    bookId: book.id,
    accountId: accountId,
    categoryId: salary.id,
    type: 'income',
    amountCents: 20000,
    occurredAt: DateTime(now.year, now.month, 8, 9).millisecondsSinceEpoch,
    note: '工资',
  );
}

/// 从首页搜索图标进入搜索页。
Future<void> _openSearch(WidgetTester tester, AppDatabase db) async {
  await pumpApp(tester, database: db);
  await tester.tap(find.byTooltip('搜索'));
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byKey(_inputKey), keyword);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页搜索图标 → 搜索页：输入框 + 引导态（不列全部流水）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    expect(find.byKey(_inputKey), findsOneWidget);
    expect(find.text('输入分类、备注或金额开始搜索'), findsOneWidget);
    // 未输入时不显示任何流水、也不显示清空按钮
    expect(find.text('-88.88'), findsNothing);
    expect(find.byKey(_clearKey), findsNothing);
  });

  testWidgets('按分类名搜：命中同分类多笔，汇总笔数与收支', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '餐饮');

    expect(find.text('共 2 笔'), findsOneWidget);
    expect(find.text('-88.88'), findsOneWidget);
    expect(find.text('+200.00'), findsOneWidget);
    // 交通那笔被排除
    expect(find.text('-12.00'), findsNothing);
  });

  testWidgets('按备注搜：跨月的历史流水也能搜到', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '打车');

    expect(find.text('共 1 笔'), findsOneWidget);
    expect(find.text('-12.00'), findsOneWidget);
  });

  testWidgets('按金额搜：数字走「元.分」文本子串匹配', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    await _type(tester, '88');
    expect(find.text('-88.88'), findsOneWidget);
    expect(find.text('共 1 笔'), findsOneWidget);

    await _type(tester, '12');
    expect(find.text('-12.00'), findsOneWidget);
    expect(find.text('-88.88'), findsNothing);

    // 带千分位/金额符号也能搜
    await _type(tester, '¥200');
    expect(find.text('+200.00'), findsOneWidget);
  });

  testWidgets('一键清空：有输入才出现，点一下清空并回到引导态', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '打车');
    expect(find.byKey(_clearKey), findsOneWidget);

    await tester.tap(find.byKey(_clearKey));
    await tester.pumpAndSettle();

    final TextField field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.controller?.text, isEmpty);
    expect(find.text('输入分类、备注或金额开始搜索'), findsOneWidget);
    expect(find.byKey(_clearKey), findsNothing);
    expect(find.text('-12.00'), findsNothing);
  });

  testWidgets('没有命中：回显关键词 + 提供清空入口', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '不存在的关键词');

    expect(find.text('没有匹配「不存在的关键词」的账单'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await tester.pumpAndSettle();
    expect(find.text('输入分类、备注或金额开始搜索'), findsOneWidget);
  });

  testWidgets('长按结果可删：删完只剩空结果提示，且库里已软删', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '打车');

    await tester.longPress(find.text('-12.00'));
    await tester.pumpAndSettle();
    expect(find.text('删除这笔'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('没有匹配「打车」的账单'), findsOneWidget);

    final book = await BookRepository(db).ensureDefaultBook();
    final rows = await TransactionRepository(db).listByBook(book.id);
    expect(rows.map((t) => t.note), isNot(contains('打车')));
    expect(rows, hasLength(2));
  });
}
