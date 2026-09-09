// F4 冒烟 + M1 等价关键路径（UI 层）。
//
// 冷启动/持久化/账本隔离等 DB 层语义已在 test/core/db、test/data/repositories 覆盖；
// 这里验证「点得动」：记一笔 → 列表出现 → 编辑 → 长按删除。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import 'helpers/pump_app.dart';

/// 等 DB 写库 + invalidate 触发的重建到位（写库是真实异步，pumpAndSettle 可能抢先返回）。
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('冷启动进入首页并自动建默认账本', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('默认账本'), findsOneWidget);
    expect(find.textContaining('还没有记账'), findsOneWidget);
  });

  testWidgets('记一笔支出 → 首页出现该笔且金额为负', (WidgetTester tester) async {
    final db = openTestDatabase();
    // 预建账本，拿到 categoryId
    final book = await BookRepository(db).ensureDefaultBook();
    final cat = (await CategoryRepository(db).listByBook(book.id, kind: 'expense')).first;
    addTearDown(db.close);

    await pumpApp(tester, database: db);

    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();

    // 输金额 12
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    // 选分类
    await tester.tap(find.text('请选择分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cat.name).last);
    await tester.pumpAndSettle();
    // 保存（内容可能超出测试视口，先滚到可见）
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // 回到首页：hero 结余 -12.00、支出 12.00，列表出现 -12.00
    expect(find.text('-12.00'), findsNWidgets(2)); // hero 结余 + 列表金额
    expect(find.text('12.00'), findsOneWidget); // hero 支出
  });

  testWidgets('长按删除 → 列表消失回到空态', (WidgetTester tester) async {
    final db = openTestDatabase();
    final book = await BookRepository(db).ensureDefaultBook();
    final cat = (await CategoryRepository(db).listByBook(book.id, kind: 'expense')).first;
    addTearDown(db.close);

    await pumpApp(tester, database: db);

    // 通过 UI 记一笔
    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.tap(find.text('请选择分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(cat.name).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('-1.00'), findsNWidgets(2)); // hero 结余 + 列表金额

    // 长按删除（长按列表里的分类名，避开 hero 上的同文本金额）
    await tester.longPress(find.text(cat.name));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有记账'), findsOneWidget);
  });

  testWidgets('hero 翻月：上月有账则能看到上月流水', (WidgetTester tester) async {
    final db = openTestDatabase();
    final bookRepo = BookRepository(db);
    final catRepo = CategoryRepository(db);
    final book = await bookRepo.ensureDefaultBook();
    final cat = (await catRepo.listByBook(book.id, kind: 'expense')).first;
    final now = DateTime.now();
    final prevMonth = DateTime(now.year, now.month - 1, 15);
    await TransactionRepository(db).create(
      bookId: book.id,
      accountId: (await AccountRepository(db).listByBook(book.id)).first.id,
      categoryId: cat.id,
      type: 'expense',
      amountCents: 2500,
      occurredAt: prevMonth.millisecondsSinceEpoch,
    );
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    expect(find.textContaining('还没有记账'), findsOneWidget);

    await tester.tap(find.text('‹'));
    await tester.pumpAndSettle();
    expect(find.text('-25.00'), findsNWidgets(2)); // hero 结余 + 列表金额
  });

  testWidgets('分类管理：新建自定义分类并出现在列表', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.category_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '打车');
    await tester.tap(find.text('确定'));
    await pumpUntil(tester, find.text('打车'));

    expect(find.text('打车'), findsOneWidget);
  });

  testWidgets('新建账本并切换，首页随切刷新', (WidgetTester tester) async {
    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    await pumpApp(tester, database: db);

    // 新建账本 B（创建即切换）
    await tester.tap(find.byIcon(Icons.import_contacts_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建账本'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'B账本');
    await tester.tap(find.text('确定'));
    await pumpUntil(tester, find.text('B账本'));

    // 回到首页，标题已是新账本
    expect(find.text('B账本'), findsOneWidget);
  });
}
