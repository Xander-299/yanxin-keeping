import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository catRepo;
  late String bookId;

  setUp(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    bookId = (await BookRepository(db).create(name: 'x')).id;
    catRepo = CategoryRepository(db);
  });

  test('预置分类不可删', () async {
    final preset = (await catRepo.listByBook(bookId, kind: 'expense')).first;
    expect(catRepo.softDelete(preset.id), throwsA(isA<StateError>()));
  });

  test('自定义分类可删', () async {
    final c = await catRepo.create(
      bookId: bookId,
      name: '自定义',
      kind: 'expense',
    );
    expect(await catRepo.softDelete(c.id), 1);
    expect(await catRepo.getById(c.id), isNull);
  });

  test('kind 非法抛错', () async {
    expect(
      () => catRepo.create(bookId: bookId, name: 'bad', kind: 'other'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('自定义分类可改名改图标', () async {
    final c = await catRepo.create(
      bookId: bookId,
      name: '打车',
      kind: 'expense',
    );
    final updated = await catRepo.update(c.id, name: '网约车', icon: '🚕');
    expect(updated.name, '网约车');
    expect(updated.icon, '🚕');
  });

  test('listByBook 按 kind 过滤且账本隔离', () async {
    final other = await BookRepository(db).create(name: 'y');
    await catRepo.create(bookId: bookId, name: '副业', kind: 'income');

    expect((await catRepo.listByBook(bookId, kind: 'income')).length, 7); // 6 预置 + 1
    expect(await catRepo.listByBook(other.id), isNot(contains(bookId)));
    for (final c in await catRepo.listByBook(other.id)) {
      expect(c.bookId, other.id);
    }
  });
}
