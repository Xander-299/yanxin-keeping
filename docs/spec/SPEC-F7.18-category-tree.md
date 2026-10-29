# SPEC — F7.18 分类树（两级分类 · 归档 · 迁移删除）

> 状态：**已实现（事后补档）** —— 本 SPEC 于实现与真机验收完成后补写，作为流程补档；
> 需求原文：**已存档至 [`docs/spec/prompts/2026-10-28-category-system-prompt.md`](prompts/2026-10-28-category-system-prompt.md)**
> （「为现有 Flutter 记账 App 实现完整的分类管理系统」，300 行）。
> ⚠️ 仓库根目录的 `Prompt.md` 只是**临时提示词暂存位**，内容会被下一次任务覆盖 ——
> 任何 SPEC 引用的需求原文都必须先存档进 `docs/spec/prompts/`（本文件即首个按此办理的）。
> 起草：2026-10-28 · 关联：`HANDOFF.md`（schema v4）、`CHANGELOG.md` 批次 11、提交 `823fc62`
> 门禁基线：`flutter analyze` 0 issue · `flutter test --concurrency=1` **665 passed / 6 skipped**
> **版本**：随下个发布 tag（当前最新 `v0.8.1`；本 SPEC 对应 schema **v4**，沿用 F7.14 起的
> 「SPEC 编号 ↔ 交付 tag」约定，交付时打 `v0.8.2` 或顺延）。
> **与其它 SPEC 的关系**：本 SPEC 不重复、不修改任何既有 SPEC 的需求 —— 只把
> `SPEC-local-assistant.md`（M1 问答）与导入（F5）里「按分类名」的**消费侧**标注为兼容不改
> （见 §6 关联表）。

---

## 0. 为什么事后补档

2026-10-28 用户以下发的分类管理任务书（现存档于 `prompts/2026-10-28-category-system-prompt.md`），明确要求「遇到不影响核心功能的小决策时，
采用合理的默认方案继续推进，不要频繁中断询问」，故按任务书直接实施，未先走 SPEC 签字。
本文把已交付内容回填到项目标准 SPEC 格式（模板：`SPEC-F7.3-budget.md`），供后续维护者查阅
决策依据；与实现的任何不一致，**以代码为准**并在 §9 记录偏差。

## 1. 要解决的问题

PRD §3.5 的 FR-CAT 只有扁平一层：预置 9+6 个分类，可改名/软删，没有层级、归档、迁移。
用户反馈「记账的分类太少了」——排查后确认是两件事：

1. **场景覆盖不全**：24 个真实生活场景没有对应分类；
2. **每次记账都要挑**：分类一多，扁平宫格的选择成本会先变好再变差。

同时历史数据安全是硬约束（任务书 §7）：被账单引用的分类**不允许物理删除**，
否则历史账单丢分类；预置分类的「补装」逻辑不能复活用户主动删掉的分类。

## 2. 目标（DoD）

> 格式对齐说明（2026-10-28）：按 `SPEC-F7.14` 惯例改为 **D1–D9 单列编号**，与原文 9 行表格一一对应。

- **D1** 分类管理页可真实操作：增/改/排序/归档/恢复/迁移 —— 验证：MuMu 全链路走查（§8）
- **D2** 收支类型隔离：记账页只列同方向分类 —— 验证：仓储测试 + UI 测试
- **D3** 两级封顶：`parentId` 只能指向一级；不许自挂/环 —— 验证：仓储测试 4 例
- **D4** 同级重名被拒，名称自动 trim —— 验证：仓储测试 3 例
- **D5** 排序持久化（同级上移/下移） —— 验证：仓储测试 + 重进页面核对
- **D6** 无引用可删；有引用只能归档或迁移；迁移只改 `category_id` —— 验证：仓储测试（金额/日期/备注/账户逐字段断言）
- **D7** 归档不出现在新账单选择器，历史账单照常显示 —— 验证：UI 测试 + 仓储测试
- **D8** schema v3→v4 迁移不丢数据 —— 验证：MuMu 老库实测 + 迁移测试
- **D9** 门禁全绿：analyze 0 issue、665 passed / 6 skipped

