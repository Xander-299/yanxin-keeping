/// 聊天页 widget 测试：空态示例、打字问、发图 → 待确认卡、深色主题。
///
/// 视口用 360×800 逻辑像素（真机竖屏尺度）：800×600 太矮，答案卡会被挤出可视区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/platform/media_picker.dart';
import 'package:yanxin/core/theme/palette.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/data/providers/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/chat/presentation/chat_page.dart';
import 'package:yanxin/features/receipt/data/mlkit_ocr_engine.dart';
import 'package:yanxin/features/receipt/data/ocr_engine.dart';

import '../../helpers/test_database.dart';

class _FakePicker implements MediaPicker {
  _FakePicker(this.path);

  final String? path;
  int imageCalls = 0;

  @override
  Future<String?> pickImage() async {
    imageCalls++;
    return path;
  }

  @override
  Future<String?> pickDocument() async => null;
}

class _FakeOcr implements OcrEngine {
  _FakeOcr(this.lines);

  final List<String> lines;

  @override
  Future<OcrResult> recognize(String imagePath) async => OcrResult(
    lines: <OcrLine>[for (final String l in lines) OcrLine(text: l)],
    text: lines.join('\n'),
    elapsedMs: 12,
  );

  @override
  Future<void> dispose() async {}
}

Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxFrames = 80}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  await tester.pumpAndSettle();
}

Future<AppDatabase> _seed() async {
  final AppDatabase db = openTestDatabase();
  final Book book = await BookRepository(db).ensureDefaultBook();
  final Category food =
      await CategoryRepository(db).create(bookId: book.id, name: '餐饮', kind: 'expense');
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

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  MediaPicker? picker,
  OcrEngine? ocr,
  ThemeData? theme,
  ChatLaunch? launch,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (picker != null) mediaPickerProvider.overrideWithValue(picker),
        if (ocr != null) ocrEngineProvider.overrideWithValue(ocr),
      ],
      child: MaterialApp(theme: theme, home: ChatPage(launch: launch)),
    ),
  );
  await tester.pumpAndSettle();
}

const List<String> _wechatLines = <String>[
  '微信支付',
  '支付成功',
  '商户全称：星巴克咖啡',
  '支付金额 ¥36.00',
  '支付时间 2026-10-23 14:05:33',
];

void main() {
  testWidgets('空态：示例问题可点，点了出答案卡', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pump(tester, db);

    expect(find.text('说吧：问一句，或发张截图'), findsOneWidget);
    await tester.tap(find.text('这个月花了多少'));
    await pumpUntil(tester, find.textContaining('¥1,200.00'));

    expect(find.textContaining('¥1,200.00'), findsWidgets);
    final DateTime now = DateTime.now();
    expect(find.textContaining('${now.year}年${now.month}月'), findsWidgets);
  });

  testWidgets('打字提问 → 答案卡', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pump(tester, db);

    await tester.enterText(find.byType(TextField), '这个月花了多少');
    await tester.tap(find.text('发送'));
    await pumpUntil(tester, find.textContaining('¥1,200.00'));
    expect(find.textContaining('¥1,200.00'), findsWidgets);
  });

  testWidgets('点相机 → 识别 → 待确认账单卡（未确认不写库）', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    final _FakePicker picker = _FakePicker('/tmp/receipt.png');
    await _pump(tester, db, picker: picker, ocr: _FakeOcr(_wechatLines));

    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await pumpUntil(tester, find.text('待确认'));

    expect(picker.imageCalls, 1);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('36.00'), findsWidgets);
    expect(find.text('确认记账'), findsOneWidget);

    // 未确认前没有「已记账」
    expect(find.textContaining('已记账'), findsNothing);
  });

  testWidgets('深色主题：空态与答案卡都能渲染', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    await _pump(tester, db, theme: buildToonTheme(ToonPalette.dark, Brightness.dark));

    expect(find.text('说吧：问一句，或发张截图'), findsOneWidget);
    await tester.tap(find.text('这个月花了多少'));
    await pumpUntil(tester, find.textContaining('¥1,200.00'));
    expect(find.textContaining('¥1,200.00'), findsWidgets);
  });

  testWidgets('launch.openImagePicker：进页即弹相册', (WidgetTester tester) async {
    final AppDatabase db = await _seed();
    addTearDown(db.close);
    final _FakePicker picker = _FakePicker('/tmp/receipt.png');
    await _pump(
      tester,
      db,
      picker: picker,
      ocr: _FakeOcr(_wechatLines),
      launch: const ChatLaunch(openImagePicker: true),
    );
    await pumpUntil(tester, find.text('待确认'));

    expect(picker.imageCalls, 1);
    expect(find.text('待确认'), findsOneWidget);
  });
}
