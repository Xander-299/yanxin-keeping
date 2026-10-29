/// hero 卡片：金额变化时的淡入（2026-10-28）。
///
/// 用户要「hero 金额淡入」：切月份或记完一笔后，数字从 0→1 淡进来，而不是硬切。
/// 这里同时钉住两点：
/// 1. 值变了要**真的在动**（动画中 opacity < 1）；
/// 2. 用的是 `FadeTransition`（透传基线），没有引入 `Stack` —— 否则金额与 `¥` 的基线对齐会断。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';
import 'package:yanxin/features/ledger/presentation/widgets/month_hero.dart';

void main() {
  testWidgets('金额变化时淡入；落定后完全可见', (WidgetTester tester) async {
    final ValueNotifier<int> cents = ValueNotifier<int>(10000);
    addTearDown(cents.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildToonTheme(ToonPalette.light, Brightness.light),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: cents,
            builder: (BuildContext _, int c, Widget? _) => MonthHero(
              year: 2026,
              month: 10,
              summary: MonthSummary(
                incomeCents: 0,
                expenseCents: c,
                balanceCents: -c,
              ),
              canNext: true,
              onPrevMonth: () {},
              onNextMonth: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('100.00'), findsOneWidget);

    // 切月 → 金额从 100.00 变 200.00
    cents.value = 20000;
    await tester.pump(); // didUpdateWidget → 动画从 0 开始
    await tester.pump(const Duration(milliseconds: 40)); // 动画进行中

    final List<FadeTransition> during = tester
        .widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(MonthHero),
            matching: find.byType(FadeTransition),
          ),
        )
        .toList();
    expect(during, isNotEmpty, reason: 'hero 金额要包一层 FadeTransition');
    expect(
      during.any((FadeTransition f) => f.opacity.value < 0.95),
      isTrue,
      reason: '金额变化必须淡入（硬切时 opacity 恒为 1）',
    );

    await tester.pumpAndSettle();
    expect(find.text('200.00'), findsOneWidget);
    final List<FadeTransition> after = tester
        .widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(MonthHero),
            matching: find.byType(FadeTransition),
          ),
        )
        .toList();
    expect(after.every((FadeTransition f) => f.opacity.value == 1.0), isTrue);
  });

  testWidgets('金额没变时不动画（避免每次重建都闪一下）', (WidgetTester tester) async {
    final ValueNotifier<int> kick = ValueNotifier<int>(0);
    addTearDown(kick.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildToonTheme(ToonPalette.light, Brightness.light),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: kick,
            builder: (BuildContext _, int _, Widget? _) => MonthHero(
              year: 2026,
              month: 10,
              summary: const MonthSummary(
                incomeCents: 0,
                expenseCents: 10000,
                balanceCents: -10000,
              ),
              canNext: true,
              onPrevMonth: () {},
              onNextMonth: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    kick.value = 1; // 触发重建，但金额没变
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final List<FadeTransition> fades = tester
        .widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(MonthHero),
            matching: find.byType(FadeTransition),
          ),
        )
        .toList();
    expect(fades.every((FadeTransition f) => f.opacity.value == 1.0), isTrue);
  });
}
