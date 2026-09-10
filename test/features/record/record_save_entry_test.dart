/// 回归：首次使用验收 P5 —— 保存入口不能藏在折叠下方。
///
/// 原问题：大屏（横屏模拟器 / 平板）下「备注 + 记一笔」落到视口外，
/// 用户填完金额和分类后看不到「下一步」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/record/presentation/record_page.dart';

import '../../helpers/test_database.dart';

void main() {
  testWidgets('记一笔页：AppBar 常驻「保存」，无需滚动即可见', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: RecordPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 记录：底部按钮是「记一笔」，因此「保存」只会命中 AppBar 那一个
    expect(find.widgetWithText(AppBar, '保存'), findsOneWidget);
    final save = find.text('保存');

    // 必须落在首屏视口内（不依赖滚动）
    final rect = tester.getRect(save);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));

    // 功能对齐底部按钮：金额为空时给出同一句校验提示
    // （不能用 pumpAndSettle —— SnackBar 的自动消失定时器会被一并推进）
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请输入金额'), findsOneWidget);
  });
}
