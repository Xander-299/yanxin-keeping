/// schema v4 新增部分：分类两级 + 归档（`categories.parent_id` / `is_archived`）。
///
/// 迁移策略（与 v2/v3 一致：**只加列 / 只加索引，不改任何既有行**）：
/// - `parent_id TEXT NULL`、`is_archived INTEGER NOT NULL DEFAULT 0` 走 `ALTER TABLE ADD COLUMN`；
/// - 老数据的 `icon` 是空串（v3 之前没被使用），迁移按**分类名**回填稳定 icon key，
///   这一步只更新 `icon`（空串才写），不碰名称/颜色/排序。
library;

/// v4 的全部索引 DDL（ADR-9：索引一律原始 SQL）。
const kSchemaV4Indexes = <String>[
  // 分类树按「账本 + 收支方向 + 父级」查询（分类管理页、记账页选择器都走这条）。
  'CREATE INDEX IF NOT EXISTS idx_categories_book_kind_parent '
      'ON categories(book_id, kind, parent_id)',
  // 归档过滤 + 排序：`WHERE deleted_at IS NULL AND is_archived = 0 ORDER BY sort_order`。
  'CREATE INDEX IF NOT EXISTS idx_categories_book_archived_sort '
      'ON categories(book_id, is_archived, sort_order)',
];
