/// 导入页 widget 测试：注入文件字节走完整流程（预览 → 取消单条 → 确认 → 落库）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
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

    await tester.tap(find.text('好的'));
    await tester.pumpAndSettle();

    // 落库校验：仅 1 笔，备注/分类正确
    final txs =
        await TransactionRepository(db).listByMonth(book.id, 2026, 8);
    expect(txs, hasLength(1));
    expect(txs.first.note, '滴滴出行 · 快车');
    expect(txs.first.amountCents, 800);
    expect(txs.first.source, 'wechat_csv');
  });
}
