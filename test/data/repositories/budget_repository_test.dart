/// 预算仓储单测：先查后写、同月唯一、软删、跨账本隔离。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/budget_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late BudgetRepository repo;
  late String bookId;

  setUp(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    repo = BudgetRepository(db);
    bookId = (await BookRepository(db).ensureDefaultBook()).id;
  });

  test('未设置时读不到，写入后能按月份读回', () async {
    expect(await repo.getForMonth(bookId, 2026, 9), isNull);

    final row = await repo.setForMonth(
      bookId: bookId,
      year: 2026,
      month: 9,
      amountCents: 100000,
    );
    expect(row.amountCents, 100000);
    expect(row.period, '2026-09');
    expect(row.bookId, bookId);
    expect(row.deletedAt, isNull);

    final read = await repo.getForMonth(bookId, 2026, 9);
    expect(read!.id, row.id);
    expect(read.amountCents, 100000);
  });

  test('period 零填充：1 月是 2026-01（字典序 = 时序）', () async {
    await repo.setForMonth(bookId: bookId, year: 2026, month: 1, amountCents: 1);
    await repo.setForMonth(bookId: bookId, year: 2026, month: 10, amountCents: 2);
    expect((await repo.getForMonth(bookId, 2026, 1))!.period, '2026-01');
    expect((await repo.getForMonth(bookId, 2026, 10))!.period, '2026-10');
  });

  test('同月重复设置 = 更新同一行（不产生第二行，created_at 不变）', () async {
    final first = await repo.setForMonth(
      bookId: bookId,
      year: 2026,
      month: 9,
      amountCents: 100000,
    );
    final second = await repo.setForMonth(
      bookId: bookId,
      year: 2026,
      month: 9,
      amountCents: 250000,
    );
    expect(second.id, first.id);
    expect(second.amountCents, 250000);
    expect(second.createdAt, first.createdAt);
    expect(second.dirty, 1);
    expect(await repo.getForMonth(bookId, 2026, 9), isNotNull);
  });

  test('不同月份互不干扰', () async {
    await repo.setForMonth(bookId: bookId, year: 2026, month: 8, amountCents: 1);
    await repo.setForMonth(bookId: bookId, year: 2026, month: 9, amountCents: 200000);
    expect((await repo.getForMonth(bookId, 2026, 8))!.amountCents, 1);
    expect((await repo.getForMonth(bookId, 2026, 9))!.amountCents, 200000);
  });

  test('不同账本互不干扰', () async {
    final other = await BookRepository(db).create(name: '另一个账本');
    final otherRepo = BudgetRepository(db);
    await otherRepo.setForMonth(
      bookId: other.id,
      year: 2026,
      month: 9,
      amountCents: 5000,
    );
    expect(await otherRepo.getForMonth(bookId, 2026, 9), isNull);
    expect((await otherRepo.getForMonth(other.id, 2026, 9))!.amountCents, 5000);
  });

  test('清除 = 软删：读不到，但行还在（deleted_at 非空）', () async {
    final row = await repo.setForMonth(
      bookId: bookId,
      year: 2026,
      month: 9,
      amountCents: 100000,
    );
    expect(await repo.clearForMonth(bookId, 2026, 9), 1);
    expect(await repo.getForMonth(bookId, 2026, 9), isNull);
    // 再删一次没有可删的行
    expect(await repo.clearForMonth(bookId, 2026, 9), 0);

    // 行本身还在，只是 deleted_at 非空（与其它业务表一致，永不物理删）
    final raw = await (db.select(db.budgets)
          ..where((b) => b.id.equals(row.id)))
        .getSingle();
    expect(raw.deletedAt, isNotNull);
    expect(raw.amountCents, 100000);
  });

  test('清除后可以重新设置（部分唯一索引只管未删除行）', () async {
    final first = await repo.setForMonth(
      bookId: bookId,
      year: 2026,
      month: 9,
      amountCents: 100000,
    );
    await repo.clearForMonth(bookId, 2026, 9);
    final again = await repo.setForMonth(
      bookId: bookId,
      year: 2026,
      month: 9,
      amountCents: 300000,
    );
    expect(again.id, isNot(first.id));
    expect((await repo.getForMonth(bookId, 2026, 9))!.amountCents, 300000);
  });

  test('金额必须为正整数分', () async {
    expect(
      () => repo.setForMonth(bookId: bookId, year: 2026, month: 9, amountCents: 0),
      throwsArgumentError,
    );
    expect(
      () => repo.setForMonth(bookId: bookId, year: 2026, month: 9, amountCents: -1),
      throwsArgumentError,
    );
    expect(
      () => repo.setForMonth(bookId: '', year: 2026, month: 9, amountCents: 100),
      throwsArgumentError,
    );
  });

  test('listByBook：全量未删预算，按 period 升序（供数据导出用）', () async {
    // 乱序写入，验证返回顺序按 period 升序而非写入顺序
    await repo.setForMonth(bookId: bookId, year: 2026, month: 10, amountCents: 3);
    await repo.setForMonth(bookId: bookId, year: 2025, month: 12, amountCents: 1);
    await repo.setForMonth(bookId: bookId, year: 2026, month: 1, amountCents: 2);

    final rows = await repo.listByBook(bookId);
    expect(rows.map((b) => b.period).toList(), <String>[
      '2025-12',
      '2026-01',
      '2026-10',
    ]);
    expect(rows.map((b) => b.amountCents).toList(), <int>[1, 2, 3]);
  });

  test('listByBook：不含已软删、且按账本隔离', () async {
    await repo.setForMonth(bookId: bookId, year: 2026, month: 9, amountCents: 100);
    await repo.setForMonth(bookId: bookId, year: 2026, month: 8, amountCents: 200);
    await repo.clearForMonth(bookId, 2026, 8);

    final other = await BookRepository(db).create(name: '另一个账本');
    await BudgetRepository(db).setForMonth(
      bookId: other.id,
      year: 2026,
      month: 9,
      amountCents: 999,
    );

    final rows = await repo.listByBook(bookId);
    expect(rows.length, 1);
    expect(rows.single.period, '2026-09');
    expect(rows.single.amountCents, 100);
  });

  test('listByBook：空账本返回空列表', () async {
    expect(await repo.listByBook(bookId), isEmpty);
  });
}
