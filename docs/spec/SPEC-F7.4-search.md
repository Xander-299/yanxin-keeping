# SPEC — F7.4 流水搜索（已签字）

> 状态：**已签字**（2026-09-12，用户确认三个待定项后开工）
> 起草：2026-09-12 · 关联：`HANDOFF.md` 未解决问题 #5、`tasks/todo-flutter.md` F7.4、首页 header 搜索图标占位
> 用户需求（原话）：**「搜索功能我需要它能够实现搜索分类、备注、金额，输入框能一键清空」**
>
> 签字结论：**Q1 当前账本·全部时间** / **Q2 金额子串匹配** / **Q3 附带项（账户名匹配、关键词高亮）本次不做**

---

## 1. 要解决的问题

首页 header 的搜索图标目前是占位（点了弹「功能建设中，敬请期待」）。用户想找一笔账时，
只能按月翻日历 / 首页逐月翻，**没有任何跨时间的检索手段**——账记得越多越难受。

本次交付：一个能按**分类名 / 备注 / 金额**检索当前账本全部流水的搜索页，输入框带一键清空。

## 2. 目标（DoD）

1. 首页 header 搜索图标 → 进 `/search` 全屏搜索页（不再是「建设中」toast）。
2. 输入关键词即时出结果，命中**分类名 / 备注 / 金额**三类字段中任意一个。
3. 输入框右侧有**一键清空**按钮：有输入才出现，点一下清空并回到初始引导态（保持焦点可继续输入）。
4. 结果按天分组倒序展示，顶部给「共 N 笔 · 支出 X · 收入 Y」汇总；结果条目可点（编辑）/ 长按（删除），
   与首页行为一致。
5. 三种状态都有明确反馈：**未输入**（引导）、**无结果**（回显关键词 + 清空入口）、**有结果**（列表 + 汇总）。
6. 门禁：`flutter analyze` 0 issue；`flutter test` 全绿（199 + 新增）。

## 3. 数据与口径

### 3.1 取数

- 范围：**当前账本**（与首页/日历/统计一致的 `activeBookIdProvider`）**全部时间**、未软删流水，
  按 `occurred_at` 倒序。
- 新增仓储方法 `TransactionRepository.listByBook(bookId)`（现有的 `listByMonth` / `listByYear` /
  `listByRange` 都带时间窗，没有「全量」这一档）。
- 进页时一次性载入内存，**每次按键在内存里过滤**（数量级：个人记账即使含导入账单也是万级，
  内存过滤 <10ms）→ 无需防抖、无逐键查库，输入手感即时。
- 结果上限 200 条；超出时列表底部提示「仅显示最近 200 条，请补充关键词」（避免超长列表）。

### 3.2 匹配口径（纯函数，可单测）

查询串预处理：`trim` → 去掉 `¥` / `￥` / 千分位 `,` → 英文转小写（中文不受影响）。

| 字段 | 口径 |
|---|---|
| 备注 | **子串包含**，大小写不敏感（`note.toLowerCase().contains(q)`） |
| 分类名 | 按 `categoryId` 解析出的分类名做**子串包含**；`categoryId` 为空时按「未分类」参与匹配 |
| 金额 | 把金额格式化为**「元.分」文本**（无千分位，如 `88.88` / `0.05`），做**子串包含**。查询含数字时才参与比较 |

- 三类命中**取并集**（OR）；空查询不产生结果（显示引导，不显示「全部流水」）。
- 金额子串示例：查 `88` 命中 `88.00` / `188.00` / `88.88` / `8.88`；查 `88.8` 命中 `88.80` / `88.88`；
  查 `0.5` 命中 `0.50` / `10.50`。**不是**精确等值匹配（待签字项 Q2 可改）。
- 只匹配**业务字段**，不匹配 `id` / `fingerprint` / 内部时间戳。

### 3.3 结果汇总

复用既有 `summarize()`（`month_summary.dart`）对过滤结果求和 → 「共 N 笔 · 支出 X · 收入 Y」，
不新写统计逻辑，天然与首页/统计页口径一致。

## 4. 交互

