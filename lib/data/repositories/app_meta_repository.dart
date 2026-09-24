/// 通用 KV 仓储：读写**已存在**的 `schema_meta` 表（`key` 主键 + `value`）。
///
/// PRD 已登记 `schema_meta` 为「KV 元数据（含 `active_book_id`）」，
/// `docs/SPEC-F7.3-budget.md` §3 也把「`schema_meta` KV」列为**零迁移**备选。
/// F7.7 D 批（搜索历史）复用它：SPEC §D.3 原计划新建 `app_meta` 表并把 schema
/// 推到 v4，实际**不需要动 schema**（少一次迁移 = 少一次覆盖安装风险）。
///
/// 只做纯 KV：不参与软删 / 同步元数据（`schema_meta` 表本来就没有这些列）。
library;

import '../../core/db/database.dart';

class AppMetaRepository {
  AppMetaRepository(this._db);

  final AppDatabase _db;

  /// 读一个 key；不存在返回 null。
  Future<String?> get(String key) async {
    final MetaEntry? row =
        await (_db.select(_db.schemaMeta)..where((t) => t.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  /// 写（存在即覆盖）。
  Future<void> set(String key, String value) async {
    await _db
        .into(_db.schemaMeta)
        .insertOnConflictUpdate(
          SchemaMetaCompanion.insert(key: key, value: value),
        );
  }

  /// 删一个 key；本来不存在也算成功。
  Future<void> remove(String key) async {
    await (_db.delete(_db.schemaMeta)..where((t) => t.key.equals(key))).go();
  }
}