## 3. 需求 → 实现对照表

任务书共 9 章；关键条目落点如下（完整原文见 `prompts/2026-10-28-category-system-prompt.md`）：

| 任务书条目 | 实现 | 备注 |
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
| 删除交互 | 先查引用 → 三路分派（直接删/归档/迁移后删） | 任务书 §7 的硬要求；迁移文案带笔数 |
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

1. §2 的 **D1–D9** 全部有测试或真机证据；
2. 门禁：analyze 0 issue、全量测试绿；
3. 老库升级路径有真机证据（154 笔账单分毫未动）；
4. PRD §3.5 FR-CAT 表补齐 FR-CAT-03~08（两级/归档/迁移/图标颜色/排序/预置补齐）。

> 当前状态：**1–4 全部达成**（第 4 条已于 `ba9b202` 回填）。

## 11. 与现有 Spec 的关联（不重复、不越界）

| 既有 SPEC | 关联点 | 本 SPEC 的边界 |
|---|---|---|
| `SPEC-local-assistant.md`（M1 问答，已签字） | 问答案的 `categoryNames` 按 id 解析 | **消费侧兼容不改**：仍用 `category.name` 匹配；展示层「父 · 子」前缀见偏差 D5。M1 的需求一字未动 |
| `SPEC-local-ai.md`（F8 总路线，⏸ 已搁置） | 无直接耦合 | 分类树为未来「截图记账分类建议」提供更细粒度候选，但不在本 SPEC 范围内做任何承诺 |
| `SPEC-F7.4-search.md` / `SPEC-F7.5-search-overlay.md` | 搜索命中含「分类名」 | 命中语义保持原名匹配（不加前缀），行为不变 —— 对应 `Prompt.md` §5.9「检查统计口径」的结论 |
| `SPEC-F7.3-budget.md` | 预算按月、不按分类（FR-BUDGET-10 分类预算 ⛔ 待排期） | 本 SPEC **不实现**分类预算；二级分类计入父级后，未来做 FR-BUDGET-10 时口径已就绪 |
| `SPEC-F7.7-backlog.md` | — | 未从中认领/关闭任何条目 |

---

## 12. 交互迭代（2026-10-29）：Collapse / Wrap / ActionSheet

> 需求原文：[`prompts/2026-10-29-category-manage-ui.md`](prompts/2026-10-29-category-manage-ui.md)。
> **纯展示层改动**：数据模型（schema v4）、仓储规则、归档/迁移/删除流程一字未动。

### 12.1 需求 → 实现对照

| # | 需求 | 实现 |
|---|---|---|
| 1 | 一级分类 Collapse：点按在当前项下方内联展开/收起二级分类，带自然过渡 | `_CategoryGroup` 用 `AnimatedSize`（220ms / easeInOut）包二级区；点根分类 = 切换 `_expandedRoots`（页内 `Set<String>`，默认全收起）；根行加 `AnimatedRotation` 箭头指示状态 |
| 2 | 二级分类横向流式 `Wrap`，各自占宽、自动换行 | 二级区改 `_ChildChip`（图标 + 名字，自适应宽度）+ `Wrap(spacing: 8, runSpacing: 8)` |
| 3 | 三点溢出菜单 → ActionSheet 底部操作面板 | `_openActions`：`showModalBottomSheet`（grabber + 分类头 + 操作行）；一级含「添加子分类」，二级无；操作集合与旧 PopupMenu 完全一致（编辑/上移/下移/归档/删除 + 删除红色） |
| 4 | 保持业务逻辑 | 增删改归档迁移排序全部走原 `category_actions.dart`；无 DB / Repository 改动 |

### 12.2 关键决策

- **点按语义重分配**：有子分类的一级行，点按 = 折叠切换（编辑挪进 ActionSheet）；
  无子分类的一级行与二级 chip，点按 = 打开 ActionSheet（编辑的快捷路径不变少）。
