/// 首页入口卡测试：点输入框进聊天、点相机带 image 模式、点示例带问题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/chat/presentation/chat_page.dart';
import 'package:yanxin/features/chat/presentation/widgets/chat_entry_card.dart';

ChatLaunch? _launched;

Future<void> _pump(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: SingleChildScrollView(child: ChatEntryCard())),
      ),
      GoRoute(
        path: '/chat',
        builder: (_, GoRouterState state) {
          _launched = state.extra as ChatLaunch?;
          return const Scaffold(body: Text('聊天页占位'));
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: router, theme: buildToonTheme(ToonPalette.light, Brightness.light)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _launched = null);

  testWidgets('点「假输入框」→ 进 /chat（不带额外意图）', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('问一句，或发张账单截图'));
    await tester.pumpAndSettle();

    expect(find.text('聊天页占位'), findsOneWidget);
    expect(_launched?.openImagePicker, isNot(true));
    expect(_launched?.question, isNull);
  });

  testWidgets('点相机 → 进 /chat 并请求弹相册', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(find.text('聊天页占位'), findsOneWidget);
    expect(_launched?.openImagePicker, isTrue);
  });

  testWidgets('点示例 chip → 进 /chat 并带上这句话', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('这个月花了多少'));
    await tester.pumpAndSettle();

    expect(find.text('聊天页占位'), findsOneWidget);
    expect(_launched?.question, '这个月花了多少');
  });
}
