/// 账户仓储（每个账本下若干账户，如现金 / 银行卡）。
///
/// 对应旧栈 `src/repositories/account-repository.js`：
/// 只做数据读写与字段校验，不含业务规则；删除一律软删除。
library;

import 'package:drift/drift.dart';

import '../../core/db/database.dart';
import '../../core/utils/id.dart';

class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  /// 新建账户。自动补 id / createdAt / updatedAt / dirty=1。
  Future<Account> create({
    required String bookId,
    required String name,
    String type = 'cash',
    int initialBalanceCents = 0,
    int sortOrder = 0,
    String? ownerId,
    String? id,
    String icon = '',
    String color = '',
  }) {
    if (bookId.isEmpty) {
      throw ArgumentError.value(bookId, 'bookId', 'account.bookId 为必填');
    }
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'account.name 为必填');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db
        .into(_db.accounts)
        .insertReturning(
          AccountsCompanion.insert(
            id: id ?? uuidV4(),
            bookId: bookId,
            name: name,
            createdAt: now,
            updatedAt: now,
            type: Value(type),
            initialBalanceCents: Value(initialBalanceCents),
            sortOrder: Value(sortOrder),
            ownerId: Value(ownerId),
            icon: Value(icon),
            color: Value(color),
          ),
        );
  }

  /// 按 id 取单个账户；[includeDeleted]=true 时可取已软删行。
  Future<Account?> getById(String id, {bool includeDeleted = false}) {
    final q = _db.select(_db.accounts)..where((t) => t.id.equals(id));
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    return q.getSingleOrNull();
  }

  /// 取某账本下所有未删除账户。
  Future<List<Account>> listByBook(String bookId) {
    return (_db.select(_db.accounts)
          ..where((t) => t.bookId.equals(bookId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  /// 局部更新。自动刷 updatedAt / dirty=1；目标不存在或已删则抛错。
  Future<Account> update(
    String id, {
    String? name,
    String? type,
    int? initialBalanceCents,
    int? sortOrder,
    String? icon,
    String? color,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final changed = await (_db.update(_db.accounts)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(
          AccountsCompanion(
            name: name == null ? const Value.absent() : Value(name),
            type: type == null ? const Value.absent() : Value(type),
            initialBalanceCents: initialBalanceCents == null
                ? const Value.absent()
                : Value(initialBalanceCents),
            sortOrder: sortOrder == null
                ? const Value.absent()
                : Value(sortOrder),
            icon: icon == null ? const Value.absent() : Value(icon),
            color: color == null ? const Value.absent() : Value(color),
            updatedAt: Value(now),
            dirty: const Value(1),
          ),
        );
    if (changed == 0) {
      throw StateError('accounts 未找到可更新的记录：$id');
    }
    final fresh = await getById(id);
    return fresh!;
  }

  /// 软删除：置 deleted_at，保留数据。返回受影响行数。
  Future<int> softDelete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.accounts)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .write(
          AccountsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(1),
          ),
        );
  }
}
