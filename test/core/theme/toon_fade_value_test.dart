/// `ToonFadeValue`：值变化淡入 + 基线对齐不被打断。
///
/// 第二条是**故意的护栏**：如果谁把它换成 `AnimatedSwitcher`（内部 `Stack`），
/// 放在 `Row(crossAxisAlignment: baseline)` 里就会断言失败 —— 而金额行正是这种结构。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/theme/toon.dart';

void main() {
  testWidgets('值变化 → 150ms 淡入；值不变 → 不动', (WidgetTester tester) async {
    final ValueNotifier<String> v = ValueNotifier<String>('10.00');
    addTearDown(v.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: v,
            builder: (BuildContext _, String s, Widget? _) =>
                ToonFadeValue(value: s, child: Text(s)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(ToonFadeValue),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    expect(opacity(), 1.0);

    v.value = '20.00';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacity(), lessThan(0.95), reason: '值变了要淡入');
    await tester.pumpAndSettle();
    expect(opacity(), 1.0);

    // 值不变的重建：不该再闪
    v.value = '20.00';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacity(), 1.0, reason: '值没变时不能动画');
  });

  testWidgets('animateOnFirstBuild：首次出现也淡入（聊天新答案卡用）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToonFadeValue(
            value: '¥36.00',
            animateOnFirstBuild: true,
            child: Text('¥36.00'),
          ),
        ),
      ),
    );
    // 首帧：还没开始推进 → 完全透明
    await tester.pump();
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(ToonFadeValue),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    expect(opacity(), 0.0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), greaterThan(0.0), reason: '首帧后应该开始淡入');
    await tester.pumpAndSettle();
    expect(opacity(), 1.0);
  });

  testWidgets('默认不在首次出现时动画（列表进页面不该整体闪）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToonFadeValue(value: '10.00', child: Text('10.00')),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(ToonFadeValue),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      1.0,
    );
  });

  testWidgets('放进 baseline Row 不报错（说明没用 Stack 包）', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('¥', style: TextStyle(fontSize: 20)),
              ToonFadeValue(
                value: '10.00',
                child: Text('10.00', style: TextStyle(fontSize: 40)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
