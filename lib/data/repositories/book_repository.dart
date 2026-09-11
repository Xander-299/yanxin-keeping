/// 账本仓储。新建账本时自动带 1 个默认现金账户 + 预置分类组。
///
/// 对应旧栈 `src/repositories/book-repository.js`，含当前账本 id 持久化
/// （旧栈 BUG-016：此前只存内存，切账本后回首页被重置、杀进程后丢失）。
library;

import 'package:drift/drift.dart';

import '../../core/constants/preset.dart';
import '../../core/db/database.dart';
import '../../core/utils/id.dart';
import 'account_repository.dart';
import 'category_repository.dart';

/// active_book_id 在 schema_meta 里的键名。
const kActiveBookKey = 'active_book_id';

class BookRepository {
  BookRepository(this._db);

  final AppDatabase _db;

  /// 新建账本（事务内连带建默认账户 + 预置分类）。
  Future<Book> create({
    required String name,
    String type = 'personal',
    String currency = defaultCurrency,
    String icon = '',
    String color = '',
    int sortOrder = 0,
    String? ownerId,
    String? id,
  }) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'book.name 为必填');
    }
    final bookId = id ?? uuidV4();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.transaction(() async {
      final book = await _db
          .into(_db.books)
          .insertReturning(
            BooksCompanion.insert(
              id: bookId,
              name: name,
              createdAt: now,
              updatedAt: now,
              type: Value(type),
              currency: Value(currency),
              icon: Value(icon),
              color: Value(color),
              sortOrder: Value(sortOrder),
              ownerId: Value(ownerId),
            ),
          );

      final accounts = AccountRepository(_db);
      final categories = CategoryRepository(_db);
      await accounts.create(
        bookId: bookId,
        name: defaultAccountName,
        type: 'cash',
      );
      for (final preset in presetExpense) {
        await categories.create(
          bookId: bookId,
          name: preset,
          kind: 'expense',
          isPreset: true,
        );
      }
      for (final preset in presetIncome) {
        await categories.create(
          bookId: bookId,
          name: preset,
          kind: 'income',
          isPreset: true,
        );
      }
      return book;
    });
  }

  /// 按 id 取单个账本；[includeDeleted]=true 时可取已软删行。
  Future<Book?> getById(String id, {bool includeDeleted = false}) {
    final q = _db.select(_db.books)..where((t) => t.id.equals(id));
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    return q.getSingleOrNull();
  }

  /// 列出未删除账本。
  Future<List<Book>> listAll() {
    return (_db.select(_db.books)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  /// 局部更新。目标不存在或已删则抛错。
  Future<Book> update(
    String id, {
    String? name,
    String? type,
    String? currency,
    String? icon,
    String? color,
    int? sortOrder,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final changed = await (_db.update(_db.books)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(
          BooksCompanion(
            name: name == null ? const Value.absent() : Value(name),
            type: type == null ? const Value.absent() : Value(type),
            currency: currency == null ? const Value.absent() : Value(currency),
            icon: icon == null ? const Value.absent() : Value(icon),
            color: color == null ? const Value.absent() : Value(color),
            sortOrder: sortOrder == null
                ? const Value.absent()
                : Value(sortOrder),
            updatedAt: Value(now),
            dirty: const Value(1),
          ),
        );
    if (changed == 0) {
      throw StateError('books 未找到可更新的记录：$id');
    }
    final fresh = await getById(id);
    return fresh!;
  }

  /// 软删除。返回受影响行数。
  Future<int> softDelete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.books)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(
          BooksCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(1),
          ),
        );
  }

  /// 持久化的当前账本 id，从未设置过则 null。
  Future<String?> getActiveBookId() async {
    final row = await (_db.select(_db.schemaMeta)
          ..where((t) => t.key.equals(kActiveBookKey)))
        .getSingleOrNull();
    return row?.value;
  }

  /// 写当前账本 id（已存在则覆盖，走参数绑定，不做字符串拼 SQL）。
  Future<void> setActiveBookId(String id) {
    return _db
        .into(_db.schemaMeta)
        .insertOnConflictUpdate(
          SchemaMetaCompanion.insert(key: kActiveBookKey, value: id),
        );
  }

  /// 确保存在一个默认账本（首次启动调用）。已存在则直接返回第一个。
  Future<Book> ensureDefaultBook() async {
    final existing = await listAll();
    if (existing.isNotEmpty) return existing.first;
    return create(name: defaultBookName, icon: '📒', color: '#3b82f6');
  }
}
