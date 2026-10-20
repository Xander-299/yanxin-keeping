# SPEC — F7.3 预算实装（小 SPEC，待签字）

> 状态：**待用户签字**（签字后才动产品代码）
> 起草：2026-09-12 · 关联：`HANDOFF.md` 未解决问题 #5、`tasks/todo-flutter.md` F7.3、首用验收 P2

---

## 1. 要解决的问题

首页预算卡（`budget_card_placeholder.dart`）是**写死的示例数据**：
「1,000.00 / 101.52 已消费 / 10.2% / 898.48 剩余」，与同屏 hero 的真实月支出**直接矛盾**。

首用验收 P2 的临时处置是加「示例」chip + 底部说明 —— 属于止损，不是功能。
本次把这张卡接上真实数据，并给用户一个**设置预算**的入口。

## 2. 目标（DoD）

1. 预算卡数字全部来自真实库数据，**移除「示例」chip 与说明文案**。
2. 用户能设置 / 修改 / 清除**某个月**的预算，重启 App 后仍在。
3. 未设置预算时，卡片显示**可操作的引导**（不是 0，也不是假数据）。
4. 超支时有明确反馈（进度变红 + 「已超支」）。
5. 门禁：`flutter analyze` 0 issue；`flutter test` 全绿（179 + 新增）。

## 3. 数据模型

### 方案 A（推荐）：独立 `budgets` 表 → schema **v2**

```sql
CREATE TABLE budgets (
  id           TEXT    PRIMARY KEY NOT NULL,
  book_id      TEXT    NOT NULL,
  period       TEXT    NOT NULL,              -- 'YYYY-MM'，字典序即时序
  amount_cents INTEGER NOT NULL,              -- 恒为正
  owner_id     TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  deleted_at   INTEGER,
  dirty        INTEGER NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX idx_budget_book_period
  ON budgets(book_id, period) WHERE deleted_at IS NULL;
```

- 与既有业务表**同构**（五件套同步元数据、软删、金额整数分、客户端 UUID v4 主键）→ 未来接云同步不需要返工。
- 逐月独立预算，可留历史、可给未来月份预设。
- **代价**：`schemaVersion 1 → 2`，需要 `onUpgrade`（`createTable` + 建索引），`database.g.dart` 重跑 `build_runner`。
  迁移只做「加表」，不动 v1 五张表 → 老库升级无数据风险（ADR-8 的 v1 DDL 一字不改）。
- 与日历页口径一致：**当月 = 真实当前月**，历史月可设（允许补记），未来月不限（`canGoNext` 只管翻月浏览）。

### 方案 B（备选，零迁移）：`schema_meta` KV

`key = 'budget.<bookId>'，value = 金额分`，只能存**一个当前生效的月预算**，无历史、无软删、无 `dirty`。
实现量约为 A 的 1/3，且完全不碰 DB schema；代价是「每月不同预算」和「未来同步预算」都要重做。
**适合只想要「一个月度总预算」的最简形态。**

> 两案的上层接口一致（`BudgetRepository.read(bookId, year, month)`），
> 若先上 B 再换 A，只需要重写 repo 一层 + 加迁移。

## 4. 计算口径（纯函数，可单测）

| 指标 | 口径 |
|---|---|
| 已消费 | 该月 `type = expense` 的 `amount_cents` 合计（**transfer / income 不计**，与 `summarize` 一致） |
| 预算进度 | `已消费 / 预算`，`clamp(0, 1)` 供环形绘制；文案显示**真实百分比**（可 > 100%） |
| 剩余额度 | `预算 - 已消费`（可为负 → 文案「已超支 ¥X」，颜色转红） |
| 本月日均消费 | `已消费 / 已过天数`：当月按「今天几号」，历史月按整月天数（**沿用日历页 `calendar_aggregate` 口径**，整数分四舍五入到分） |
| 剩余每日可消费 | `剩余额度 / 剩余天数`：当月 = `本月天数 - 今天 + 1`；历史月 = 显示「—」（月已结束，无意义）；超支时显示 0.00 并转红 |

- 金额展示沿用 `centsToYuan`（千分位 + 两位小数）。
- 除零保护：预算 ≤ 0 视为未设置。

