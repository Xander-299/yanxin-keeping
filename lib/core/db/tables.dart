/// drift 表定义（schema v1）。
///
/// 与旧栈 `src/db/schema.js` 一一对应，ADR-8 要求 DDL 一致：
/// - 所有业务表带同步元数据五件套 id / owner_id / created_at / updated_at / deleted_at / dirty
/// - 永不物理删除，deleted_at 非空即已删
/// - 金额整数分（_cents），时间毫秒 epoch（_at）
/// - 声明顺序 = 旧 DDL 字段顺序
///
/// 索引不在这里声明（drift 不支持 DESC / 部分索引），见 schema_v1.dart。
library;

import 'package:drift/drift.dart';

/// 版本元信息表（迁移状态 + active_book_id 等 KV 持久化）。
@DataClassName('MetaEntry')
class SchemaMeta extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 账本。
class Books extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get type => text().withDefault(const Constant('personal'))();

  TextColumn get currency => text().withDefault(const Constant('CNY'))();

  TextColumn get icon => text().withDefault(const Constant(''))();

  TextColumn get color => text().withDefault(const Constant(''))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get ownerId => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  IntColumn get deletedAt => integer().nullable()();

  IntColumn get dirty => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 账户（每个账本下若干账户，如现金 / 银行卡）。
class Accounts extends Table {
  TextColumn get id => text()();

  TextColumn get bookId => text()();

  TextColumn get name => text()();

  TextColumn get type => text().withDefault(const Constant('cash'))();

  IntColumn get initialBalanceCents =>
      integer().withDefault(const Constant(0))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get ownerId => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  IntColumn get deletedAt => integer().nullable()();

  IntColumn get dirty => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 分类（预置分类 is_preset=1 不可删）。
class Categories extends Table {
  TextColumn get id => text()();

  TextColumn get bookId => text()();

  TextColumn get name => text()();

  /// expense | income
  TextColumn get kind => text()();

  TextColumn get icon => text().withDefault(const Constant(''))();

  TextColumn get color => text().withDefault(const Constant(''))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get isPreset => integer().withDefault(const Constant(0))();

  TextColumn get ownerId => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  IntColumn get deletedAt => integer().nullable()();

  IntColumn get dirty => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 流水。数据类名 `TxRow`：避免与 drift 自带的 `Transaction` 冲突。
@DataClassName('TxRow')
class Transactions extends Table {
  TextColumn get id => text()();

  TextColumn get bookId => text()();

  TextColumn get accountId => text()();

  /// transfer 类型时为 NULL。
  TextColumn get categoryId => text().nullable()();

  /// expense | income | transfer
  TextColumn get type => text()();

  /// 恒为正，方向由 type 决定。
  IntColumn get amountCents => integer()();

  TextColumn get note => text().withDefault(const Constant(''))();

  /// 业务发生时间（用户可改）。
  IntColumn get occurredAt => integer()();

  /// 预留：转账成对关联。
  TextColumn get transferGroupId => text().nullable()();

  /// manual|wechat_csv|alipay_csv|notification|shortcut
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// 入账指纹，防重复。
  TextColumn get fingerprint => text().nullable()();

  TextColumn get ownerId => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  IntColumn get deletedAt => integer().nullable()();

  IntColumn get dirty => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  /// 旧 DDL 的行内 CHECK，drift 只能放到表级（语义等价）。
  @override
  List<String> get customConstraints => ['CHECK (amount_cents > 0)'];
}
