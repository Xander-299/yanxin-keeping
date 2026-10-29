/// 分类弹层尺寸 + 浮动按钮（2026-10-29 任务书第四轮）。
///
/// 钉住三件事：
/// 1. 新建分类弹层占屏幕 **30%**；
/// 2. 点图标后另开 **60%** 的图标 / 颜色弹层，选完不影响外层编辑；
/// 3. 浮动按钮固定在屏幕高度 **15%** 处（滚动不移动），点按展开 `F` / `S` 两个入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

import '../../helpers/pump_app.dart';

const ValueKey<String> _editorSheetKey = ValueKey<String>(
  'category-editor-sheet',
);
const ValueKey<String> _iconSheetKey = ValueKey<String>('category-icon-sheet');

void main() {
  double screenHeight(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  Future<void> openManage(WidgetTester tester) async {
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类管理'));
    await tester.pumpAndSettle();
  }

  Future<AppDatabase> bootApp(WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();
    await pumpApp(tester, database: db);
    await openManage(tester);
    return db;
  }

  testWidgets('新建分类弹层 = 屏幕 30%；点图标另开 60% 的图标弹层', (
    WidgetTester tester,
  ) async {
    await bootApp(tester);
    final double h = screenHeight(tester);

    // 新建入口只剩浮动按钮（AppBar 的「＋」已移除）
    expect(find.byTooltip('新建分类'), findsNothing);
    await tester.tap(find.byTooltip('添加分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加一级分类'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(_editorSheetKey)).height,
      closeTo(h * 0.30, 1),
      reason: '任务书：新建分类弹层占屏幕高度 30%',
    );

    // 图标网格不在编辑层里 —— 点预览才另开一层
    await tester.tap(find.byTooltip('选择图标和颜色'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(_iconSheetKey)).height,
      closeTo(h * 0.60, 1),
      reason: '任务书：图标选择弹层占屏幕高度 60%',
    );

    // 选一个图标 → 完成 → 图标层关闭、编辑层还在（选择已即时回写预览）
    await tester.tap(
      find
          .descendant(
            of: find.byKey(_iconSheetKey),
            matching: find.byIcon(Icons.pets_rounded),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.byKey(_iconSheetKey), findsNothing);
    expect(find.byKey(_editorSheetKey), findsOneWidget);
    expect(
      tester
          .widget<Icon>(find.byKey(const ValueKey('category-icon-preview')))
          .icon,
      Icons.pets_rounded,
      reason: '选中的图标要回写到编辑层的预览块',
    );
  });

  testWidgets('浮动按钮：固定在右下角 15%、滚动不动，点按向上展开 F / S 入口', (
    WidgetTester tester,
  ) async {
    await bootApp(tester);
    final double h = screenHeight(tester);

    final Finder fab = find.byTooltip('添加分类');
    expect(fab, findsOneWidget);
    expect(
      tester.getRect(fab).center.dy,
      closeTo(h * 0.85, 1),
      reason: '任务书：右下角，距屏幕底部 15%（圆心 = 屏高 85% 处）',
    );
    expect(
      tester.getRect(fab).center.dx,
      greaterThan(800 * 0.75),
      reason: '靠右',
    );

    // trigger = click：先收起，点一下才展开
    expect(find.text('添加一级分类'), findsNothing);
    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.text('添加一级分类'), findsOneWidget);
    expect(find.text('添加二级分类'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);

    // 子项在按钮**上方**（贴底展开必须向上，否则掉出屏幕）
    final double fabTop = tester.getRect(fab).top;
    expect(tester.getRect(find.text('添加二级分类')).bottom, lessThan(fabTop));

    // 列表滚动时浮动按钮位置不变（不可移动）
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(tester.getRect(fab).center.dy, closeTo(h * 0.85, 1));

    // 一级入口 → 直接进新建弹层
    await tester.tap(find.text('添加一级分类'));
    await tester.pumpAndSettle();
    expect(find.byKey(_editorSheetKey), findsOneWidget);
    expect(find.text('分类名称'), findsOneWidget);
  });

  testWidgets('浮动按钮 S：先选一级分类，新建出来的确实挂在它下面', (
    WidgetTester tester,
  ) async {
    final AppDatabase db = await bootApp(tester);
    final Book book = (await BookRepository(db).listAll()).first;

    await tester.tap(find.byTooltip('添加分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加二级分类'));
    await tester.pumpAndSettle();

    expect(find.text('挂到哪个一级分类下？'), findsOneWidget);
    await tester.tap(find.text('餐饮').last);
    await tester.pumpAndSettle();

    expect(find.byKey(_editorSheetKey), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '美式');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    // 写库是真实异步：等弹层自己关掉再查库（pumpAndSettle 会早退）
    for (var i = 0;
        i < 40 && find.byKey(_editorSheetKey).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    final List<Category> cats = await CategoryRepository(
      db,
    ).listByBook(book.id, kind: 'expense');
    final Category created = cats.firstWhere((Category c) => c.name == '美式');
    final Category parent = cats.firstWhere((Category c) => c.name == '餐饮');
    expect(created.parentId, parent.id);
  });
}
