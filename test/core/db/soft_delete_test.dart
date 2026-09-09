// drift 与 matcher 都导出顶层 isNull → 隐藏 drift 的，保留 matcher 的
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';

import '../../helpers/test_database.dart';

/// 存储层软删除语义：业务不物理删除，只置 deleted_at。
/// 默认查询带 `deleted_at IS NULL` 即不可见；不带的查询仍可见（供回收/合并）。
void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
    addTearDown(db.close);
  });

  test('软删后默认查询不可见，但能查到 deleted_at', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(id: 'b1', name: 'x', createdAt: 1, updatedAt: 1),
        );
    await (db.update(db.books)..where((t) => t.id.equals('b1'))).write(
      const BooksCompanion(deletedAt: Value(123)),
    );

    final hidden = await (db.select(db.books)
          ..where((t) => t.id.equals('b1') & t.deletedAt.isNull()))
        .getSingleOrNull();
    expect(hidden, isNull);

    final visible = await (db.select(db.books)
          ..where((t) => t.id.equals('b1')))
        .getSingle();
    expect(visible.deletedAt, 123);
  });

  test('dirty 默认 1，写入后仍为 1', () async {
    final book = await db
        .into(db.books)
        .insertReturning(
          BooksCompanion.insert(
            id: 'b2',
            name: 'y',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    expect(book.dirty, 1);
    expect(book.deletedAt, isNull);
  });
}
