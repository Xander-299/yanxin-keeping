/// 分类管理页 + 记账页选择器（schema v4：两级 / 归档 / 收支隔离）。
///
/// 仓储层的规则在 `test/data/repositories/category_repository_test.dart`，
/// 这里只钉「用户能看到什么、点了会发生什么」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

import '../../helpers/category_seed.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<void> openManage(WidgetTester tester) async {
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类管理'));
    await tester.pumpAndSettle();
  }

  testWidgets('收支 Tab 隔离：支出列餐饮，收入列工资', (WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();

    await pumpApp(tester, database: db);
    await openManage(tester);

    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('工资'), findsNothing);

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();

    expect(find.text('工资'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing);
  });

  testWidgets('归档后进「已归档」，恢复后又回到列表', (WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    final Book book = await BookRepository(db).ensureDefaultBook();
    final CategoryRepository repo = CategoryRepository(db);
    final Category custom = await repo.create(
      bookId: book.id,
      name: '宠物',
      kind: 'expense',
    );
    await repo.archive(custom.id);

    await pumpApp(tester, database: db);
    await openManage(tester);
    await tester.pumpAndSettle();

    // 已归档分区默认折叠，点开后能看到「宠物」
    await tester.scrollUntilVisible(
      find.textContaining('已归档'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('已归档'));
    await tester.pumpAndSettle();
    expect(find.text('宠物'), findsOneWidget);

    // 展开后「恢复」可能在折叠线以下 → 先滚到可见，再补一小段避免贴边点空
    await tester.scrollUntilVisible(
      find.text('恢复').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').first);
    await tester.pumpAndSettle();

    final Category fresh = (await repo.getById(custom.id))!;
    expect(fresh.isArchived, 0);
  });

  testWidgets('记账页选择器：归档分类不出现，二级分类可钻取并回填', (
    WidgetTester tester,
  ) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    final Book book = await BookRepository(db).ensureDefaultBook();
    final CategoryRepository repo = CategoryRepository(db);
    // 预置里已有「餐饮」→ 取现成的（v4 起同级不允许重名）
    final Category parent = await ensureCategory(repo, book.id, '餐饮');
    await repo.create(
      bookId: book.id,
      name: '早餐',
      kind: 'expense',
      parentId: parent.id,
    );
    final Category archived = await repo.create(
      bookId: book.id,
      name: '已停用',
      kind: 'expense',
    );
    await repo.archive(archived.id);

    await pumpApp(tester, database: db);
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('请选择分类'));
    await tester.pumpAndSettle();

    // 只列支出、且不含归档分类
    expect(find.text('已停用'), findsNothing);
    expect(find.text('工资'), findsNothing);

    // 点「餐饮」→ 进子级列表（含「餐饮（不细分）」+「早餐」）
    await tester.tap(find.text('餐饮').last);
    await tester.pumpAndSettle();
    expect(find.text('餐饮（不细分）'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);

    await tester.tap(find.text('早餐'));
    await tester.pumpAndSettle();
    expect(find.text('早餐'), findsWidgets, reason: '选完应回填到记账页');
  });
}
