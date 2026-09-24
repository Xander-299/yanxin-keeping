/// F7.8 左滑删除：开合判定纯函数 + [SwipeActionRow] 的行行为。
///
/// 覆盖 SPEC-F7.8 的 D1（滑出）、D3（取消/收起）、D4（单开 + 点行收起）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/ledger/presentation/widgets/swipe_action_row.dart';

/// 造一个 n 行的宿主：每行一个可点的 child（记录 onTap）+ 一个动作区（记录 onAction）。
Widget _host({
  required List<String> ids,
  required List<String> acted,
  required List<String> tapped,
}) {
  final ValueNotifier<String?> open = ValueNotifier<String?>(null);
  addTearDown(open.dispose);
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          for (final String id in ids)
            SwipeActionRow(
              key: ValueKey<String>('swipe-$id'),
              rowId: id,
              openRow: open,
              onAction: () async => acted.add(id),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tapped.add(id),
                child: SizedBox(
                  height: 48,
                  child: Center(child: Text('row-$id')),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

double _x(WidgetTester tester, String id) =>
    tester.getTopLeft(find.text('row-$id')).dx;

void main() {
  group('resolveSwipeOpen（开合判定）', () {
    test('行程不足且没甩 → 不打开', () {
      expect(resolveSwipeOpen(dx: 10, velocity: 0), isFalse);
      expect(resolveSwipeOpen(dx: 37, velocity: 0), isFalse); // < 84 * 0.45
    });

    test('行程过半 → 打开', () {
      expect(resolveSwipeOpen(dx: 38, velocity: 0), isTrue);
      expect(resolveSwipeOpen(dx: 84, velocity: 0), isTrue);
    });

    test('行程不足但向左甩得够快 → 打开', () {
      expect(resolveSwipeOpen(dx: 5, velocity: -400), isTrue);
    });

    test('向右甩或速度不够 → 不打开', () {
      expect(resolveSwipeOpen(dx: 5, velocity: 400), isFalse);
      expect(resolveSwipeOpen(dx: 5, velocity: -200), isFalse);
    });

    test('actionWidth 为 0 时恒不打开（防御）', () {
      expect(resolveSwipeOpen(dx: 100, velocity: -9999, actionWidth: 0), isFalse);
    });
  });

  group('SwipeActionRow', () {
    testWidgets('左滑露出删除按钮，点它触发 onAction 并自动收起', (WidgetTester tester) async {
      final acted = <String>[];
      await tester.pumpWidget(
        _host(ids: <String>['a'], acted: acted, tapped: <String>[]),
      );
      final double before = _x(tester, 'a');

      await tester.drag(find.text('row-a'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(_x(tester, 'a'), lessThan(before)); // 行已左移

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(acted, <String>['a']);
      expect(_x(tester, 'a'), before); // action 完成后回到原位
    });

    testWidgets('未滑开时点整行 = child 自己的 onTap（不进删除）', (WidgetTester tester) async {
      final acted = <String>[];
      final tapped = <String>[];
      await tester.pumpWidget(
        _host(ids: <String>['a'], acted: acted, tapped: tapped),
      );

      await tester.tap(find.text('row-a'));
      await tester.pumpAndSettle();

      expect(tapped, <String>['a']);
      expect(acted, isEmpty);
    });

    testWidgets('滑开后点整行 = 收起，且不触发 child 的 onTap', (WidgetTester tester) async {
      final acted = <String>[];
      final tapped = <String>[];
      await tester.pumpWidget(
        _host(ids: <String>['a'], acted: acted, tapped: tapped),
      );
      final double before = _x(tester, 'a');

      await tester.drag(find.text('row-a'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(_x(tester, 'a'), lessThan(before));

      await tester.tap(find.text('row-a'));
      await tester.pumpAndSettle();

      expect(tapped, isEmpty); // 没有跳编辑
      expect(_x(tester, 'a'), before); // 收起了
    });

    testWidgets('多行只允许一行展开', (WidgetTester tester) async {
      final acted = <String>[];
      await tester.pumpWidget(
        _host(ids: <String>['a', 'b'], acted: acted, tapped: <String>[]),
      );
      final double aBefore = _x(tester, 'a');
      final double bBefore = _x(tester, 'b');

      await tester.drag(find.text('row-a'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(_x(tester, 'a'), lessThan(aBefore));

      await tester.drag(find.text('row-b'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(_x(tester, 'a'), aBefore); // a 被收起
      expect(_x(tester, 'b'), lessThan(bBefore)); // b 展开
    });

    testWidgets('enabled = false 时纯展示：不滑、不渲染动作区', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeActionRow(
              enabled: false,
              onAction: () async {},
              child: const SizedBox(height: 40, child: Text('只读行')),
            ),
          ),
        ),
      );

      expect(find.text('删除'), findsNothing);
      await tester.drag(find.text('只读行'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('只读行')).dx, 0);
    });
  });
}
