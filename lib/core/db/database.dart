/// drift 数据库入口（schema **v3**）。
///
/// 版本号由 drift 托管（写进 `PRAGMA user_version`）；`schema_meta` 表保留
/// 用于 KV 持久化（如 active_book_id），与旧栈 DDL 一致（ADR-8）。
///
/// v1 → v2 只做**加表**：新增 `budgets`（月度预算）+ 一条部分唯一索引。
/// v1 的 5 张表结构与 7 条索引一字未改，老库升级不触碰任何既有数据。
///
/// v2 → v3 只做**加列**：`accounts.icon` / `accounts.color`（TEXT NOT NULL
/// DEFAULT ''，F7.7 C 批账户自选图标 / 颜色）。空串 = 跟随账户类型；
/// 老库升级走 `ALTER TABLE ADD COLUMN`，不改任何既有行。
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'schema_v1.dart';
import 'schema_v2.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [SchemaMeta, Books, Accounts, Categories, Transactions, Budgets],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // drift 声明式建表表达不了 DESC / 部分索引 → 索引走原始 SQL，
          // 保证与旧库 v1 完全一致（ADR-8）。
          for (final sql in kSchemaV1Indexes) {
            await customStatement(sql);
          }
          for (final sql in kSchemaV2Indexes) {
            await customStatement(sql);
          }
        },
        onUpgrade: (m, int from, int to) async {
          if (from < 2) {
            // 只加表：不动 v1 五张表，老库数据零风险。
            await m.createTable(budgets);
            for (final sql in kSchemaV2Indexes) {
              await customStatement(sql);
            }
          }
          if (from < 3) {
            // 只加列：带 DEFAULT ''，不改任何既有行（零数据风险）。
            // 防御半迁移态（如 v1→v2 升级中断后重试）：列已存在则跳过。
            if (!await _columnExists('accounts', 'icon')) {
              await m.addColumn(accounts, accounts.icon);
            }
            if (!await _columnExists('accounts', 'color')) {
              await m.addColumn(accounts, accounts.color);
            }
          }
        },
      );

  /// 查某表是否已有某列（PRAGMA table_info）。
  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }
}

/// App 侧默认打开方式：数据落在应用数据目录 `yanxin.sqlite`。
///
/// drift_flutter 负责在 Android 上带上 sqlite3 native 库。
AppDatabase openAppDatabase() => AppDatabase(driftDatabase(name: 'yanxin'));