1. **入口**：首页 header 搜索图标 → `context.push('/search')`；tooltip 从「搜索（建设中）」改为「搜索」。
2. **搜索页**（`/search`，全屏 `Scaffold`）：
   - `AppBar` 内嵌 `TextField`（`autofocus: true`），`prefixIcon` 放大镜，
     `suffixIcon` = **一键清空**（`Icons.cancel_rounded`，仅在有输入时显示；点击清空 + 重新聚焦）。
   - `maxLength` 50（不显示计数器），`textInputAction: search`。
   - 下划线输入框（`InputDecoration`）与 AppBar 同色，视觉上像「标题变成输入框」。
3. **结果列表**：复用 `TxGroupList`（按天分组、`formatDayLabel` 自动补年份）；点 → `/record`（extra=id）编辑；
   长按 → 复用 `confirmDeleteTx` 二次确认后软删。
4. **删除/编辑后的刷新链路**（本项目高发 bug 类，必须显式接线）：
   - 删除：`searchProvider.refresh()` + `ledgerProvider` / `calendarProvider` / `statsProvider` /
     预算卡链路，与首页 `_confirmDelete` 完全一致。
   - 编辑：`await context.push('/record', ...)` 返回后 `searchProvider.refresh()`
     （不依赖 `.then`，与 `import_page` 的既有处理一致）。
5. **状态**：
   - 未输入：提示「输入分类、备注或金额开始搜索」+ 三行示例说明（点示例可填入）。
   - 无结果：「没有匹配「xxx」的账单」+「清空」按钮。
   - 载入中 / 失败：转圈 / 「加载失败：$e」。

## 5. 文件清单

**新增**
- `lib/features/search/application/search_query.dart` — 纯函数：`normalizeQuery` / `matchesQuery` /
  `filterTx` / `amountTextOf`（口径全在这里，可单测）
- `lib/features/search/application/search_controller.dart` — `searchProvider` + `searchKeywordProvider`
- `lib/features/search/presentation/search_page.dart` — 页面（含 AppBar 输入框与一键清空）
- `test/features/search/search_query_test.dart`
- `test/features/search/search_page_test.dart`

**修改**
- `lib/data/repositories/transaction_repository.dart` — +`listByBook(bookId)`
- `lib/app.dart` — +`GoRoute('/search')`
- `lib/features/ledger/presentation/home_page.dart` — 搜索图标接线（tooltip 去「建设中」）
- `test/data/repositories/transaction_repository_test.dart` — +`listByBook` 用例
- 文档：`CHANGELOG.md` / `HANDOFF.md` / `tasks/todo-flutter.md` / `README.md`

> 落点说明：搜索是**跨页能力**（首页 header 是入口，但结果页不属于账本/日历任一 feature），
> 因此单开 `features/search/`，与 `features/stats/` 同级。

## 6. 测试

| 层 | 用例要点 |
|---|---|
| `search_query`（纯函数） | 备注子串 / 大小写 / 前后空格 / `¥` 与逗号；分类名匹配（含「未分类」）；金额子串（`88`→`88.88`、`88.8`→`88.80`、`0.5`→`10.50`）；**不命中**的反例；空查询；中文+数字混合 |
| `transaction_repository` | `listByBook` 覆盖全部月份、倒序、排除已软删、跨账本隔离 |
| widget | 输入分类 / 备注 / 金额各命中一次；一键清空按钮的出现与生效（清空后回引导态）；无结果文案；汇总行「共 N 笔」 |

## 7. 风险 / 取舍

- **全量载入内存**是本方案唯一的规模假设（万级行没问题，若将来真到十万级再改 SQL LIKE 分页）。
  已在 §3.1 写明；不在本次做过早优化。
- 关键词**高亮**、搜索历史、日期区间筛选、账户名匹配、拼音/首字母匹配**本次不做**（Q3 可点单）。
- 跨账本搜索**不做**（与其它页一致，只搜当前账本）。
- 金额子串匹配（`88` 也命中 `188.00`）是「宁多勿漏」的取舍；若嫌噪音大可改精确匹配（Q2）。

## 8. 工期切片

1. 数据层：`listByBook` + 仓储单测
2. 计算层：`search_query` 纯函数 + 单测
3. UI：`search_page` + 路由 + 首页接线 + widget 测试
4. 门禁 + MuMu 冒烟（分类/备注/金额各搜一次 + 一键清空 + 结果点开/长按删）+ 文档