## 5. 交互

1. **有预算**：卡内右上显示预算金额 + 编辑图标；点金额/图标/整卡 → 底部弹窗「设置本月预算」。
2. **无预算**：卡内显示「本月还未设置预算」+「设置预算」按钮（同一弹窗）。
3. **弹窗**：数字键盘输入金额（元）、常用额度快捷键（1000/2000/3000/5000）、
   「保存」（写入或更新）、有预算时显示「删除预算」（软删，回到未设置态）。
4. 月份跟随首页 hero 的翻月 —— 翻到 7 月就显示 / 设置 7 月的预算。
5. 保存后**只刷新预算卡**（不重查流水），并顺手 `statsProvider` 无关、无需联动。
6. 首页 `/record` 保存、删除流水的既有刷新链路里**补上预算刷新**（避免出现「记一笔后预算卡不更新」同类 bug）。

## 6. 文件清单（签字后按实际落库位置微调，与既有分层保持一致）

**新增**
- `lib/core/db/schema_v2.dart` — v2 索引原始 SQL（沿用 ADR-9：索引走原始 SQL）
- `lib/data/repositories/budget_repository.dart` — 与既有 4 个仓储同级
- `lib/features/ledger/application/budget_metrics.dart` — 纯函数（进度 / 日均 / 剩余每日）
- `lib/features/ledger/application/budget_controller.dart` — `monthBudgetProvider`
- `lib/features/ledger/presentation/widgets/budget_card.dart` — 替换 placeholder
- `lib/features/ledger/presentation/widgets/budget_edit_sheet.dart`
- `test/features/ledger/budget_metrics_test.dart` / `test/data/repositories/budget_repository_test.dart` /
  `test/features/ledger/budget_card_test.dart`（原占位卡的测试改为真实数据版）

**修改**
- `lib/core/db/tables.dart`（+`Budgets`）、`lib/core/db/database.dart`（`schemaVersion = 2` + `onUpgrade`）
- `lib/core/db/database.g.dart`（重新生成，一并提交）
- `lib/core/providers/database.dart`（+`budgetRepositoryProvider`）
- `lib/features/ledger/presentation/home_page.dart`（换用真实预算卡）
- `test/core/db/database_test.dart`（v2 断言 + **v1→v2 迁移回归**）
- `lib/features/ledger/presentation/widgets/budget_card_placeholder.dart` — **删除**
- 文档：`CHANGELOG.md` / `HANDOFF.md` / `tasks/todo-flutter.md` / `README.md`

> 落点说明：预算卡是**首页的卡**，所以计算/控制器/组件都放在 `features/ledger/` 下
> （与 `calendar_aggregate` 归属 `features/calendar/` 同理），不再单开 `features/budget/`。

## 7. 测试

| 层 | 用例要点 |
|---|---|
| `budget_metrics`（纯函数） | 正常 / 超支 / 未设置(0) / 当月按已过天数 / 历史月按整月 / 剩余天数含今天 / 跨年月末 |
| `budget_repository` | 写入→读取；同月重复设置走更新不产生第二行；软删后读取为空；换账本互不干扰 |
| widget | 未设置时显示引导且**无假数字**；设置后百分比与剩余额度正确；超支变红 + 「已超支」；点卡片弹出设置弹窗 |

## 8. 风险 / 取舍

- **schema 升级是本次最大风险点**：必须在真机 / 模拟器上验一条「从旧版本升级上来、老数据不丢」的路径
  （`flutter install --release` 不行，需 debug 包覆盖安装旧包后看首页数据仍在 + 预算可设）。
- 分类预算（每个分类一个额度）**本次不做**，留 F7.4。
- 预算提醒 / 推送**不做**（ADR-6：不接系统级提醒）。
- 移除「示例」chip 后，若用户从未设过预算，卡片必须有明确空态 + 引导，否则就是 P2 的另一面。

## 9. 工期切片（本次交付）

1. 数据层：表 + 迁移 + repo + 单测
2. 计算层：`budget_metrics` + 单测
3. UI：卡片 + 设置弹窗 + 接线 + widget 测试
4. 门禁 + 模拟器冒烟（升级路径 + 设置/超支/清除）+ 文档
