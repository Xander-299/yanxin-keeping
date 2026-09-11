import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late BookRepository repo;

  setUp(() {
    db = openTestDatabase();
    addTearDown(db.close);
    repo = BookRepository(db);
  });

  test('创建账本自动带默认账户 + 预置分类', () async {
    final book = await repo.create(name: '旅行账');
    final accounts = await AccountRepository(db).listByBook(book.id);
    expect(accounts, hasLength(1));
    expect(accounts.first.name, '现金');

    final cats = await CategoryRepository(db).listByBook(book.id);
    expect(cats.length, greaterThanOrEqualTo(15)); // 9 支出 + 6 收入
    final expenses = cats.where((c) => c.kind == 'expense').toList();
    expect(expenses, hasLength(9));
    expect(expenses.every((c) => c.isPreset == 1), isTrue);
  });

  test('切换账本数据隔离', () async {
    final bA = await repo.create(name: 'A');
    final bB = await repo.create(name: 'B');
    final accA = await AccountRepository(db).listByBook(bA.id);
    final accB = await AccountRepository(db).listByBook(bB.id);
    expect(accA, hasLength(1));
    expect(accB, hasLength(1));
    expect(accA.first.id, isNot(accB.first.id));

    final catA = await CategoryRepository(db).listByBook(bA.id);
    final catB = await CategoryRepository(db).listByBook(bB.id);
    expect(catA.length, catB.length);
    expect(catA.first.id, isNot(catB.first.id));
  });

  test('ensureDefaultBook 幂等：已存在则返回第一个且只建一个', () async {
    final first = await repo.ensureDefaultBook();
    final second = await repo.ensureDefaultBook();
    expect(second.id, first.id);
    final all = await repo.listAll();
    expect(all, hasLength(1));
  });

  test('软删除后 listAll 不可见，但可带 includeDeleted 取回', () async {
    final book = await repo.create(name: '临时');
    expect(await repo.softDelete(book.id), 1);
    expect(await repo.listAll(), isEmpty);
    final deleted = await repo.getById(book.id, includeDeleted: true);
    expect(deleted, isNotNull);
    expect(deleted!.deletedAt, isNotNull);
  });

  test('active_book_id 持久化（BUG-016 回归点）', () async {
    final book = await repo.create(name: 'A');
    expect(await repo.getActiveBookId(), isNull);
    await repo.setActiveBookId(book.id);
    expect(await repo.getActiveBookId(), book.id);
    await repo.setActiveBookId('other-id');
    expect(await repo.getActiveBookId(), 'other-id');
  });
}
