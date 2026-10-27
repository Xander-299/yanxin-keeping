/// 「问账本」的编排测试：真实内存库 + 真实仓储 + 真实纯函数，只把整条链路跑通。
///
/// 覆盖：问一句 → 查库 → 出答案；不认识的问法；空问题；以及「答案里的数字与账本一致」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/providers/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/assistant/application/assistant_controller.dart';
import 'package:yanxin/features/assistant/application/finance_answer.dart';

import '../../helpers/test_database.dart';

/// 固定"现在"：2026-10-25 15:00（与 `finance_answer_test` 同一套数据口径）。
final int _nowMs = DateTime(2026, 10, 25, 15).millisecondsSinceEpoch;

Future<({AppDatabase db, ProviderContainer container})> _seed() async {
  final AppDatabase db = openTestDatabase();
  final Book book = await BookRepository(db).ensureDefaultBook();
  final CategoryRepository cats = CategoryRepository(db);
  final Category food = await cats.create(bookId: book.id, name: '餐饮', kind: 'expense');
  final Category shop = await cats.create(bookId: book.id, name: '购物', kind: 'expense');
  final Category salary = await cats.create(bookId: book.id, name: '工资', kind: 'income');
  final Account acc = await AccountRepository(db).create(bookId: book.id, name: '现金');
  final TransactionRepository tx = TransactionRepository(db);
  await tx.create(
    bookId: book.id,
    accountId: acc.id,
    type: 'expense',
    amountCents: 128050,
    occurredAt: DateTime(2026, 10, 3, 12).millisecondsSinceEpoch,
    categoryId: food.id,
    note: '午饭',
  );
  await tx.create(
    bookId: book.id,
    accountId: acc.id,
    type: 'expense',
    amountCents: 98000,
    occurredAt: DateTime(2026, 10, 8, 12).millisecondsSinceEpoch,
    categoryId: shop.id,
    note: '外套',
  );
  await tx.create(
    bookId: book.id,
    accountId: acc.id,
    type: 'income',
    amountCents: 1200000,
    occurredAt: DateTime(2026, 10, 1, 9).millisecondsSinceEpoch,
    categoryId: salary.id,
    note: '工资',
  );

  final ProviderContainer container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  return (db: db, container: container);
}

void main() {
  test('问「这个月花了多少」→ 金额与账本一致', () async {
    final r = await _seed();
    addTearDown(r.db.close);
    addTearDown(r.container.dispose);

    await r.container.read(assistantProvider.notifier).ask('这个月花了多少', nowMs: _nowMs);
    final AssistantState state = r.container.read(assistantProvider);
    expect(state.busy, isFalse);
    expect(state.turns.length, 1);
    final AssistantTurn turn = state.turns.single;
    expect(turn.question, '这个月花了多少');
    expect(turn.error, isNull);
    expect(turn.answer!.headline, '¥2,260.50'); // 1280.50 + 980
    expect(turn.answer!.narrative, contains('餐饮'));
    expect(turn.answer!.title, contains('2026年10月'));
  });

  test('问「本月预算还剩多少」（没设预算）→ 明确说没设，不编数字', () async {
    final r = await _seed();
    addTearDown(r.db.close);
    addTearDown(r.container.dispose);

    await r.container.read(assistantProvider.notifier).ask('本月预算还剩多少', nowMs: _nowMs);
    final FinanceAnswer answer = r.container.read(assistantProvider).turns.single.answer!;
    expect(answer.narrative, contains('还没设预算'));
    expect(answer.headline, isNull);
  });

  test('不认识的问法 → 给示例问题，不报错', () async {
    final r = await _seed();
    addTearDown(r.db.close);
    addTearDown(r.container.dispose);

    await r.container.read(assistantProvider.notifier).ask('帮我写一首诗', nowMs: _nowMs);
    final AssistantTurn turn = r.container.read(assistantProvider).turns.single;
    expect(turn.error, isNull);
    expect(turn.answer!.suggestions, kExampleQuestions);
  });

  test('空问题不入会话', () async {
    final r = await _seed();
    addTearDown(r.db.close);
    addTearDown(r.container.dispose);

    await r.container.read(assistantProvider.notifier).ask('   ', nowMs: _nowMs);
    expect(r.container.read(assistantProvider).turns, isEmpty);
  });

  test('clear 清空会话', () async {
    final r = await _seed();
    addTearDown(r.db.close);
    addTearDown(r.container.dispose);

    await r.container.read(assistantProvider.notifier).ask('这个月花了多少', nowMs: _nowMs);
    expect(r.container.read(assistantProvider).turns, isNotEmpty);
    r.container.read(assistantProvider.notifier).clear();
    expect(r.container.read(assistantProvider).turns, isEmpty);
  });

  test('连续追问：两轮都在，且各自独立查库', () async {
    final r = await _seed();
    addTearDown(r.db.close);
    addTearDown(r.container.dispose);

    final AssistantController c = r.container.read(assistantProvider.notifier);
    await c.ask('这个月花了多少', nowMs: _nowMs);
    await c.ask('这个月餐饮花了多少', nowMs: _nowMs);
    final List<AssistantTurn> turns = r.container.read(assistantProvider).turns;
    expect(turns.length, 2);
    expect(turns[0].answer!.headline, '¥2,260.50');
    expect(turns[1].answer!.headline, '¥1,280.50');
  });
}
