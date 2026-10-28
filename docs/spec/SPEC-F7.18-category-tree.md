# SPEC — F7.18 分类树（两级分类 · 归档 · 迁移删除）

> 状态：**已实现（事后补档）** —— 本 SPEC 于实现与真机验收完成后补写，作为流程补档；
> 需求原文：仓库根目录 `Prompt.md`（「为现有 Flutter 记账 App 实现完整的分类管理系统」，2026-10-28 10:16 版，300 行）。
> 起草：2026-10-28 · 关联：`HANDOFF.md`（schema v4）、`CHANGELOG.md` 批次 11、提交 `823fc62`
> 门禁基线：`flutter analyze` 0 issue · `flutter test --concurrency=1` **665 passed / 6 skipped**

---

## 0. 为什么事后补档

2026-10-28 用户以 `Prompt.md` 形式下达分类管理需求，明确要求「遇到不影响核心功能的小决策时，
采用合理的默认方案继续推进，不要频繁中断询问」，故按任务书直接实施，未先走 SPEC 签字。
本文把已交付内容回填到项目标准 SPEC 格式（模板：`SPEC-F7.3-budget.md`），供后续维护者查阅
决策依据；与实现的任何不一致，**以代码为准**并在 §9 记录偏差。

## 1. 要解决的问题

PRD §3.5 的 FR-CAT 只有扁平一层：预置 9+6 个分类，可改名/软删，没有层级、归档、迁移。
用户反馈「记账的分类太少了」——排查后确认是两件事：

1. **场景覆盖不全**：24 个真实生活场景没有对应分类；
2. **每次记账都要挑**：分类一多，扁平宫格的选择成本会先变好再变差。

同时历史数据安全是硬约束（`Prompt.md` §7）：被账单引用的分类**不允许物理删除**，
否则历史账单丢分类；预置分类的「补装」逻辑不能复活用户主动删掉的分类。

## 2. 目标（DoD）

对照 `Prompt.md` §九「完成标准」逐条落成可验证的 DoD：

| # | DoD | 验证 |
|---|---|---|
| 1 | 分类管理页可真实操作：增/改/排序/归档/恢复/迁移 | MuMu 全链路走查（§8） |
| 2 | 收支类型隔离：记账页只列同方向分类 | 仓储测试 + UI 测试 |
| 3 | 两级封顶：`parentId` 只能指向一级；不许自挂/环 | 仓储测试 4 例 |
| 4 | 同级重名被拒，名称自动 trim | 仓储测试 3 例 |
| 5 | 排序持久化（同级上移/下移） | 仓储测试 + 重进页面核对 |
| 6 | 无引用可删；有引用只能归档或迁移；迁移只改 `category_id` | 仓储测试（金额/日期/备注/账户逐字段断言） |
| 7 | 归档不出现在新账单选择器，历史账单照常显示 | UI 测试 + 仓储测试 |
| 8 | schema v3→v4 迁移不丢数据 | MuMu 老库实测 + 迁移测试 |
| 9 | 门禁全绿 | 665 passed / 6 skipped |

## 3. 需求 → 实现对照表

`Prompt.md` 共 9 章；关键条目落点如下（完整原文见 `Prompt.md`）：

| Prompt.md 条目 | 实现 | 备注 |
|---|---|---|
| §2.1 默认分类清单（11 支出 + 7 收入） | `core/constants/preset.dart` `PresetCategory` | **偏差 D1**：「其他支出/其他收入」沿用既有名「其他」 |
| §2.1 图标/颜色/排序 | `core/constants/category_icons.dart` 43 个稳定 key + 9 色 | key 一经发布不可改名，只能追加 |
| §2.1 只在首次初始化创建 | `BookRepository.create()` 写一次 | 老账本由 `ensurePresets()` 幂等补齐 |
| §2.2 两级树、二级可选 | `categories.parent_id` + `CategoryRepository` 校验 | **偏差 D2**：见 §9 |
| §2.3 管理页布局 | `category_manage_page.dart` | 排序用上移/下移，**偏差 D3**：见 §9 |
| §2.4 字段校验 | `CategoryException`（中文文案直接可展示） | |
| §2.5 稳定 icon key + 整数颜色 | `kCategoryIcons` / `parseHexColor` | 明确禁用 `IconData.hashCode`（注释写明原因） |
| §2.6 拖拽或上移下移 | 上移/下移 | **偏差 D3** |
| §2.7 删除/归档/迁移三选 | `deleteIfUnused` / `archive` / `migrateAndDelete`（事务） | 迁移连子分类账单一起迁 |
| §3 数据模型 10 字段 | `categories` 表 v4 | id/name/kind/parentId/icon/color/sortOrder/isPreset(=isSystem)/isArchived/createdAt/updatedAt |
| §3 迁移不丢数据 | **只加列 + 加索引**，既有行零改动 | 升级时按名字回填 icon key（只写空值） |
| §3 按 ID 关联、不按名称 | 既有 `transactions.category_id` 不变 | |
| §5 记账集成 10 条 | `category_picker.dart` 两级钻取 | 子级列表含「XX（不细分）」兜底 |
| §5 统计一致性 | `categoryNameMap()`：二级显示「父 · 子」 | 搜索/问答仍用原名匹配（语义不同） |

## 4. 数据模型（schema v4）

