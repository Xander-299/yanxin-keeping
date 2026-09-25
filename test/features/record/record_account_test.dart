/// F7.7 A.0：记一笔支持选账户。
///
/// 回归点：原来 `record_page` 写死 `accountId: accounts.first.id`，用户选不了账户
/// → 「按账户报表」永远只有一行。这里验证「选的账户真的落到 transactions.account_id」。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/pump_app.dart';

/// 金额键盘上的某个键。
///
/// ⚠️ 不能只按文本找：`AmountKeyboard` 顶部的金额显示区也在同一个子树里，
/// 输入 '8' 之后 `find.text('8')` 会同时命中「显示区」和「按键」→ tap 报多命中。
/// 按键外面包着 `ToonPress`，显示区没有 → 用 `widgetWithText` 精确定位。
Finder _key(String label) => find.widgetWithText(ToonPress, label);

/// 点底部**吸底**的主按钮 —— F7.9 起这是全页唯一的保存入口。
///
/// 历史坑（F7.7–F7.8 时期，顶部 AppBar 还有个「保存」，现已移除）：
/// **不能**写 `tester.tap(find.widgetWithText(AppBar, '保存'))` —— 那个 finder
/// 命中的是 **AppBar 自身**，`tap` 取它的中心点（标题区那一带），根本点不到
/// 右上角的按钮 → 静默不生效（`warnIfMissed` 也不会警告，因为中心点确实在
/// AppBar 内），表现为「保存没反应、库里没有这笔」。
///
/// ⚠️ 吸底按钮**不在 `Scrollable` 内**（它是滚动区的兄弟节点），
/// `ensureVisible` 会因 `Scrollable.of` 返回 null 而抛错 → 直接 tap。
Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ToonButton, '记一笔'));
  await tester.pumpAndSettle();
}

/// 造账本（自带「现金」）+ 第二个账户「招行」。
Future<({String bookId, String bankId})> _seed(AppDatabase db) async {
  final book = await BookRepository(db).ensureDefaultBook();
  final accounts = AccountRepository(db);
  final cash = (await accounts.listByBook(book.id)).first;
  expect(cash.name, '现金'); // 默认账户不变，老行为的前提
  final bank = await accounts.create(
    bookId: book.id,
    name: '招行',
    type: 'bank',
    sortOrder: 1,
  );
  return (bookId: book.id, bankId: bank.id);
}

void main() {
  testWidgets('选「招行」后保存 → transactions.account_id 是招行', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final seed = await _seed(db);
    final repo = TransactionRepository(db);

    await pumpApp(tester, database: db);
    // 底栏中央「记一笔」
    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();

    // 1) 默认账户 = 列表首个（老行为不变）
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('现金'), findsOneWidget);

    // 2) 打开账户弹层，改选「招行」
    await tester.ensureVisible(find.text('现金'));
    await tester.tap(find.text('现金'));
    await tester.pumpAndSettle();
    expect(find.text('选择账户'), findsOneWidget);

    await tester.tap(find.text('招行'));
    await tester.pumpAndSettle();
    expect(find.text('招行'), findsOneWidget); // 字段已回填

    // 3) 金额 88.88
    for (final String label in <String>['8', '8', '.', '8', '8']) {
      await tester.tap(_key(label));
      await tester.pump();
    }

    // 4) 分类：餐饮
    await tester.ensureVisible(find.text('请选择分类'));
    await tester.tap(find.text('请选择分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    // 5) 保存（F7.9：底部吸底按钮，全页唯一入口）
    await _tapSave(tester);

    // 6) 库里那笔的账户必须是「招行」（写库是真实异步 → 轮询到出现为止）
    final DateTime now = DateTime.now();
    List<TxRow> rows = <TxRow>[];
    for (int i = 0; i < 40 && rows.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      rows = await repo.listByMonth(seed.bookId, now.year, now.month);
    }
    expect(rows.length, 1);
    expect(rows.single.accountId, seed.bankId);
    expect(rows.single.amountCents, 8888);
  });

  testWidgets('不选账户直接保存 → 仍用列表首个账户（老行为）', (
    WidgetTester tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final seed = await _seed(db);
    final repo = TransactionRepository(db);
    final cashId = (await AccountRepository(db).listByBook(seed.bookId)).first.id;

    await pumpApp(tester, database: db);
    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();

    for (final String label in <String>['1', '2']) {
      await tester.tap(_key(label));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('请选择分类'));
    await tester.tap(find.text('请选择分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();

    await _tapSave(tester);

    final DateTime now = DateTime.now();
    List<TxRow> rows = <TxRow>[];
    for (int i = 0; i < 40 && rows.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      rows = await repo.listByMonth(seed.bookId, now.year, now.month);
    }
    expect(rows.length, 1);
    expect(rows.single.accountId, cashId);
    expect(rows.single.amountCents, 1200);
  });
}