- 折叠状态存**页内 state**，不落库 —— 展开偏好属会话级 UI 状态，进 DB 反而要清理。
- 迁移目标选择沿用已有的 `showModalBottomSheet` 风格，两处底部面板观感一致。

### 12.3 测试

- `category_manage_page_test.dart` 新增 2 例：Collapse 默认收起/展开/再收起；ActionSheet 弹出且「编辑」能进编辑弹层。
- 测试抓到并修掉一个真实问题：800×600 矮视口下 ActionSheet 底部溢出 73px → 面板内容包
  `SingleChildScrollView`（横屏 / 小屏可滚动）。
- 门禁实测（2026-10-29）：`flutter analyze` 0 issue（等效门禁脚本）·
  `flutter test --concurrency=1` **667 passed / 6 skipped**（基线 665，本批 +2）。

### 12.4 第二轮迭代（2026-10-29）：二级分类 Chip → 块状分类项

> 需求原文：[`prompts/2026-10-29-category-manage-ui-v2.md`](prompts/2026-10-29-category-manage-ui-v2.md)。
> 8 条要求中 #1 / #2 / #4 / #5 / #6 与 §12.1 首轮实现一致（TreeSelect 式纵向层级、Collapse、
> 子分类点击开 ActionSheet、三点 Overflow Action、三入口分离），本轮**唯一实质变化是 #3 的视觉形态**。

- `_ChildChip`（彩色胶囊）→ `_ChildBlock`：独立视觉块 —— 纸底（`p.canvas`）+ 发丝描边（`p.line`）+
  上下结构（分类色图标小方块 30×30 在上、名称在下，宽随内容，`minWidth: 76`），
  仍由 `Wrap(spacing: 8, runSpacing: 8)` 流式换行；分类色只保留在图标方块，不再铺满整块。
- 其余交互与业务逻辑零改动（无 DB / Repository 变更）。
- 测试：新增「二级分类块点击 → 打开该子分类的 ActionSheet（无『添加子分类』项）」1 例。
- 门禁实测：`flutter analyze` 0 issue · `flutter test --concurrency=1` **668 passed / 6 skipped**（+1）。

### 12.5 第三轮微调（2026-10-29）：「添加」块 + Collapse 全员展开

- 「添加子分类」从 ActionSheet 移出，改为**网格末尾的「添加」块**（`_AddBlock`，与
  `_ChildBlock` 同尺寸同描边，图标方块走中性底 + `+` 号），点击直接进编辑器并预置父分类；
- 每个一级分类因此**都可 Collapse**（含无子分类的根：展开后只有「添加」块），
  展开网格在视觉上对齐；根行点按 = 展开/收起，操作统一走 ⋯ ActionSheet；
- 测试：Collapse 用例扩为「展开见『添加』→ 收起 → 再展开 → 点『添加』进编辑器」；
  子分类 ActionSheet 用例补「面板无『添加子分类』」断言（修复一条误设的全树 `find` 断言）。
- 门禁实测：`flutter analyze` 0 issue · `flutter test --concurrency=1` **668 passed / 6 skipped**。

### 12.6 第四轮迭代（2026-10-29）：弹层尺寸 + 图标分层 + FloatButton 入口

> 需求原文：[`prompts/2026-10-29-category-manage-ui-v3.md`](prompts/2026-10-29-category-manage-ui-v3.md)。
> 仍是**纯展示层改动**：schema v4 / 仓储规则 / 归档·迁移·删除 / `category_actions.dart` 一字未动。

