/// 回归：保存入口的可见性与唯一性（**F7.9 口径**）。
///
/// 沿革：
/// - F7.7 首次使用验收 P5 发现「大屏（横屏 / 平板）下『备注 + 记一笔』落到视口外」，
///   当时在 AppBar 加了常驻「保存」兜底 → 于是页面上有了两个保存入口。
/// - F7.9 用户裁定改方案：**底部按钮吸底常驻 + 删掉顶部入口**
///   （`docs/SPEC-F7.9-record-sticky-save.md`）。本文件随之改口径：
///   ① AppBar 与全页再无「保存」（唯一入口 = 底部吸底按钮）；
///   ② **矮视口**（逻辑 800×400，内容必然溢出）下按钮也一直落在视口内；
///   ③ 内容滚到底之后按钮位置**不变**（真的吸底，不随内容滚走）；
///   ④ 吸底按钮走同一套 `_save()` 校验。
///
/// ⚠️ 吸底按钮位于滚动区的**兄弟节点**（不在 `Scrollable` 内）→ 这里**不能**用
/// `tester.ensureVisible`（`Scrollable.of` 返回 null 会直接抛错）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/record/presentation/record_page.dart';

import '../../helpers/test_database.dart';

/// 逻辑视口高（矮视口：内容必然溢出，用来验证「吸底不随滚动走」）。
const double _viewportHeight = 400;

Future<void> _pumpRecordPage(WidgetTester tester) async {
  // 矮视口 + 显式重置（默认 800×600 时内容可能刚好不溢出，验证力不足）
  tester.view.physicalSize = const Size(800, _viewportHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = openTestDatabase();
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: RecordPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('保存入口只有一个：底部吸底按钮；AppBar 里没有「保存」', (WidgetTester tester) async {
    await _pumpRecordPage(tester);

    // ① 顶部入口已删除（AppBar 与全页都不该有裸 Text「保存」）
    expect(find.widgetWithText(AppBar, '保存'), findsNothing);
    expect(find.text('保存'), findsNothing);

    // ② 唯一入口 = 底部吸底按钮（新建模式文案是「记一笔」）
    final Finder saveBtn = find.widgetWithText(ToonButton, '记一笔');
    expect(saveBtn, findsOneWidget);

    // ③ 未滚动时就必须在视口内（这是吸底的核心保证）
    final Rect before = tester.getRect(saveBtn);
    expect(before.top, greaterThanOrEqualTo(0));
    expect(before.bottom, lessThanOrEqualTo(_viewportHeight));

    // ④ 把内容滚到底 → 按钮位置**不变**（吸底，不随内容滚走）
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    final Rect after = tester.getRect(saveBtn);
    expect(after.top, before.top);
    expect(after.bottom, lessThanOrEqualTo(_viewportHeight));
  });

  testWidgets('吸底按钮走同一套校验：金额为空 → 「请输入金额」', (WidgetTester tester) async {
    await _pumpRecordPage(tester);

    // 不能用 pumpAndSettle —— 会把 SnackBar 的自动消失定时器一并推进
    await tester.tap(find.widgetWithText(ToonButton, '记一笔'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请输入金额'), findsOneWidget);
  });
}
