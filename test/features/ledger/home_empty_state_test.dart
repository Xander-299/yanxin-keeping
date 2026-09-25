/// 回归：首次使用验收 P4 —— 零配置首页空态必须有可懂的下一步。
///
/// 原问题：列表区一片空白，文案还让用户找并不存在的「＋」按钮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/theme/toon.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('零配置首页空态：给出说明 + 可点的「记一笔」入口', (WidgetTester tester) async {
    await pumpApp(tester);

    // 空态有解释，而不是空白
    expect(find.textContaining('还没有记账'), findsOneWidget);
    // 导入是另一条常见入口，明确指路
    expect(find.textContaining('导入账单'), findsOneWidget);

    // 空态里的「记一笔」按钮（区别于底栏 tab 的「记一笔」）
    final cta = find.widgetWithText(TextButton, '记一笔');
    expect(cta, findsOneWidget);

    // 800×600 测试视口下按钮在折叠下方，先滚进视口再点
    await tester.dragUntilVisible(
      cta,
      find.byType(CustomScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();

    // 真的进了记一笔页。
    // 判据口径改于 F7.9 —— 顶部 AppBar 的「保存」已删除，保存入口只留底部吸底按钮
    // （见 `docs/SPEC-F7.9-record-sticky-save.md`）。故不再断言 AppBar 里的「保存」，
    // 改为「AppBar 只有标题」+「吸底按钮在位」。
    expect(find.widgetWithText(AppBar, '记一笔'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '保存'), findsNothing);
    // 吸底按钮用 ToonButton 定位：首页空态的 cta 是 TextButton.icon、底栏中央是 Tooltip
    // → 无论下层路由是否还在树上，这个 finder 都只会命中吸底那一处。
    expect(find.widgetWithText(ToonButton, '记一笔'), findsOneWidget);
    expect(find.text('请选择分类'), findsOneWidget);
  });
}