| # | 需求 | 实现 |
|---|---|---|
| 1 | 新建分类用 Bottom Sheet，占屏 **30%** | `showCategoryEditor` 外层 `SizedBox(height: 屏高 × 0.30)`（`kCategoryEditorHeightFactor`），内部三段式：抓手 + 标题固定 / `Expanded` 里滚表单 / 保存·取消钉底；键盘弹起时整块让出 `viewInsets.bottom` |
| 2 | 点图标后，图标选择也用 Bottom Sheet，占屏 **60%** | 新文件 `widgets/category_icon_sheet.dart`：`showCategoryIconSheet`，`SizedBox(height: 屏高 × 0.60)`。编辑层只留 48dp 图标预览（右下角铅笔暗示可点），点开才是 43 图标 + 9 颜色的网格 |
| 3 | 二级入口维持现状；另加一个一级入口，FloatButton / **右下角、屏高 15%** / 不可移动 / 圆形 / 加号 / trigger=click / 一级 F、二级 S | 新组件 `ToonFloatMenu`（`lib/core/theme/toon/float_button.dart`）；页面用 `Stack` + `Positioned(right:16, bottom: 屏高×0.15 − 28)` 覆盖在 Scaffold 外层（整屏坐标，滚动不动）；**贴底只能向上展开**（`expandUp: true`，主钮钉在 `Column` 末尾才不会随菜单长高而位移）；展开项 `F` = 添加一级分类、`S` = 添加二级分类（先选父分类再进编辑器）。展开网格末尾的「添加」块原样保留 |
| 4 | ActionSheet 改 `showModalBottomSheet`，内容用线性布局 `Column` | 操作面板**本来就是** `showModalBottomSheet` + `Column`（§12.1 #3）；本轮把剩下的两处 `ListView`（父分类选择、迁移目标）也统一成 `Column`，`ListTile` 换成自绘 `Row`（`_SheetTile` / `_SheetRow`），保证「所有底部面板 = 线性布局」 |

**关键决策**

- **颜色跟着图标走**：30% 的空间装不下「名称 + 类型 + 父分类 + 43 图标 + 9 颜色 + 按钮」，
  所以把 43 图标与 9 颜色一起放进 60% 的那一层（都是「外观」类选择，一次改完），
  编辑层只保留一块预览。若只搬图标，颜色会因没地方放而被迫删掉 —— 那是功能回退。
- **F / S 的语义**：任务书「一级用 F、二级用 S，依次类推」按**层级字母**落地 ——
  `ToonFloatAction.letter` 是「第几级」的标识（First/Second…），不是分类图标；
  二级入口先弹父分类选择，是为了让 S 与 F 有真实差异（否则两个入口行为完全一样）。
- **浮动按钮挂在 Scaffold 外面**：`Positioned` 的偏移要按**屏幕高度**算（不是 body 高度），
  所以页面根节点改成 `Stack(Scaffold, Positioned)`；`ToonFloatMenu` 内部自带一层
  `Material(type: transparency)`（Scaffold 外的 InkWell 找不到 Material 祖先会直接抛断言 —— 测试抓到过）。
- **位置口径（2026-10-29 用户订正）**：是「右下角、距屏幕底部 15%」，不是距顶 15%。
  圆心 = 屏高 × 0.85；贴底后菜单必须向上展开，所以 `ToonFloatMenu` 加了 `expandUp` ——
  向上展开时主钮放在 `Column` **末尾**，菜单长高只往上顶，主钮不会跟着往下走（向下展开那版实测会位移）。
- **30% 弹层的代价**：矮视口（横屏 / 800×600 测试视口）下表单区必须能滚，
  所以第一行（名称）常驻，第二行（类型 / 父分类）可能要滚一点；按钮钉底保证永远点得到。
- **已知取舍**：按钮固定在右下角，**必然会压住当前滚到那个高度的某一行的 ⋯**（实测首页视图里正好压住
  「教育」的 ⋯）。改位置只需动 `_kFloatBottomFactor`（`category_manage_page.dart` 顶部常量）。

**测试**

- 新增 `test/features/category/category_sheets_test.dart` 3 例：
  ① 编辑层实测 `屏高 × 0.30`、图标层实测 `屏高 × 0.60`，选完图标关层后编辑层仍在；
  ② 浮动按钮圆心在 `屏高 × 0.15`、列表滚动后位置不变、点按展开 `F`/`S` 且一级入口直接进编辑层；
  ③ S 入口选「餐饮」后新建的「美式」在库里 `parentId == 餐饮.id`。
- 门禁实测（2026-10-29）：`flutter analyze` 0 issue ·
  `flutter test --concurrency=1` **671 passed / 6 skipped**（基线 668，本批 +3）。

