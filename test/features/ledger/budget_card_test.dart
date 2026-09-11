/// 预算占位卡：必须让用户一眼看出卡上数字是示例，不是自己的账。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/ledger/presentation/widgets/budget_card_placeholder.dart';

void main() {
  // 回归：首次使用验收 P2 —— 预算卡写死了 101.52 已消费 / 10.2%，而同一屏的
  // hero 显示真实月支出（首屏两个矛盾的「本月支出」）。数字暂时仍为示例值，
  // 但界面必须显式标注，否则用户会以为 App 算错账。
  testWidgets('预算卡标注为示例数据', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BudgetCardPlaceholder())),
      ),
    );

    expect(find.text('本月预算'), findsOneWidget);
    expect(find.text('示例'), findsOneWidget);
    expect(
      find.textContaining('预算功能建设中，以上均为示例数据'),
      findsOneWidget,
    );
  });
}
