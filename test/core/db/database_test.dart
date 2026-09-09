import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/db/schema_v1.dart';

import '../../helpers/test_database.dart';

/// 从 sqlite_master 取对象名。
Future<Set<String>> _objects(AppDatabase db, String type) async {
  final rows = await db.customSelect(
    "SELECT name FROM sqlite_master WHERE type = '$type'",
  ).get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

void main() {
  group('AppDatabase schema v1', () {
    late AppDatabase db;

    setUp(() {
      db = openTestDatabase();
      addTearDown(db.close);
    });

    test('空库建出全部表 + schema_meta', () async {
      final tables = await _objects(db, 'table');
      expect(
        tables,
        containsAll(<String>[
          'books',
          'accounts',
          'categories',
          'transactions',
          'schema_meta',
        ]),
      );
    });

    test('索引与旧 DDL 一致（含 DESC 与指纹部分唯一索引）', () async {
      final indexes = await _objects(db, 'index');
      expect(
        indexes,
        containsAll(<String>[
          'idx_accounts_book',
          'idx_categories_book_kind',
          'idx_tx_book_occurred',
          'idx_tx_book_category',
          'idx_tx_account',
          'idx_tx_dirty',
          'idx_tx_fingerprint',
        ]),
      );

      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'idx_tx_fingerprint'",
          )
          .getSingle();
      expect(sql.read<String>('sql'), contains('UNIQUE'));
      expect(sql.read<String>('sql'), contains('deleted_at IS NULL'));

      final occurred = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'idx_tx_book_occurred'",
          )
          .getSingle();
      expect(occurred.read<String>('sql'), contains('DESC'));
    });

    test('schemaVersion 落库为 1（PRAGMA user_version）', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), 1);
    });

    test('建表/建索引 DDL 幂等：重复执行不报错且版本不变', () async {
      for (final sql in kSchemaV1Indexes) {
        await db.customStatement(sql);
      }
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), 1);
    });

    test('指纹部分唯一索引：同样指纹两条 → UNIQUE 冲突', () async {
      const fp = 'same-fingerprint';
      Future<void> insert(String id) => db.customStatement(
        'INSERT INTO transactions(id, book_id, account_id, type, amount_cents, '
        'occurred_at, created_at, updated_at, fingerprint) '
        "VALUES('$id','b1','a1','expense',100,1,1,1,'$fp')",
      );

      await insert('t1');
      expect(insert('t2'), throwsA(isA<sqlite.SqliteException>()));
    });

    test('指纹部分唯一索引：软删后可再写同指纹', () async {
      const fp = 'dup-after-delete';
      await db.customStatement(
        'INSERT INTO transactions(id, book_id, account_id, type, amount_cents, '
        'occurred_at, created_at, updated_at, fingerprint) '
        "VALUES('t1','b1','a1','expense',100,1,1,1,'$fp')",
      );
      await db.customStatement(
        "UPDATE transactions SET deleted_at = 9 WHERE id = 't1'",
      );
      await db.customStatement(
        'INSERT INTO transactions(id, book_id, account_id, type, amount_cents, '
        'occurred_at, created_at, updated_at, fingerprint) '
        "VALUES('t2','b1','a1','expense',100,1,1,1,'$fp')",
      );

      final rows = await db
          .customSelect(
            "SELECT id FROM transactions WHERE fingerprint = '$fp'",
          )
          .get();
      expect(rows.length, 2);
    });

    test('amount_cents 必为正（CHECK 约束生效）', () async {
      Future<void> insert(int cents) => db.customStatement(
        'INSERT INTO transactions(id, book_id, account_id, type, amount_cents, '
        'occurred_at, created_at, updated_at) '
        "VALUES('t$cents','b1','a1','expense',$cents,1,1,1)",
      );
      expect(insert(0), throwsA(isA<sqlite.SqliteException>()));
      expect(insert(-1), throwsA(isA<sqlite.SqliteException>()));
      await insert(1);
    });
  });
}
