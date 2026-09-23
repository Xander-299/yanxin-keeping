/// 资产页关键路径（UI 层）：新增账户 → 列表/净资产更新；有流水的账户删不掉。
///
/// 真机（MuMu 12）已实走验收，见 `docs/acceptance-F7.5b-assets.md`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/pump_app.dart';

/// 等 DB 写库 + provider 重建到位（写库是真实异步，pumpAndSettle 可能抢先返回）。
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

/// 切到底栏「资产」tab（钱包图标在底栏唯一；空态图标只在无账户时出现）。
Future<void> goAssetsTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_balance_wallet_rounded));
  await pumpUntil(tester, find.text('净资产'));
}

void main() {
  testWidgets('新增账户 → 出现在列表且净资产同步', (WidgetTester tester) async {
    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    await goAssetsTab(tester);

    // 默认账本自带「现金」，初始 0
    expect(find.text('现金'), findsOneWidget);
    expect(find.text('¥ 0.00'), findsOneWidget);

    await tester.tap(find.byTooltip('新增账户'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '招行储蓄卡');
    await tester.enterText(find.byType(TextField).at(1), '100');
    await tester.pumpAndSettle();
    // 测试视口 800×600 偏小，按钮可能在折线下 → 先滚到可见
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    // 等 sheet 收起（SnackBar 出现即表示已 pop）
    await pumpUntil(tester, find.text('已新增「招行储蓄卡」'));
    await tester.pumpAndSettle();

    // 列表多一行，净资产 0 → 100
    expect(find.text('招行储蓄卡'), findsOneWidget);
    expect(find.text('¥ 100.00'), findsOneWidget);
    expect(find.text('2 个账户 · 全时间累计'), findsOneWidget);
  });

  testWidgets('有流水的账户删不掉（提示先改流水账户）', (WidgetTester tester) async {
    final db = openTestDatabase();
    final book = await BookRepository(db).ensureDefaultBook();
    final cat = (await CategoryRepository(db).listByBook(book.id, kind: 'expense'))
        .first;
    final cash = (await AccountRepository(db).listByBook(book.id)).first;
    await TransactionRepository(db).create(
      bookId: book.id,
      accountId: cash.id,
      type: 'expense',
      amountCents: 1000,
      occurredAt: DateTime(2026, 9, 10, 12).millisecondsSinceEpoch,
      categoryId: cat.id,
    );
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    await goAssetsTab(tester);

    // 支出 10 元 → 现金余额 -10.00
    expect(find.text('-10.00'), findsOneWidget);

    await tester.tap(find.text('现金'));
    // 先让 sheet 的滑入动画跑完再找按钮（动画途中按错的视口算滚动会把按钮顶出屏幕）
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('编辑账户'));
    // C 批加了图标/颜色两块，表单变高 → 删除按钮可能折到屏外，先滚到可见
    await tester.ensureVisible(find.text('删除账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await pumpUntil(tester, find.text('删不了这个账户'));

    expect(find.textContaining('还有 1 笔流水'), findsOneWidget);
    // 账户没被删（弹窗只是提示，sheet 仍开着）
    await tester.tap(find.text('知道了'));
    await pumpUntil(tester, find.text('编辑账户'));
    expect(find.text('现金'), findsWidgets);
  });

  testWidgets('无流水的账户可删除', (WidgetTester tester) async {
    final db = openTestDatabase();
    final book = await BookRepository(db).ensureDefaultBook();
    await AccountRepository(db).create(bookId: book.id, name: '支付宝', type: 'alipay');
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    await goAssetsTab(tester);
    expect(find.text('支付宝'), findsOneWidget);

    await tester.tap(find.text('支付宝'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('编辑账户'));
    // C 批加了图标/颜色两块，表单变高 → 删除按钮可能折到屏外，先滚到可见
    await tester.ensureVisible(find.text('删除账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账户'));
    await pumpUntil(tester, find.text('删除账户「支付宝」后不再计入净资产，确定删除？'));
    await tester.tap(find.text('删除'));

    // 删除后列表里不再有它（bump 数据版本号 → 资产页重算）
    for (var i = 0; i < 20 && find.text('支付宝').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('支付宝'), findsNothing);
  });

  testWidgets('金额格式非法时拦截保存，且不丢已填内容', (WidgetTester tester) async {
    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    await goAssetsTab(tester);

    await tester.tap(find.byTooltip('新增账户'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'TestBank');
    // 三位小数：yuanToCents 的正则不放行
    await tester.enterText(find.byType(TextField).at(1), '12.345');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await pumpUntil(tester, find.text('初始余额格式不对，最多两位小数'));

    // 弹窗没关、已填的名称与金额都还在（状态保留）
    expect(find.text('新增账户'), findsOneWidget);
    expect(find.text('TestBank'), findsWidgets);
    expect(find.text('12.345'), findsWidgets);
  });

  testWidgets('为空名称拦截保存', (WidgetTester tester) async {
    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    await goAssetsTab(tester);

    await tester.tap(find.byTooltip('新增账户'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await pumpUntil(tester, find.text('请输入账户名称'));

    expect(find.text('新增账户'), findsOneWidget);
    // 没建出账户：仍然只有默认的「现金」
    expect(find.text('1 个账户 · 全时间累计'), findsOneWidget);
  });

  testWidgets('点编辑弹窗外（遮罩）关闭弹窗，账户不变', (WidgetTester tester) async {
    // ⚠️ 必须用手机竖屏视口。默认 800×600 又宽又矮，而账户表单是**底部弹窗**：
    //    C 批加了「图标 + 颜色」两块后，弹窗内容高 ≈ 580+ ≈ 整个视口高 →
    //    弹窗顶边贴到 y=0，遮罩一条缝都不剩，点哪都在弹窗里（点不关，不是 bug）。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0; // → 逻辑视口 540×1200
    addTearDown(tester.view.reset);

    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    await pumpApp(tester, database: db);
    await goAssetsTab(tester);

    await tester.tap(find.text('现金'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('编辑账户'));
    // 弹窗确实开出来了（pumpUntil 找不到不会失败，这里补一道硬断言）
    expect(find.text('编辑账户'), findsOneWidget);

    // 遮罩在弹窗上方，点它应关闭弹窗（真机同样行为，不是 bug）
    final Rect sheet = tester.getRect(find.byType(BottomSheet));
    expect(
      sheet.top,
      greaterThan(100),
      reason: '遮罩区过小：弹窗顶边 y=${sheet.top}、弹窗高 ${sheet.height}（视口 1200 高）',
    );
    await tester.tapAt(Offset(sheet.center.dx, sheet.top / 2));
    await tester.pumpAndSettle();
    expect(find.text('编辑账户'), findsNothing);
    expect(find.text('现金'), findsWidgets);
  });
}
