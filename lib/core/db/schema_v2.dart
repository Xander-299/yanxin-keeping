/// schema v2 新增部分：`budgets` 表的索引（drift 声明式表达不了部分唯一索引）。
///
/// ADR-9：索引一律走原始 SQL。ADR-8 约束的是 v1 五张表与旧库 DDL 一致 ——
/// v2 只是**新增**一张表，v1 的表结构与索引一字未改，老库升级只做「加表」。
library;

/// v2 的全部索引 DDL。
const kSchemaV2Indexes = <String>[
  // 一个账本 + 一个月份只能有一条未删除预算：重复设置走更新而不是插第二行。
  // 仅约束未删除行，这样「删掉本月预算再重设」不会被永久锁死
  // （与 idx_tx_fingerprint 同样的部分唯一索引思路）。
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_book_period '
      'ON budgets(book_id, period) '
      'WHERE deleted_at IS NULL',
];
