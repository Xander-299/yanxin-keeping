/// 导入页 widget 测试：注入文件字节走完整流程（预览 → 取消单条 → 确认 → 落库）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/import/application/bill_importer.dart';
import 'package:yanxin/features/import/data/bill_normalize.dart';
import 'package:yanxin/features/import/data/bill_profiles.dart';
import 'package:yanxin/features/import/presentation/import_page.dart';

import '../../helpers/test_database.dart';

/// 等真实异步写库 + UI 重建到位（pumpAndSettle 会在写库完成前返回）。
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('导入流程：解析预览 → 单条取消 → 确认导入 → 流水落库',
      (WidgetTester tester) async {
    final db = openTestDatabase();
    final book = await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    // 微信样式 CSV：2 条有效支出
    const csv = '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\n'
        '2026-08-01 12:00:00,x,美团平台商户,外卖订单,支出,¥12.30,零钱,支付成功,IMP1,M1,/\n'
        '2026-08-02 13:30:00,x,滴滴出行,快车,支出,¥8.00,零钱,支付成功,IMP2,M2,/';
    final bytes = utf8.encode(csv);

    final router = GoRouter(
      initialLocation: '/import',
      routes: <RouteBase>[
        GoRoute(
          path: '/import',
          builder: (_, _) =>
              ImportPage(pickBytesOverride: () async => bytes),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 选文件 → 解析预览
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('识别为「微信支付」账单'), findsOneWidget);
    expect(find.textContaining('美团平台商户'), findsOneWidget);
    expect(find.textContaining('滴滴出行'), findsOneWidget);
    expect(find.text('确认导入（2 笔）'), findsOneWidget);

    // 取消第一条（美团），只导入滴滴
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('确认导入（1 笔）'), findsOneWidget);

    // 确认导入 → 报告对话框（importRows 走 drift 事务，真实异步）
    await tester.tap(find.text('确认导入（1 笔）'));
    await pumpUntil(tester, find.text('导入完成'));
    expect(find.text('导入完成'), findsOneWidget);
    expect(find.textContaining('成功导入 1 笔'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    // 落库校验：仅 1 笔，备注/分类正确
    final txs =
        await TransactionRepository(db).listByMonth(book.id, 2026, 8);
    expect(txs, hasLength(1));
    expect(txs.first.note, '滴滴出行 · 快车');
    expect(txs.first.amountCents, 800);
    expect(txs.first.source, 'wechat_csv');
  });

  // 回归：首次使用验收 P1 —— 导入的账单属于历史月份，首页停在当前月会
  // 「看起来什么都没发生」。报告必须给出数据所在月份 + 直达入口。
  testWidgets('导入完成报告给出数据月份，点「去看账单」跳到首页该月',
      (WidgetTester tester) async {
    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    // 8 月的账单，而「当前月」是测试运行当月 → 不跳转就看不到
    const csv = '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\n'
        '2026-08-01 12:00:00,x,美团平台商户,外卖订单,支出,¥12.30,零钱,支付成功,IMPA,MA,/';
    final bytes = utf8.encode(csv);

    final router = GoRouter(
      initialLocation: '/import',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('LEDGER_HOME')),
        ),
        GoRoute(
          path: '/import',
          builder: (_, _) => ImportPage(pickBytesOverride: () async => bytes),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入（1 笔）'));
    await pumpUntil(tester, find.text('导入完成'));

    // 报告里必须说明数据落在哪个月
    expect(find.text('去看账单'), findsOneWidget);
    expect(find.textContaining('其中 1 笔属于 2026-08'), findsOneWidget);

    // 点「去看账单」→ 跳首页
    await tester.tap(find.text('去看账单'));
    await tester.pumpAndSettle();
    expect(find.text('LEDGER_HOME'), findsOneWidget);
  });

  // 回归：首次使用验收 P6 —— 预览页看不出「点条目 = 取消该条」。
  testWidgets('预览页给出勾选说明，且「全不选」把可导入数归零', (WidgetTester tester) async {
    final db = openTestDatabase();
    await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    const csv = '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\n'
        '2026-08-01 12:00:00,x,美团平台商户,外卖订单,支出,¥12.30,零钱,支付成功,IMPX,MX,/\n'
        '2026-08-02 13:30:00,x,滴滴出行,快车,支出,¥8.00,零钱,支付成功,IMPY,MY,/';
    final bytes = utf8.encode(csv);

    final router = GoRouter(
      initialLocation: '/import',
      routes: <RouteBase>[
        GoRoute(
          path: '/import',
          builder: (_, _) => ImportPage(pickBytesOverride: () async => bytes),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();

    // 说明文案让用户知道「点条目可取消」
    expect(find.text('勾选的条目会导入，点条目可取消它'), findsOneWidget);
    expect(find.text('确认导入（2 笔）'), findsOneWidget);

    // 「全不选」→ 全部取消，可导入归零且按钮禁用
    await tester.tap(find.text('全不选'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入（0 笔）'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);

    // 「全选」恢复
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入（2 笔）'), findsOneWidget);
  });

  // 回归：首次使用验收 P3 —— 二次导入报告不得出现「导入完成 / 0 笔」矛盾。
  testWidgets('二次导入同一文件 → 报告标题「没有新增」且不显示未匹配分类',
      (WidgetTester tester) async {
    final db = openTestDatabase();
    final book = await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    // 两笔都命中不了分类规则，用来验证「未匹配分类」的显示条件
    const csv = '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\n'
        '2026-08-01 12:00:00,x,无关键词甲,神秘甲,支出,¥12.30,零钱,支付成功,RPTA,RA,/\n'
        '2026-08-02 13:30:00,x,无关键词乙,神秘乙,支出,¥8.00,零钱,支付成功,RPTB,RB,/';
    final bytes = utf8.encode(csv);

    // 先直接入库一次，模拟「这个文件之前导入过」（此时库内 2 笔未匹配分类）
    final accountId = await ensureImportAccount(AccountRepository(db), book.id);
    final maps = await buildCategoryMaps(CategoryRepository(db), book.id);
    final seeded = parseBillCsv(wechatProfile, csv);
    await importRows(
      db,
      bookId: book.id,
      accountId: accountId,
      categoryMaps: maps,
      rows: seeded.rows,
    );

    final router = GoRouter(
      initialLocation: '/import',
      routes: <RouteBase>[
        GoRoute(
          path: '/import',
          builder: (_, _) => ImportPage(pickBytesOverride: () async => bytes),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 走一次完整导入 → 必然全部重复
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入（2 笔）'));
    await pumpUntil(tester, find.text('没有新增'));

    expect(find.text('没有新增'), findsOneWidget);
    expect(find.textContaining('之前已经导入过了'), findsOneWidget);
    expect(find.textContaining('成功导入 0 笔'), findsNothing);
    // 零新增时不得出现「未匹配分类」（与「没有新增」矛盾）
    expect(find.textContaining('未匹配分类'), findsNothing);
  });
}
