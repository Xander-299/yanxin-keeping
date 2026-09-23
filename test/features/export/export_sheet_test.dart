/// 「我的 → 数据导出」入口 + 导出弹层（F7.7 B 批）。
///
/// 只覆盖**不依赖 file_picker 原生通道**的部分：
/// 入口接通、两条选项、取消关闭、以及「原生通道不可用时」不崩且给出可读提示。
/// 真正落盘（SAF 对话框 + 写文件）只能在真机上走查 —— 见 `docs/SPEC-F7.7-backlog.md` §B。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/export/presentation/export_sheet.dart';

import '../../helpers/pump_app.dart';

/// 轮询等待某个 finder 出现（写库 / 弹层动画都是真实异步，`pumpAndSettle` 会早退）。
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (int i = 0; i < 60; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('等待超时：$finder');
}

/// 直达「我的」页（壳路由 tab）。
Future<void> _goProfile(WidgetTester tester) async {
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('我的 → 数据导出：弹出弹层，两条选项 + 取消都在', (WidgetTester tester) async {
    await pumpApp(tester);
    await _goProfile(tester);
    await pumpUntil(tester, find.text('数据导出'));

    await tester.tap(find.text('数据导出'));
    await tester.pumpAndSettle();

    expect(find.text('导出流水 CSV'), findsOneWidget);
    expect(find.text('导出备份 JSON'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // 口径提示：CSV 用「元」、备份用「分」
    expect(find.textContaining('备份 JSON 金额是整数'), findsOneWidget);
  });

  testWidgets('取消：关闭弹层', (WidgetTester tester) async {
    await pumpApp(tester);
    await _goProfile(tester);
    await pumpUntil(tester, find.text('数据导出'));
    await tester.tap(find.text('数据导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出流水 CSV'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('导出流水 CSV'), findsNothing);
  });

  testWidgets('原生文件通道不可用时：不崩、给可读提示、弹层不关', (WidgetTester tester) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext c, WidgetRef ref, Widget? _) => Center(
                child: TextButton(
                  onPressed: () => showExportSheet(c, ref),
                  child: const Text('打开导出'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出流水 CSV'));
    // 取数是真实异步（读库），pumpAndSettle 会早退 → 轮询等提示
    await pumpUntil(tester, find.text('导出失败，请换个保存位置再试'));

    // 测试环境没有 file_picker 原生实现 → 走错误分支，给出人话提示（不是抛异常）
    expect(find.text('导出失败，请换个保存位置再试'), findsOneWidget);
    // 弹层仍在，用户可以重试或改点另一条
    expect(find.text('导出备份 JSON'), findsOneWidget);
  });
}
