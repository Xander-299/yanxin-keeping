/// 截图草稿写库路径测试（F8.1）：真实 drift 内存库 + 现有入账链路。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/import/application/bill_importer.dart';
import 'package:yanxin/features/receipt/application/receipt_write.dart';

import '../../helpers/test_database.dart';

/// 一个可用的账本 + 账户 + 分类映射。
Future<({AppDatabase db, String bookId, String accountId, BillCategoryMaps maps})>
    seed() async {
  final AppDatabase db = openTestDatabase();
  final Book book = await BookRepository(db).ensureDefaultBook();
  final List<Account> accounts = await AccountRepository(db).listByBook(book.id);
  final BillCategoryMaps maps = await buildCategoryMaps(
    CategoryRepository(db),
    book.id,
  );
  return (db: db, bookId: book.id, accountId: accounts.first.id, maps: maps);
}

void main() {
  test('写入成功：source=screenshot，金额/时间/分类与入参一致', () async {
    final seeded = await seed();
    addTearDown(seeded.db.close);
    final TransactionRepository repo = TransactionRepository(seeded.db);
    final int occurredAt = DateTime(2026, 10, 23, 14, 5).millisecondsSinceEpoch;

    final ReceiptWriteResult result = await writeReceipt(
      repo,
      bookId: seeded.bookId,
      accountId: seeded.accountId,
      type: 'expense',
      amountCents: 3600,
      occurredAtMs: occurredAt,
      categoryId: resolveReceiptCategoryId(seeded.maps, 'expense', '餐饮')!,
      note: '星巴克咖啡',
      textHash: 'hash-a',
    );

    expect(result, isA<ReceiptWritten>());
    final List<TxRow> rows = await repo.listByBook(seeded.bookId);
    expect(rows.length, 1);
    expect(rows.single.amountCents, 3600);
    expect(rows.single.occurredAt, occurredAt);
    expect(rows.single.source, 'screenshot');
    expect(rows.single.type, 'expense');
    expect(rows.single.note, '星巴克咖啡');
  });

  test('同一张截图再确认一次 → 指纹命中，不重复入账', () async {
    final seeded = await seed();
    addTearDown(seeded.db.close);
    final TransactionRepository repo = TransactionRepository(seeded.db);
    final String categoryId =
        resolveReceiptCategoryId(seeded.maps, 'expense', '餐饮')!;

    Future<ReceiptWriteResult> write() => writeReceipt(
      repo,
      bookId: seeded.bookId,
      accountId: seeded.accountId,
      type: 'expense',
      amountCents: 1200,
      occurredAtMs: DateTime(2026, 10, 23, 12, 0).millisecondsSinceEpoch,
      categoryId: categoryId,
      note: '美团',
      textHash: 'hash-b',
    );

    expect(await write(), isA<ReceiptWritten>());
    expect(await write(), isA<ReceiptDuplicate>());
    expect((await repo.listByBook(seeded.bookId)).length, 1);
  });

  test('金额为 0 / 分类为空 → 失败且不写库', () async {
    final seeded = await seed();
    addTearDown(seeded.db.close);
    final TransactionRepository repo = TransactionRepository(seeded.db);

    final ReceiptWriteResult zero = await writeReceipt(
      repo,
      bookId: seeded.bookId,
      accountId: seeded.accountId,
      type: 'expense',
      amountCents: 0,
      occurredAtMs: DateTime(2026, 10, 23).millisecondsSinceEpoch,
      categoryId: resolveReceiptCategoryId(seeded.maps, 'expense', '餐饮')!,
      note: '',
      textHash: 'hash-c',
    );
    expect(zero, isA<ReceiptWriteFailed>());

    final ReceiptWriteResult noCategory = await writeReceipt(
      repo,
      bookId: seeded.bookId,
      accountId: seeded.accountId,
      type: 'expense',
      amountCents: 100,
      occurredAtMs: DateTime(2026, 10, 23).millisecondsSinceEpoch,
      categoryId: '',
      note: '',
      textHash: 'hash-d',
    );
    expect(noCategory, isA<ReceiptWriteFailed>());
    expect((await repo.listByBook(seeded.bookId)).isEmpty, isTrue);
  });

  group('分类解析（同名「其他」必须带 kind）', () {
    test('精确命中', () async {
      final seeded = await seed();
      addTearDown(seeded.db.close);
      final String? id = resolveReceiptCategoryId(
        seeded.maps,
        'expense',
        '餐饮',
      );
      expect(id, isNotNull);
      final List<Category> cats = await CategoryRepository(
        seeded.db,
      ).listByBook(seeded.bookId, kind: 'expense');
      expect(cats.any((Category c) => c.id == id && c.name == '餐饮'), isTrue);
    });

    test('名字不存在 → 落该方向的「其他」，不返回 null', () async {
      final seeded = await seed();
      addTearDown(seeded.db.close);
      final String? id = resolveReceiptCategoryId(
        seeded.maps,
        'expense',
        '这个名字不存在',
      );
      expect(id, isNotNull);
      final List<Category> cats = await CategoryRepository(
        seeded.db,
      ).listByBook(seeded.bookId, kind: 'expense');
      expect(cats.any((Category c) => c.id == id && c.name == '其他'), isTrue);
    });

    test('收入方向解析到收入分类（不会串到支出的「其他」）', () async {
      final seeded = await seed();
      addTearDown(seeded.db.close);
      final String? id = resolveReceiptCategoryId(
        seeded.maps,
        'income',
        '不存在',
      );
      final List<Category> income = await CategoryRepository(
        seeded.db,
      ).listByBook(seeded.bookId, kind: 'income');
      expect(income.any((Category c) => c.id == id), isTrue);
    });
  });

  group('疑似重复提示（只提示，不阻断）', () {
    test('同金额同时段同方向 → 命中；方向或金额不同则不命中', () async {
      final seeded = await seed();
      addTearDown(seeded.db.close);
      final TransactionRepository repo = TransactionRepository(seeded.db);
      final int at = DateTime(2026, 10, 23, 12, 0).millisecondsSinceEpoch;

      await writeReceipt(
        repo,
        bookId: seeded.bookId,
        accountId: seeded.accountId,
        type: 'expense',
        amountCents: 1200,
        occurredAtMs: at,
        categoryId: resolveReceiptCategoryId(seeded.maps, 'expense', '餐饮')!,
        note: '美团',
        textHash: 'hash-e',
      );

      final List<TxRow> same = await findSimilarReceipts(
        repo,
        bookId: seeded.bookId,
        type: 'expense',
        amountCents: 1200,
        occurredAtMs: at + 5 * 60 * 1000,
      );
      expect(same.length, 1);

      final List<TxRow> otherType = await findSimilarReceipts(
        repo,
        bookId: seeded.bookId,
        type: 'income',
        amountCents: 1200,
        occurredAtMs: at,
      );
      expect(otherType, isEmpty);

      final List<TxRow> otherAmount = await findSimilarReceipts(
        repo,
        bookId: seeded.bookId,
        type: 'expense',
        amountCents: 1300,
        occurredAtMs: at,
      );
      expect(otherAmount, isEmpty);

      // 时间窗外（默认 ±15 分钟）
      final List<TxRow> farAway = await findSimilarReceipts(
        repo,
        bookId: seeded.bookId,
        type: 'expense',
        amountCents: 1200,
        occurredAtMs: at + 40 * 60 * 1000,
      );
      expect(farAway, isEmpty);
    });
  });
}
