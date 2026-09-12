/// 搜索浮层 widget 测试：入口（覆盖首页）、三类命中、类型筛选 chips、
/// 结果汇总、一键清空、无结果、关闭、删除链路。
///
/// ⚠️ 断言必须限定在**浮层内**（[_inOverlay]）：浮层是透明度 false 的 dialog，
/// 首页留在下面仍参与 widget 树 —— 首页本月账单里也有 `-88.88` 这类文本，
/// 直接 `find.text` 会同时命中两份（原独立路由是 opaque，首页被 Offstage 屏蔽才没这问题）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/ledger/presentation/home_page.dart';
import 'package:yanxin/features/search/presentation/search_overlay.dart';

import '../../helpers/pump_app.dart';

const Key _inputKey = ValueKey<String>('search-input');
const Key _clearKey = ValueKey<String>('search-clear');
const Key _closeKey = ValueKey<String>('search-close');

Key _chipKey(String word) => ValueKey<String>('search-chip-$word');

/// 只在浮层子树里找文本，避开首页那份同名文本。
Finder _inOverlay(Finder matching) =>
    find.descendant(of: find.byType(SearchOverlay), matching: matching);

/// 造三笔跨月数据：
/// - 餐饮 88.88 / 备注「午餐」（当月 5 日，支出）
/// - 交通 12.00 / 备注「打车」（上月 20 日，支出）
/// - 餐饮补贴 200.00 / 备注「工资」（当月 8 日，收入）
///
/// 收入那笔特意用「餐饮补贴」：搜「餐饮」能一次命中支出 + 收入两笔，
/// 顺便验证「分类名命中」的并集与汇总行的收支合计。
/// 支出 2 笔 / 收入 1 笔也正好用来验证「仅支出 / 仅收入」的类型筛选。
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

