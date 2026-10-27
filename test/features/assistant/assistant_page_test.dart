/// 「问账本」页的 widget 测试：点示例问题 / 自己打字 → 出答案卡。
///
/// 视口调到 360×800 逻辑像素（真机竖屏尺度）：800×600 的默认视口太矮，
/// 答案卡会被挤出可视区，`find.text` 就找不到（见 HANDOFF「最容易踩的坑」）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/palette.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/data/providers/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/assistant/presentation/assistant_page.dart';

import '../../helpers/test_database.dart';

/// 等真实异步查库 + UI 重建到位（`pumpAndSettle` 会在查库完成前返回）。
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 80,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

Future<AppDatabase> _seed() async {
  final AppDatabase db = openTestDatabase();
  final Book book = await BookRepository(db).ensureDefaultBook();
  final Category food = await CategoryRepository(
    db,
  ).create(bookId: book.id, name: '餐饮', kind: 'expense');
  final Account acc = await AccountRepository(db).create(bookId: book.id, name: '现金');
  await TransactionRepository(db).create(
    bookId: book.id,
    accountId: acc.id,
    type: 'expense',
    amountCents: 120000, // ¥1,200.00
    occurredAt: DateTime.now().millisecondsSinceEpoch,
    categoryId: food.id,
    note: '午饭',
  );
  return db;
}

Future<void> _pumpPage(WidgetTester tester, AppDatabase db, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: theme, home: const AssistantPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空态有示例问题；点一条 → 出答案卡且金额来自账本', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pumpPage(tester, db);

    expect(find.text('一句话问自己的账本'), findsOneWidget);
    expect(find.text('这个月花了多少'), findsOneWidget);

    await tester.tap(find.text('这个月花了多少'));
    await pumpUntil(tester, find.textContaining('¥1,200.00'));

    expect(find.textContaining('¥1,200.00'), findsWidgets);
    // 问题气泡还在（会话是追加式的），标题里带区间
    final DateTime now = DateTime.now();
    expect(find.text('这个月花了多少'), findsOneWidget);
    expect(find.textContaining('${now.year}年${now.month}月'), findsWidgets);
  });

  testWidgets('自己打字问不认识的问题 → 明说不会，并给示例', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pumpPage(tester, db);

    await tester.enterText(find.byType(TextField), '帮我写一首诗');
    await tester.tap(find.text('问'));
    await pumpUntil(tester, find.text('这个我还没学会'));

    expect(find.text('这个我还没学会'), findsOneWidget);
    expect(find.textContaining('只能答「账本里的数」'), findsOneWidget);
  });

  testWidgets('清空按钮把会话清掉', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pumpPage(tester, db);

    await tester.tap(find.text('这个月花了多少'));
    await pumpUntil(tester, find.textContaining('¥1,200.00'));

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.text('一句话问自己的账本'), findsOneWidget);
  });

  // 深色主题下也要能渲染并出答案（颜色一律走 context.toon 实例字段；
  // 写死颜色会在深色下变成看不见 —— 这条测试就是防这个）
  testWidgets('深色主题：空态与答案卡都能渲染', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pumpPage(
      tester,
      db,
      theme: buildToonTheme(ToonPalette.dark, Brightness.dark),
    );

    expect(find.text('一句话问自己的账本'), findsOneWidget);
    await tester.tap(find.text('这个月花了多少'));
    await pumpUntil(tester, find.textContaining('¥1,200.00'));
    expect(find.textContaining('¥1,200.00'), findsWidgets);
  });
}
