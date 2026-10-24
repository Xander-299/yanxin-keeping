/// 截图记账页 widget 测试（F8.1）：假 OCR 引擎 + 内存库，走完整流程。
///
/// 覆盖：识别 → 核对（多金额可切换）→ 确认 → 落库；重复确认不重复记账；
/// 支付失败的截图**不允许**保存。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/providers/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/receipt/data/mlkit_ocr_engine.dart';
import 'package:yanxin/features/receipt/data/ocr_engine.dart';
import 'package:yanxin/features/receipt/presentation/receipt_page.dart';

import '../../helpers/test_database.dart';

/// 假引擎：把预设文本当成 OCR 结果返回（不碰平台通道）。
class _FakeOcrEngine implements OcrEngine {
  _FakeOcrEngine(this.lines);

  final List<String> lines;
  int calls = 0;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    calls++;
    return OcrResult(
      lines: <OcrLine>[for (final String l in lines) OcrLine(text: l)],
      text: lines.join('\n'),
      elapsedMs: 12,
    );
  }

  @override
  Future<void> dispose() async {}
}

/// 等真实异步写库 + UI 重建到位（`pumpAndSettle` 会在写库完成前返回）。
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

Future<void> pumpReceiptPage(
  WidgetTester tester, {
  required AppDatabase db,
  required OcrEngine engine,
  String? imagePath,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/receipt',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('首页占位')),
      ),
      GoRoute(
        path: '/receipt',
        builder: (_, _) => ReceiptPage(
          pickImageOverride: () async => imagePath ?? '/tmp/not-exists.png',
          nowMsOverride: DateTime(2026, 10, 24, 3, 0).millisecondsSinceEpoch,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ocrEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 微信支付凭证（一个高可信金额）。
const List<String> _wechatLines = <String>[
  '微信支付',
  '支付成功',
  '商户全称：星巴克咖啡',
  '支付金额 ¥36.00',
  '支付时间 2026-10-23 14:05:33',
];

/// 原价 / 优惠 / 实付（三个金额，需要用户挑）。
const List<String> _multiAmountLines = <String>[
  '支付宝',
  '支付成功',
  '订单金额 ¥13.00',
  '优惠 ¥1.00',
  '实付 ¥12.00',
  '支付时间 2026-10-23 12:00',
];

void main() {
  testWidgets('识别 → 核对 → 确认 → 写库；再次确认不重复记账', (WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    final Book book = await BookRepository(db).ensureDefaultBook();
    final _FakeOcrEngine engine = _FakeOcrEngine(_wechatLines);

    await pumpReceiptPage(tester, db: db, engine: engine);

    // 第 1 步
    expect(find.text('从相册选一张'), findsOneWidget);

    await tester.tap(find.text('从相册选一张'));
    await pumpUntil(tester, find.text('确认记账'));
    expect(engine.calls, 1);

    // 第 2 步：字段来自识别结果
    expect(find.text('微信支付'), findsOneWidget);
    expect(find.text('36.00'), findsOneWidget);
    expect(find.text('星巴克咖啡'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('2026-10-23 14:05'), findsOneWidget);
    expect(find.text('交易成功'), findsOneWidget);

    // 确认 → 第 3 步
    await tester.tap(find.text('确认记账'));
    await pumpUntil(tester, find.text('已记账'));
    expect(find.text('已记账'), findsOneWidget);

    final List<TxRow> rows = await TransactionRepository(
      db,
    ).listByBook(book.id);
    expect(rows.length, 1);
    expect(rows.single.amountCents, 3600);
    expect(rows.single.source, 'screenshot');
    expect(rows.single.note, '星巴克咖啡');

    // 再识别同一张 → 指纹命中，不重复记账
    await tester.tap(find.text('再识别一张'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选一张'));
    await pumpUntil(tester, find.text('确认记账'));
    await tester.tap(find.text('确认记账'));
    await pumpUntil(tester, find.text('这笔之前已经记过了'));
    expect(find.text('这笔之前已经记过了'), findsOneWidget);
    expect((await TransactionRepository(db).listByBook(book.id)).length, 1);
  });

  testWidgets('多个金额：默认取实付，点候选可切换', (WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();

    await pumpReceiptPage(
      tester,
      db: db,
      engine: _FakeOcrEngine(_multiAmountLines),
    );
    await tester.tap(find.text('从相册选一张'));
    await pumpUntil(tester, find.text('确认记账'));

    // 主金额 = 实付 12.00
    expect(find.text('12.00'), findsOneWidget);
    // 两个候选都在（12.00 是当前值也出现在候选里 → 用它定位 chip 行）
    expect(find.text('识别到多个金额，点一下换成你要记的那个'), findsOneWidget);
    expect(find.text('¥13.00'), findsOneWidget);

    // 切到原价 13.00（候选行在金额键盘下方，800×600 视口里要先滚进可视区）
    await tester.ensureVisible(find.text('¥13.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('¥13.00'));
    await tester.pumpAndSettle();
    expect(find.text('13.00'), findsOneWidget);
  });

  testWidgets('支付失败的截图：按钮禁用、给出原因、绝不写库', (WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    final Book book = await BookRepository(db).ensureDefaultBook();

    await pumpReceiptPage(
      tester,
      db: db,
      engine: _FakeOcrEngine(<String>[
        '微信支付',
        '支付失败',
        '商户全称：某某商店',
        '金额 ¥5.00',
      ]),
    );
    await tester.tap(find.text('从相册选一张'));
    await pumpUntil(tester, find.text('确认记账'));

    expect(find.textContaining('支付失败'), findsWidgets);
    expect(find.text('这张图不能直接记账，请换一张或手动记一笔'), findsOneWidget);

    // 按钮被禁用 → 点了也不会写库
    await tester.tap(find.text('确认记账'));
    await tester.pump(const Duration(seconds: 1));
    expect(await TransactionRepository(db).listByBook(book.id), isEmpty);
  });

  testWidgets('识别失败（通道不可用）：停在第一步并给出可读提示', (WidgetTester tester) async {
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);
    await BookRepository(db).ensureDefaultBook();

    await pumpReceiptPage(tester, db: db, engine: _ThrowingOcrEngine());
    await tester.tap(find.text('从相册选一张'));
    await pumpUntil(tester, find.textContaining('这台设备上用不了端上文字识别'));

    expect(find.text('从相册选一张'), findsOneWidget);
    expect(find.text('确认记账'), findsNothing);
  });
}

/// 抛 [OcrFailure] 的引擎（模拟非 Android / 通道缺失）。
class _ThrowingOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> recognize(String imagePath) async {
    throw const OcrFailure('unsupported_platform', 'MissingPluginException');
  }

  @override
  Future<void> dispose() async {}
}
