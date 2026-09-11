import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;

  setUp(() {
    db = openTestDatabase();
    addTearDown(db.close);
    repo = TransactionRepository(db);
  });

  const baseBookId = 'b1';
  const baseAccountId = 'a1';
  const baseCategoryId = 'c1';

  test('金额为 0 / 负数抛错', () {
    expect(
      () => repo.create(
        bookId: baseBookId,
        accountId: baseAccountId,
        categoryId: baseCategoryId,
        type: 'expense',
        amountCents: 0,
        occurredAt: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repo.create(
        bookId: baseBookId,
        accountId: baseAccountId,
        categoryId: baseCategoryId,
        type: 'expense',
        amountCents: -100,
        occurredAt: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('expense 缺 categoryId 抛错', () {
    expect(
      () => repo.create(
        bookId: baseBookId,
        accountId: baseAccountId,
        type: 'expense',
        amountCents: 100,
        occurredAt: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('创建后 id 为 UUID、dirty=1、deletedAt=null', () async {
    final tx = await repo.create(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 1234,
      occurredAt: DateTime.now().millisecondsSinceEpoch,
      note: '午饭',
    );
    expect(tx.id, hasLength(36));
    expect(tx.dirty, 1);
    expect(tx.deletedAt, isNull);
    expect(tx.amountCents, 1234);
    expect(tx.note, '午饭');
    expect(tx.source, 'manual');
  });

  test('更新后 updatedAt 变化、createdAt 不变', () async {
    final tx = await repo.create(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 1234,
      occurredAt: DateTime.now().millisecondsSinceEpoch,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final updated = await repo.update(
      tx.id,
      amountCents: 2000,
      note: '晚饭',
    );
    expect(updated.amountCents, 2000);
    expect(updated.note, '晚饭');
    expect(updated.createdAt, tx.createdAt);
    expect(updated.updatedAt, greaterThanOrEqualTo(tx.createdAt));
  });

  test('软删除后 listByMonth 查不到，但 getById(includeDeleted) 能取到',
      () async {
    final tx = await repo.create(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 1234,
      occurredAt: DateTime(2026, 9, 1).millisecondsSinceEpoch,
    );
    await repo.softDelete(tx.id);
    final month = await repo.listByMonth(baseBookId, 2026, 9);
    expect(month.map((t) => t.id), isNot(contains(tx.id)));
    final got = await repo.getById(tx.id, includeDeleted: true);
    expect(got?.deletedAt, isNotNull);
  });

  test('listByMonth 月份边界不漏不多', () async {
    Future<void> seed(int cents, DateTime when) => repo.create(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: cents,
      occurredAt: when.millisecondsSinceEpoch,
    );

    await seed(100, DateTime(2026, 7, 31, 23, 59, 59, 999));
    await seed(200, DateTime(2026, 9, 1));
    await seed(300, DateTime(2026, 9, 30, 23, 59, 59, 999));
    await seed(400, DateTime(2026, 10, 1));

    final sep = await repo.listByMonth(baseBookId, 2026, 9);
    final amounts = sep.map((t) => t.amountCents).toList()..sort();
    expect(amounts, <int>[200, 300]);
    // 倒序：9/30 在前
    expect(sep.first.amountCents, 300);
  });

  test('importTransaction 相同指纹第二次返回 duplicate（不抛错）', () async {
    final occ = DateTime.now().millisecondsSinceEpoch;
    Future<ImportResult> run() => repo.importTransaction(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 1234,
      occurredAt: occ,
      source: 'wechat_csv',
      externalId: 'W123',
    );

    final r1 = await run();
    expect(r1, isA<ImportOk>());
    final r2 = await run();
    expect(r2, isA<ImportDuplicate>());
    expect((r2 as ImportDuplicate).existingTx.id, (r1 as ImportOk).tx.id);
  });

  test('软删该笔后，相同指纹可再次成功写入', () async {
    final occ = DateTime.now().millisecondsSinceEpoch;
    Future<ImportResult> run() => repo.importTransaction(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 1234,
      occurredAt: occ,
      source: 'wechat_csv',
      externalId: 'WX',
    );

    final r1 = await run();
    await repo.softDelete((r1 as ImportOk).tx.id);
    expect(await run(), isA<ImportOk>());
  });

  test('source=manual 时 fingerprint 为 null，同金额时间可重复写入', () async {
    final occ = DateTime.now().millisecondsSinceEpoch;
    final t1 = await repo.create(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 50,
      occurredAt: occ,
      source: 'manual',
    );
    final t2 = await repo.create(
      bookId: baseBookId,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 50,
      occurredAt: occ,
      source: 'manual',
    );
    expect(t1.id, isNot(t2.id));
    expect(t1.fingerprint, isNull);
  });

  test('账本隔离：另一个账本查不到本账本流水', () async {
    await repo.create(
      bookId: 'book-a',
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 500,
      occurredAt: DateTime(2026, 9, 5).millisecondsSinceEpoch,
    );
    expect(await repo.listByMonth('book-b', 2026, 9), isEmpty);
    expect(await repo.listByMonth('book-a', 2026, 9), hasLength(1));
  });

  test('listByYear：跨 12 个月取数，跨年 / 已删不计', () async {
    Future<void> add(DateTime at, {String book = baseBookId}) => repo.create(
      bookId: book,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 100,
      occurredAt: at.millisecondsSinceEpoch,
    );

    await add(DateTime(2026, 1, 1)); // 年初边界（含）
    await add(DateTime(2026, 7, 16));
    await add(DateTime(2026, 12, 31, 23, 59)); // 年末边界（含）
    await add(DateTime(2025, 12, 31, 23, 59)); // 上一年 → 不含
    await add(DateTime(2027, 1, 1)); // 下一年 → 不含
    await add(DateTime(2026, 3, 3), book: 'book-b'); // 别的账本 → 不含

    final rows = await repo.listByYear(baseBookId, 2026);
    expect(rows, hasLength(3));
    // 倒序：年末 → 年初
    expect(rows.first.occurredAt, DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch);

    // 软删后不再计入
    await repo.softDelete(rows.first.id);
    expect(await repo.listByYear(baseBookId, 2026), hasLength(2));
  });

  test('listByBook：全量取数（跨年跨月）、倒序、排除已删、账本隔离', () async {
    Future<TxRow> add(
      DateTime at, {
      String book = baseBookId,
      String note = '',
    }) => repo.create(
      bookId: book,
      accountId: baseAccountId,
      categoryId: baseCategoryId,
      type: 'expense',
      amountCents: 100,
      occurredAt: at.millisecondsSinceEpoch,
      note: note,
    );

    await add(DateTime(2024, 3, 5), note: '两年前');
    await add(DateTime(2026, 9, 12), note: '本月');
    await add(DateTime(2026, 9, 20), note: '本月下旬');
    // 搜索不受「不能翻到未来月」限制，未来日期的账也要能搜到
    await add(DateTime(2027, 1, 2), note: '未来月');
    await add(DateTime(2026, 5, 1), book: 'book-b', note: '别的账本');
    final deleted = await add(DateTime(2026, 6, 1), note: '待删');

    final rows = await repo.listByBook(baseBookId);
    expect(rows, hasLength(5));
    // 倒序：最新的在前
    expect(rows.first.note, '未来月');
    expect(rows.last.note, '两年前');

    await repo.softDelete(deleted.id);
    final after = await repo.listByBook(baseBookId);
    expect(after, hasLength(4));
    expect(after.map((t) => t.id), isNot(contains(deleted.id)));

    // 账本隔离
    expect(await repo.listByBook('book-b'), hasLength(1));
  });
}
