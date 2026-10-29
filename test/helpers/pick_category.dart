/// 在「记一笔」页的分类选择器里选中一个分类。
///
/// 为什么要这个 helper：2026-10-29 起预置一级分类带二级（餐饮 → 早餐 / 午餐 / 晚餐…），
/// 点一级分类会**钻进子列表**而不是直接选中，测试里原来那一行 `tap(分类名)` 会停在子列表上，
/// 保存出来的账单没有分类。这里点完一级再点「XX（不细分）」；没有二级的分类（如「其他」）
/// 点一下就结束。
library;

import 'package:flutter_test/flutter_test.dart';

/// 选中 [name]（先点一级；若进了子列表再点「不细分」）。
Future<void> pickCategory(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
  final Finder drill = find.text('$name（不细分）');
  if (drill.evaluate().isNotEmpty) {
    await tester.tap(drill.last);
    await tester.pumpAndSettle();
  }
}

/// 选中 [parent] 下的某个二级分类（用于需要真正落到二级的用例）。
Future<void> pickSubCategory(
  WidgetTester tester,
  String parent,
  String child,
) async {
  await tester.tap(find.text(parent).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(child).last);
  await tester.pumpAndSettle();
}