```sql
-- 只加两列（ALTER TABLE ADD COLUMN），不改任何既有行
ALTER TABLE categories ADD COLUMN parent_id TEXT NULL;      -- NULL = 一级
ALTER TABLE categories ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;

-- 两条索引（ADR-9：索引一律原始 SQL）
CREATE INDEX idx_categories_book_kind_parent
  ON categories(book_id, kind, parent_id);                  -- 树查询主路径
CREATE INDEX idx_categories_book_archived_sort
  ON categories(book_id, is_archived, sort_order);          -- 选择器过滤 + 排序
```

- `schemaVersion 3 → 4`（`core/db/database.dart`）；`onUpgrade(from<4)` 防御半迁移态
  （`_columnExists` 判重），与 v2/v3 迁移同构；
- 升级时 `_backfillCategoryIcons()` 按「分类名 + 老别名（理财/红包/人情）」回填 icon key，
  **只写 `icon` 为空的行** —— 用户改过的图标不覆盖；
- 预置补齐 `ensurePresets(bookId)`：命中「同名或别名」不重复插；**连软删行一起查**
  （真机踩坑：见 §9 偏差 D4）。

## 5. 架构落点

```
lib/
├─ core/constants/
│  ├─ preset.dart                  # PresetCategory（name/iconKey/color/aliases）
│  └─ category_icons.dart          # key→IconData、颜色目录、parseHexColor
├─ core/db/
│  ├─ tables.dart                  # Categories +parent_id +is_archived
│  ├─ schema_v4.dart               # 索引 DDL
│  └─ database.dart                # v3→v4 迁移 + 图标回填
├─ data/repositories/
│  └─ category_repository.dart     # 全量重写：树/校验/归档/迁移/引用计数
├─ data/providers/
│  └─ category_providers.dart      # categoriesProvider（含归档）+ categoriesByKindProvider（排除归档）
│                                  # + categoryDisplayName / categoryNameMap
└─ features/category/
   ├─ application/category_actions.dart   # 写操作收口（invalidate 刷新）
   └─ presentation/
      ├─ category_manage_page.dart        # 管理页
      └─ widgets/category_editor.dart     # 新建/编辑弹层
```

**两个 provider 口径**（这是最容易踩的坑，写死在注释里）：
`categoriesProvider` **含归档**（历史账单/统计/报表/搜索要解析名字）；
`categoriesByKindProvider` **排除归档**（记账选择器/导入映射）。

## 6. 关键决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| 「其他支出」改名？ | **不改**，沿用「其他」 | 老账本已有「其他」，改名会出现两个「其他」；`(kind,name)` 才是唯一口径 |
| 老账本老名字 | 别名映射（理财→投资收益、红包→红包礼金、人情→人情社交） | 命中别名就不插新行，避免同义分类并存 |
| 删除交互 | 先查引用 → 三路分派（直接删/归档/迁移后删） | `Prompt.md` §7 的硬要求；迁移文案带笔数 |
| 二级预算/统计 | 二级计入父分类（标签「父 · 子」），不单列 | 一级口径不变，报表兼容 |
| 排序交互 | 上移/下移 | 见偏差 D3 |

## 7. 测试

新增/重写 24 例：

- `test/data/repositories/category_repository_test.dart`（21 例）：预置数量与图标、
  ensurePresets 幂等 / 别名命中 / **软删不复活**、两级校验 4 例、名称校验 4 例、
  改名改图标、reorder 持久化、删除三路、归档连带子分类、迁移逐字段不变断言、跨类型迁移拒绝、
  有子分类不许删（不留孤儿）；
- `test/features/category/category_manage_page_test.dart`（3 例）：收支 Tab 隔离、
  归档→恢复、记账选择器（归档不可见 + 钻取回填）；
- 受影响老测试同步修正：`database_test`（user_version 3→4）、`book_repository_test`
  （预置 15→18）、chat/budget/search 测试改用 `test/helpers/category_seed.dart`
  `ensureCategory()`（v4 同级禁重名后，`create(name:'餐饮')` 会撞预置）。

## 8. 真机验收

详见 `docs/acceptance-F7.18-category-tree.md`（MuMu 12 / 900×1600）。

## 9. 实施记录与偏差

| # | 偏差 | 原因 |
|---|---|---|
| D1 | 「其他支出/其他收入」→ 沿用「其他」 | 见 §6；老数据兼容优先于命名建议 |
| D2 | 编辑弹层支持「改父分类」（Prompt 只要求新增时选父级） | 补齐「提为一级/挂到别的一级」能力，校验与新增同源 |
| D3 | 排序用**上移/下移**而非拖拽 | 两级树里嵌套拖拽的落点容易跨层级；任务书 §2.6 明确允许此替代 |
| D4 | ensurePresets 补「连软删行一起查」 | **真机实测踩到**：删预置「购物」3 秒后复活；修复 + 回归测试 |
| D5 | 图例/统计标签「父 · 子」前缀只用于展示 | 搜索/问答仍用原名匹配，加前缀会改变匹配语义 |

## 10. 验收标准（本 SPEC 的 done 定义）

1. §2 的 9 条 DoD 全部有测试或真机证据；
2. 门禁：analyze 0 issue、全量测试绿；
3. 老库升级路径有真机证据（154 笔账单分毫未动）；
4. PRD §3.5 FR-CAT 表补齐 FR-CAT-03~08（两级/归档/迁移/图标颜色/排序/预置补齐）。

> 当前状态：1–3 已达成；第 4 条（PRD 回填）待办。
