/// 分类仓储。预置分类 is_preset=1 不可删、不物理删。
///
/// 对应旧栈 `src/repositories/category-repository.js`。
library;

import 'package:drift/drift.dart';

import '../../core/db/database.dart';
import '../../core/utils/id.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  /// 新建分类。kind 必须为 expense | income。
  Future<Category> create({
    required String bookId,
    required String name,
    required String kind,
    String icon = '',
    String color = '',
    int sortOrder = 0,
    bool isPreset = false,
    String? ownerId,
    String? id,
  }) {
    if (bookId.isEmpty) {
      throw ArgumentError.value(bookId, 'bookId', 'category.bookId 为必填');
    }
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'category.name 为必填');
    }
    if (kind != 'expense' && kind != 'income') {
      throw ArgumentError.value(kind, 'kind', '必须为 expense 或 income');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db
        .into(_db.categories)
        .insertReturning(
          CategoriesCompanion.insert(
            id: id ?? uuidV4(),
            bookId: bookId,
            name: name,
            kind: kind,
            createdAt: now,
            updatedAt: now,
            icon: Value(icon),
            color: Value(color),
            sortOrder: Value(sortOrder),
            isPreset: Value(isPreset ? 1 : 0),
            ownerId: Value(ownerId),
          ),
        );
  }

  /// 按 id 取单个分类；[includeDeleted]=true 时可取已软删行。
  Future<Category?> getById(String id, {bool includeDeleted = false}) {
    final q = _db.select(_db.categories)..where((t) => t.id.equals(id));
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    return q.getSingleOrNull();
  }

  /// 按账本（可选 kind）列出未删除分类。
  Future<List<Category>> listByBook(String bookId, {String? kind}) {
    final q = _db.select(_db.categories)
      ..where((t) => t.bookId.equals(bookId) & t.deletedAt.isNull());
    if (kind != null) {
      q.where((t) => t.kind.equals(kind));
    }
    q.orderBy([
      (t) => OrderingTerm.asc(t.sortOrder),
      (t) => OrderingTerm.asc(t.createdAt),
    ]);
    return q.get();
  }

  /// 局部更新（改名 / 改图标等）。目标不存在或已删则抛错。
  Future<Category> update(
    String id, {
    String? name,
    String? icon,
    String? color,
    int? sortOrder,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final changed = await (_db.update(_db.categories)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(
          CategoriesCompanion(
            name: name == null ? const Value.absent() : Value(name),
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
      throw StateError('categories 未找到可更新的记录：$id');
    }
    final fresh = await getById(id);
    return fresh!;
  }

  /// 软删除。预置分类不可删除。返回受影响行数。
  Future<int> softDelete(String id) async {
    final cat = await getById(id);
    if (cat != null && cat.isPreset == 1) {
      throw StateError('预置分类不可删除');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.categories)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(
          CategoriesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(1),
          ),
        );
  }
}