### 12.7 设备走查（2026-10-29 · MuMu 12 / Android 12 / 900×1600 @2x = 450×800 dp）

debug 包（`qaAppId=com.teacodeman.yanxin.qa`，装完 `android/` 零改动），语义树用
`tool/ui_mumu.ps1`，像素判读用 Pillow 扫截图（本机模型看不了图，改用「彩色行区段」判定）。

| 检查点 | 实测（设备 px，÷2 = dp） |
|---|---|
| 浮动按钮位置 | 语义节点 `[756,1304][868,1416]` → 圆心 `(812,1360)` = **680 dp = 屏高 800 的 85%，即右下角距底 15%**；列表连滚 11 次后坐标一字不变（不可移动） |
| 展开方式 | 初始无子项；点一次才出现「添加一级分类 **F**」（`1084–1168`）「添加二级分类 **S**」（`1184–1268`），**都在主钮上方**；展开后主钮仍在 `1304–1416`，没有被推下去 |
| 编辑层占屏 | 遮罩止于 `y=1120` → 面板顶 = 1600×0.70，**正好 30%**；标题 / 图标预览 / 支出·收入 / 父分类 / 取消·保存 全在面板内，`logcat` 无 overflow |
| 图标层占屏 | 遮罩止于 `y=640` → **60%**；图标区可单独滚动（前后截图差异 19.2 万像素），颜色行固定在 `1508–1575` 不动 |
| ActionSheet | 编辑 / 上移 / 下移 / 归档 / 删除 五行，行高 48 dp、整行可点（`Column` 线性布局） |
| F 入口 | 直接进新建层；输入 `coffee` 保存后出现在列表末尾，与原有 ghost 按钮、网格「添加」块并存 |
| S 入口 | 「挂到哪个一级分类下？」→ 选「餐饮」→ 编辑层父分类显示「餐饮」 |
| 编辑路径 | ⋯ → 编辑：30% 面板、标题「编辑分类」、无收支类型分段（方向不可改）、父分类行满宽 |

**设备上抓到并修掉的问题（单测与 mock 视口都看不见）**：
60% 图标层最初把「图标网格 + 颜色」放进同一个滚动区，43 个图标把颜色行顶到 `1532–1599`
（贴着屏幕最底边、没有留白），看起来像「没有颜色可选」。改成**图标区自己滚 + 颜色行钉底 + 发丝分割线**后
颜色行稳定在 `1508–1575`，下方留 25 px 空白。

**已知残留**：浮动按钮是覆盖层，**压住当前滚到那个高度的某一行的 ⋯ 是固有的**
（本轮实测压住「教育」那张卡的 ⋯；滚动即换一张）。要避让就改 `_kFloatBottomFactor` 或换边。

---

## 13. 预置二级分类（2026-10-29）

> 需求原文：[`prompts/2026-10-29-preset-subcategories.md`](prompts/2026-10-29-preset-subcategories.md)。
> 只动**预置数据 + 补装逻辑 + 问答口径**；**schema 仍是 v4，没有迁移**，老库升级零风险。

### 13.1 需求 → 实现

| 需求 | 实现 |
|---|---|
| 给预置一级分类补二级（餐饮 → 早餐/午餐/晚餐，交通 → 地铁/公交/共享单车…） | `core/constants/preset.dart`：`PresetCategory.children`（`PresetChild`），**10 个支出一级带二级、共 33 条**；收入与「其他」刻意不带（见 13.3） |
| 新建账本要带上二级 | `BookRepository.create()` 不再自己遍历预置表，直接复用 `CategoryRepository.ensurePresets()` —— **预置只有一处写入逻辑**，新账本与老账本补装不会再长歪 |
| 老账本也要补上 | `ensurePresets()` 重写：一级命中就顺手补它的二级，逐条幂等 |
| 二级能看到的图标 | `kCategoryIcons` **追加** 3 个 key：`dinner` / `bus` / `bike`（目录 41 → **44** 个 key；只追加、不改名，符合「key 一经发布不可变」） |

### 13.2 二级清单（支出侧）