/// 从首页搜索图标打开搜索浮层（F7.5 起是 dialog，不再是路由跳转）。
Future<void> _openSearch(WidgetTester tester, AppDatabase db) async {
  await pumpApp(tester, database: db);
  await tester.tap(find.byTooltip('搜索'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byKey(_inputKey), keyword);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页搜索图标 → 覆盖式浮层：输入框 + 引导态（不列全部流水）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    expect(find.byKey(_inputKey), findsOneWidget);
    expect(_inOverlay(find.text('输入分类、备注或金额开始搜索')), findsOneWidget);
    // 未输入时浮层里不出现任何流水、也不显示清空按钮
    expect(_inOverlay(find.text('-88.88')), findsNothing);
    expect(find.byKey(_clearKey), findsNothing);
  });

  testWidgets('浮层覆盖而非跳页：首页仍在树里（毛玻璃下方可辨）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    // DialogRoute 不透明度为 false → 下层路由不会被 Offstage，首页仍在
    expect(find.byType(HomePage), findsOneWidget);
    // 同时浮层也在
    expect(find.byKey(_inputKey), findsOneWidget);
  });

  testWidgets('提示块含三个类型筛选 chips', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    expect(find.byKey(_chipKey('仅支出')), findsOneWidget);
    expect(find.byKey(_chipKey('仅收入')), findsOneWidget);
    expect(find.byKey(_chipKey('转账')), findsOneWidget);
  });

  testWidgets('按分类名搜：命中同分类多笔，汇总笔数与收支', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '餐饮');

    expect(_inOverlay(find.text('共 2 笔')), findsOneWidget);
    expect(_inOverlay(find.text('-88.88')), findsOneWidget);
    expect(_inOverlay(find.text('+200.00')), findsOneWidget);
    // 交通那笔被排除
    expect(_inOverlay(find.text('-12.00')), findsNothing);
  });

  testWidgets('按备注搜：跨月的历史流水也能搜到', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '打车');

    expect(_inOverlay(find.text('共 1 笔')), findsOneWidget);
    expect(_inOverlay(find.text('-12.00')), findsOneWidget);
  });

  testWidgets('按金额搜：数字走「元.分」文本子串匹配', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    await _type(tester, '88');
    expect(_inOverlay(find.text('-88.88')), findsOneWidget);
    expect(_inOverlay(find.text('共 1 笔')), findsOneWidget);

    await _type(tester, '12');
    expect(_inOverlay(find.text('-12.00')), findsOneWidget);
    expect(_inOverlay(find.text('-88.88')), findsNothing);

    // 带千分位/金额符号也能搜
    await _type(tester, '¥200');
    expect(_inOverlay(find.text('+200.00')), findsOneWidget);
  });

  testWidgets('点「仅支出」：词填进输入框、chip 高亮，结果是全部支出', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await tester.tap(find.byKey(_chipKey('仅支出')));
    await tester.pumpAndSettle();

    // 词真的进了输入框（可见、可编辑、可一键清空）；
    // 末尾带一个空格 —— 用户接着敲关键词才会被空格分隔开，保持类型指令有效
    final TextField field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.controller?.text, '仅支出 ');
    // chip 高亮由输入框内容推导
    expect(
      tester.widget<ChoiceChip>(find.byKey(_chipKey('仅支出'))).selected,
      isTrue,
    );

    // 2 笔支出都在，收入那笔被排除
    expect(_inOverlay(find.text('共 2 笔')), findsOneWidget);
    expect(_inOverlay(find.text('-88.88')), findsOneWidget);
    expect(_inOverlay(find.text('-12.00')), findsOneWidget);
    expect(_inOverlay(find.text('+200.00')), findsNothing);
  });

  testWidgets('点「仅收入」：结果只剩收入；「转账」无数据 → 无结果态', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);

    await tester.tap(find.byKey(_chipKey('仅收入')));
    await tester.pumpAndSettle();
    expect(_inOverlay(find.text('共 1 笔')), findsOneWidget);
    expect(_inOverlay(find.text('+200.00')), findsOneWidget);
    expect(_inOverlay(find.text('-88.88')), findsNothing);

    // 切到转账：App 记不了转账，现有数据为空 → 无结果态
    await tester.tap(find.byKey(_chipKey('转账')));
    await tester.pumpAndSettle();
    expect(_inOverlay(find.text('没有匹配「转账」的账单')), findsOneWidget);
  });

  testWidgets('再点同一个 chip = 取消筛选，回到引导态', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await tester.tap(find.byKey(_chipKey('仅支出')));
    await tester.pumpAndSettle();
    expect(_inOverlay(find.text('共 2 笔')), findsOneWidget);

    await tester.tap(find.byKey(_chipKey('仅支出')));
    await tester.pumpAndSettle();

    final TextField field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.controller?.text, isEmpty);
    expect(_inOverlay(find.text('输入分类、备注或金额开始搜索')), findsOneWidget);
  });

  testWidgets('类型筛选 + 关键词 = 交集', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await tester.tap(find.byKey(_chipKey('仅支出')));
    await tester.pumpAndSettle();
    await _type(tester, '仅支出 打车');

    expect(_inOverlay(find.text('共 1 笔')), findsOneWidget);
    expect(_inOverlay(find.text('-12.00')), findsOneWidget);
    expect(_inOverlay(find.text('-88.88')), findsNothing);
  });

  testWidgets('点 chip 后直接接着敲字（不额外打空格）→ 交集照样生效', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await tester.tap(find.byKey(_chipKey('仅支出')));
    await tester.pumpAndSettle();

    // 模拟真实操作：点完 chip 直接在后面敲「12」（chip 已留好尾随空格）
    final TextField field = tester.widget<TextField>(find.byKey(_inputKey));
    await _type(tester, '${field.controller!.text}12');

    expect(_inOverlay(find.text('共 1 笔')), findsOneWidget);
    expect(_inOverlay(find.text('-12.00')), findsOneWidget);
    expect(_inOverlay(find.text('-88.88')), findsNothing);
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
    expect(_inOverlay(find.text('输入分类、备注或金额开始搜索')), findsOneWidget);
    expect(find.byKey(_clearKey), findsNothing);
    expect(_inOverlay(find.text('-12.00')), findsNothing);
  });

  testWidgets('没有命中：回显关键词 + 提供清空入口', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '不存在的关键词');

    expect(_inOverlay(find.text('没有匹配「不存在的关键词」的账单')), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await tester.pumpAndSettle();
    expect(_inOverlay(find.text('输入分类、备注或金额开始搜索')), findsOneWidget);
  });

  testWidgets('点关闭按钮 → 浮层收起，回首页（数据无变化）', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '餐饮');
    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_inputKey), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('点提示块以下的玻璃空白区 → 浮层收起', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    // 无结果态：提示块只占顶部约 1/5 屏，下方是纯玻璃，可穿透点击
    await _type(tester, '不存在的关键词');
    expect(find.byKey(_inputKey), findsOneWidget);

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, size.height * 0.75));
    await tester.pumpAndSettle();

    expect(find.byKey(_inputKey), findsNothing);
  });

  testWidgets('引导态下点提示块以外的空白区也能关闭（不能被 Scrollable 挡住）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    expect(_inOverlay(find.text('输入分类、备注或金额开始搜索')), findsOneWidget);

    // 真机曾在此挂掉：引导态原本用 SingleChildScrollView，Scrollable 以 opaque
    // 命中整块下方区域 → 点空白无反应。改成 Align 后空白可穿透。
    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, size.height * 0.75));
    await tester.pumpAndSettle();

    expect(find.byKey(_inputKey), findsNothing);
  });

  testWidgets('长按结果可删：删完只剩空结果提示，且库里已软删', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await _seed(db);

    await _openSearch(tester, db);
    await _type(tester, '打车');

    await tester.longPress(_inOverlay(find.text('-12.00')));
    await tester.pumpAndSettle();
    expect(find.text('删除这笔'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(_inOverlay(find.text('没有匹配「打车」的账单')), findsOneWidget);

    final book = await BookRepository(db).ensureDefaultBook();
    final rows = await TransactionRepository(db).listByBook(book.id);
    expect(rows.map((t) => t.note), isNot(contains('打车')));
    expect(rows, hasLength(2));
  });
}