| 一级 | 二级 |
|---|---|
| 餐饮 | 早餐 / 午餐 / 晚餐 / 饮料 / 零食 |
| 交通 | 地铁 / 公交 / 打车 / 共享单车 / 加油 |
| 购物 | 服饰 / 数码 / 日用品 |
| 居住 | 房租 / 水电燃气 / 家居 |
| 娱乐 | 电影 / 游戏 / 健身 |
| 医疗 | 门诊 / 药品 / 体检 |
| 教育 | 学费 / 书籍 / 培训 |
| 人情社交 | 送礼 / 请客 / 红包 |
| 旅行 | 机票 / 住宿 / 门票 |
| 通讯 | 话费 / 宽带 |
| 其他 | **无**（它就是兜底，再分下去就失去兜底意义） |

二级沿用一级的颜色（`color = 父级 color`），视觉上成组；`is_preset=1`，可改名/归档/删除，删除后不会被补装复活。

### 13.3 补装规则（这是本轮最容易出 bug 的地方）

- **匹配口径按父级分开**：一级只在 `parent_id IS NULL` 的行里找（同名或别名）；二级只在**同一个 `parent_id`** 下找。
  （旧实现用一个全局 `kind|name` 集合，加了二级之后会互相串味：一级「红包礼金」的别名与二级「红包」同名。）
- **父级被用户软删 → 整棵树都不补**，不给已删父级塞子分类。
- **软删行仍在匹配集合里**（F7.18 的老规矩：删掉的预置不复活）。
- 已存在但 icon 为空时只补空值（用户改过的图标不覆盖）。

### 13.4 加二级后暴露并修掉的真 bug：问答漏算子分类

`finance_answer._categorySpending` 原来按**分类名精确匹配**切片，于是「这个月餐饮花了多少」
只会统计直接记在「餐饮」上的钱，记在「早餐 / 午餐 / 晚餐」上的一分不算 —— 而首页示例问题
第一屏就有「这个月餐饮花了多少」。

- 修法：`FinanceData` 增加 `categoryParents`（二级 id → 父级 id），汇总口径改成
  **「自己命中」或「父级命中」**；问「早餐」时只算早餐自身，不会倒推整个餐饮。
- 回归：`test/features/assistant/finance_answer_test.dart` +2 例（父级合计含二级 / 二级只算自己）。

### 13.5 已知取舍（写进 HANDOFF 的 open-issues，等用户拍板）

1. **记账多一次点击**：一级有子分类后，点「餐饮」会进子列表，要记在一级上得再点「餐饮（不细分）」。
   这是「有二级」的必然代价；嫌慢可考虑长按直接选一级。
2. **改名不会阻止补装**：预置没有 `preset_key` 列，用户把「早餐」改成「早饭」后，补装会再插一条「早餐」。
   根治要加列（schema v5），本轮不动。
3. **统计 / 报表的分母**：饼图与报表按「父 · 子」**分开列**（F7.18 的既定展示），
   而编辑层文案写的是「二级分类会计入父分类的统计」—— 只有问答按父级汇总了。
   两条口径要不要统一，属产品决策。
4. **导入规则仍只到一级**：`category_rules.dart` 里「地铁 / 公交 / 单车」关键词仍落到「交通」，
   没有自动落到对应二级。改它会改变既有导入结果，需用户确认后再动。

### 13.6 测试与门禁

- `category_repository_test`：预置结构（11 一级 / 33 二级 / 点名两条）、老账本只补二级且正常、
  一级被删不补装、软删不复活（改为先删子分类再删父级，符合「有子分类不能直接删」的规则）。
- 新增 `test/helpers/pick_category.dart`：`pickCategory()` 处理「点一级 → 若进子列表再点不细分」，
  `widget_test` / 记账页 / 日历页三处改用（否则那些用例会停在子列表上、保存出没有分类的账单）。
- 门禁实测（2026-10-29）：`flutter analyze` 0 issue ·
  `flutter test --concurrency=1` **675 passed / 6 skipped**（基线 671，本批 +4）。
- **本轮没有做真机走查**（用户明确要求先不做）。


