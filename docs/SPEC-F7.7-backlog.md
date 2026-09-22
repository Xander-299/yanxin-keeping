# SPEC — F7.7 backlog 五批（报表明细 / 数据导出 / 账户图标 / 搜索增强 / 日历增强）

> 状态：**待签字**（2026-09-23 起草）
> 上游：`docs/PRD-yanxin-flutter.md`（口径汇总）· `HANDOFF.md`「未解决问题」
> 前置：F7.6 卡通视觉改版已收尾（`v0.7.6`）。本批**全是新功能**，视觉一律沿用 F7.6 的令牌 + 通用件。
> 目的：把 backlog 里剩下的 5 项**一次性写清楚**，签一次字就能按 A→E 顺序逐批交付，每批单独打 tag。

---

## 0. 批次总览

| 批次 | 内容 | 需新依赖 | 版本 | 主要理由 |
|---|---|---|---|---|
| **A** | 报表明细清单 —— 点亮 4 处「报表（建设中）」占位（**含前置：记一笔支持选账户**） | 否 | `v0.7.7` | 占位最多、用户可感知度最高；数据层已齐（`stats_aggregate`） |
| **B** | 数据导出（「我的 → 数据导出」） | 否（用已装的 `file_picker.saveFile`） | `v0.7.8` | 「我的」页最后一个占位；纯读 + 落盘，风险低 |
| **C** | 账户图标 / 颜色选择 | 否 | `v0.7.9` | `accounts.icon` / `color` 列**早已存在**，只缺界面 |
| **D** | 搜索增强（高亮 / 账户名 / 历史 / 日期区间） | 待确认（拼音见 D.5） | `v0.7.10` | 打磨已有功能 |
| **E** | 日历增强（长按记账 / 页内翻月） | 待确认（农历见 E.5） | `v0.7.11` | 同上 |

**统一约定**

- 视觉：一律用 `Tok` 令牌 + `ToonCard / ToonButton / ToonPress / ToonSeg / ToonChip / ToonField / ToonDashedBorder`；
  **产品代码禁止裸 `Color(0x…)`**（`lib/core/theme/` 内除外）。
- 门禁（每批都要过）：`flutter analyze` **0 issue**；`flutter test` **全绿，0 skip**（基线 269，用例只增不删）；
  真机走查（MuMu 12 / 900×1600 / 320dpi）**阻断 0**。
- 每批：代码 → 门禁 → 真机走查 → 回写 `SPEC` 实施记录 / `CHANGELOG` / `HANDOFF` / `todo` → `git tag -a`。
- 语义文案尽量**保持既有字符串**（如「共 N 笔」「重置」），把测试改动面压到最小。

---

## A. 报表明细清单（`/reports`）

### A.1 要解决的问题

首页 header、首页「全部账单 ›」、日历页 header、月份选择页 header —— **共 4 处**「报表（建设中）」
灰色占位。用户点下去只弹 toast，看不到「这个月的钱花在哪、由哪些流水组成」。
统计页只有**占比圆环 + 趋势柱**，没有**清单**（谁、哪天、多少钱、哪个账户）。

### A.2 目标（DoD）

0. **【前置】记一笔支持选账户**。现状：`record_page.dart:172` 写死 `accountId: accounts.first.id`
   （`accounts` = 当前账本账户列表），**用户根本无法选账户** → 不改这一条，「按账户报表」只会永远只有一行，
   C 批（账户图标）也白做。做法：在现有三个 `ToonField`（分类 / 日期 / 备注）后面加第四个
   **账户**字段 → 点开底部弹层选账户（抓手 + 标题 + `ToonAvatar` 行列表 + 选中对勾），
   默认仍是**列表首个账户**（老行为不变，老用例不受影响）；导入流程的账户选择**本期不动**（仍用首个账户）。
1. 新增全屏页 `/reports`，AppBar 标题**报表**，右侧有月份切换（复用统计页那套 `ToonIconButton` + 年月文本）。
2. 页内 `ToonSeg` 三档：**明细 · 分类 · 账户**。
3. 4 处占位全部改成真实入口（不再有「建设中」灰字 / toast）：
   - 首页 header「报表」→ `/reports`（**默认「分类」档**）
   - 首页「全部账单 ›」→ `/reports`（**默认「明细」档**，文案保持「全部账单」）
   - 日历页 header「报表」→ `/reports`（**默认「明细」档**，月份对齐日历页当前月）
   - 月份选择页 header「报表」→ `/reports`（**默认「明细」档**，月份对齐该页当前月）
4. 页面与统计页一样**独立记月份**（翻月不带动首页 / 日历 / 统计）。
5. 空态：该月无流水 → 卡通空态（虚线圆 + `PigMascot` + 「这个月还没有记账」+ 「去记一笔」）。

### A.3 数据与口径

- 取数：`transactionRepository.listByMonth(bookId, year, month)` —— **与首页 / 日历 / 统计同一句 SQL**，
  口径天然一致（软删已过滤）。
- 「明细」档：按**日**倒序分组，组头「今天 / 昨天 / M月D日 周X · N 笔 · 支出 ¥x」，
  组内行复用现有 `TxGroupList` 的流水行样式（含长按删除）。**不做**左滑删除（见 A.4）。
- 「分类」档：
  - 分**支出 / 收入**两段（`ToonSeg` 已经占给三档，这里改为两段小标题），
    每段用 `categoryBreakdown(rows, kind, nameOf)` 聚合（**纯函数直接复用**，不重写口径）。
  - 每行 = 分类头像 + 名称 + 笔数 + 金额 + 占比条；**点击展开**该分类的流水行（折叠态默认收起）。
  - `transfer` 不计入支出/收入（与统计页一致），单列一段「转账 · N 笔」。
- 「账户」档：**已核对 `lib/core/db/tables.dart`** —— `transactions.account_id` 是 `NOT NULL` 单列，
  **没有 `to_account_id`**（转账成对关联只有预留的 `transfer_group_id`，当前未启用）。
  所以口径定为：**每行 = 一个账户**，按 `account_id` 聚合该月的
  `支出 ¥x · 收入 ¥y · 转账 ¥z · N 笔`；点击展开该账户的流水行。
  - 账户过滤：只列**当前账本内、未软删**的账户；已软删账户的流水归到「其他账户」。
  - 账户为空串 / 查不到名字 → 归到「其他账户」。
- 金额展示：`centsToYuan(x, group: true)`；支出 `Tok.red`、收入 `Tok.green`、转账 `Tok.ink2`。

### A.4 不做

- 不做导出（属 B 批）、不做新图表（圆环 / 趋势仍在统计页）、不做自定义时间段（只有按月）。
- 不做报表页内的流水编辑 / 删除（长按删除仍只在首页与搜索结果里）。
- 不做「按分类折叠状态持久化」。

### A.5 文件清单（预估）

| 文件 | 改动 |
|---|---|
| `lib/features/record/presentation/record_page.dart` | **A.0 前置**：加第 4 个 `ToonField`「账户」+ 状态与保存改用所选账户（默认首个） |
| `lib/features/record/presentation/widgets/account_picker_sheet.dart` **新增** | 选账户底部弹层（抓手 + `ToonAvatar` 列表 + 选中对勾） |
| `lib/features/reports/application/report_aggregate.dart` **新增** | 纯函数：`groupByDay` 复用 + `groupByCategory` / `groupByAccount`（可单测） |
| `lib/features/reports/application/reports_controller.dart` **新增** | `AsyncNotifier`：当前账本 + 月份 + 档位 + 当月流水 + 账户名映射 |
| `lib/features/reports/presentation/reports_page.dart` **新增** | 页面骨架（AppBar + 月份切换 + `ToonSeg` + 三档 body + 空态） |
| `lib/features/reports/presentation/widgets/report_group_list.dart` **新增** | 分组行 + 可展开的流水子列表 |
| `lib/app.dart` | 加 `/reports` 路由（extra 传 `{tab, year, month}`） |
| `home_page.dart` / `calendar_page.dart` / `month_picker_page.dart` | 4 处占位换真实入口（muted 样式去掉） |
| `test/features/reports/report_aggregate_test.dart` **新增** | 聚合纯函数单测（≥8 例） |
| `test/features/reports/reports_page_test.dart` **新增** | 页面 widget 测试（三档切换 / 展开 / 空态 / 入口可达） |
| `test/features/record/record_account_test.dart` **新增** | A.0：选账户后保存，库里 `account_id` 是所选账户 |

### A.6 风险

| 风险 | 处理 |
|---|---|
| `transfer` 的双账户语义与现有表结构不符 | 先读 `tables.dart` 确认；若无 `to_account_id` 就本期不做双账户，SPEC 记录 |
| 三档展开后列表很长 | 展开项限制「最多 200 行 + 尾注」（搜索浮层已有同样做法，复用文案口径） |

---

## B. 数据导出

### B.1 目标（DoD）

「我的 → 数据导出」（当前是「建设中」灰字）→ 打开**导出弹层**（抓手 + 标题 + 两条选项 + 取消）：

1. **导出流水 CSV**（当前账本 · 全时间）
   - 表头：`日期,类型,金额,分类,账户,备注,来源`
   - 日期 `YYYY-MM-DD HH:mm`；金额**元、两位小数**（不带千分位、不带符号）；
     类型 `支出/收入/转账`；来源取 `transactions.source`。
   - 编码 **UTF-8 with BOM**（Excel 双击不乱码）；换行 `\r\n`；备注按 RFC4180 加引号转义。
   - 文件名：`颜芯记账_{账本名}_{YYYYMMDD}.csv`
2. **导出备份 JSON**（当前账本 · 全量：账本 / 账户 / 分类 / 流水 / 预算）
   - 文件名：`颜芯记账_{账本名}_{YYYYMMDD}.json`
3. 落盘：`FilePicker.saveFile(fileName:, bytes:, mimeType:)`（**已装依赖，零新增**）→ 返回 `Uri?`；
   成功 SnackBar：`已导出 N 笔到 {文件名}`；用户取消 → 静默（不弹错误）。
4. 导出**只读**，不写库、不改任何状态。

### B.2 不做

- 不做导入回灌（备份 JSON 只导出，不承诺可还原）、不做云端上传 / 分享（会引入新依赖）、
  不做 Excel 格式、不做按月份导出（本期全时间）。

### B.3 文件清单

| 文件 | 改动 |
|---|---|
| `lib/features/export/application/csv_export.dart` **新增** | 纯函数：`buildBillCsv(rows, categoryNames, accountNames)` / `buildBackupJson(...)`（可单测） |
| `lib/features/export/presentation/export_sheet.dart` **新增** | 导出弹层（两个 `ToonPress` 选项 + 进度 / 结果） |
| `lib/features/profile/presentation/profile_page.dart` | 「数据导出」条目接真实入口 |
| `test/features/export/csv_export_test.dart` **新增** | CSV 转义 / BOM / 金额格式 / 空账本 |

---

## C. 账户图标 / 颜色选择

### C.1 目标（DoD）

`accounts.icon` / `accounts.color` 两列**已存在**（当前恒为 `''`），本批把界面补上：

- 账户表单（新增 / 编辑）在「账户名称」与「账户类型」之间插入**图标**与**颜色**两块：
  - 图标：`ToonChip` 网格，候选 8 个（沿用 `accountTypeIcon` 那套 Material 图标的语义集 + 现金/卡/钱包/存钱罐），
    选中即高亮；**留空 = 跟随账户类型**（现行为）。
  - 颜色：8 色圆点（取 `Tok.pie`），**留空 = 跟随类型默认色**。
- 资产页账户头像：`icon` 非空 → 用该图标；`color` 非空 → 用该色做 `brandTint` 位的底色（前景用 `Tok.ink`）。
- 新增账户时给**默认值**（图标 / 颜色跟着类型走），用户可改。
- 兼容：老数据 `icon`/`color` 为空串 → 行为与现在完全一致（不迁移、不回填）。

### C.2 文件清单

| 文件 | 改动 |
|---|---|
| `lib/features/assets/presentation/widgets/account_form_sheet.dart` | 加图标 / 颜色两块选择 |
| `lib/features/assets/application/account_meta.dart` | 加 `kAccountIcons` / `kAccountColors` + 默认值解析（纯函数） |
| `lib/features/assets/presentation/assets_page.dart` | 头像用 `icon` / `color` |

### C.3 风险

| 风险 | 处理 |
|---|---|
| 图标集选中后语义重复（类型图标 vs 自选图标） | 自选图标**只是装饰**，不参与筛选 / 口径 |
| 表单变长，矮窗口下按钮被顶出屏 | 表单已经是 `SingleChildScrollView`；测试里用 `ensureVisible` |

---

## D. 搜索增强

### D.1 目标（DoD）

在现有搜索浮层（`showSearchOverlay`，非路由）上增强，**保持入口与关闭手势不变**：

1. **关键词高亮**：命中的分类名 / 备注 / 金额子串在结果行里高亮（`RichText` + `brandTint2` 底）。
2. **账户名匹配**：新增一路命中口径 —— 账户名（如「招行」「支付宝」）也能搜到流水。
3. **搜索历史**：最近 10 条关键词，**持久化到现有 drift 库**（新增一张 KV 表 `app_meta`，schema v2 → **v3**）；
   引导态下方展示历史 `ToonChip`，点击即搜；提供「清空历史」。
   - 为什么不用 `shared_preferences`：**它不在现有依赖里**（已核对 `pubspec.yaml`：只有 archive /
     crypto / drift / file_picker / flutter_riverpod / gbk_codec / go_router / path / sqlite3 / uuid）。
     加依赖 vs 加一张表，选后者 —— 不用动依赖、导出备份能一起带走、迁移走项目已有的 `onUpgrade` 纪律。
   - ⚠️ **动 schema 就必须走「真机覆盖安装」验迁移**（见 `mumu-flutter-ui-smoke` 的对应小节），
     内存库单测只能证明 `onUpgrade` 逻辑本身。
4. **日期区间筛选**：在类型 chips 那一行后面加「本月 / 近 3 月 / 全部」三档 `ToonChip`（单选，默认全部）。
5. 排序与上限不变（发生时间倒序，最多 200 条），尾注文案同步。

### D.2 不做

- 不做拼音 / 首字母匹配（见 D.5）、不做模糊纠错、不做搜索结果内分页、不做跨账本搜索。

### D.3 文件清单

| 文件 | 改动 |
|---|---|
| `lib/core/db/tables.dart` **新增表** | `AppMeta`（`key` 主键 + `value`），KV 用 |
| `lib/core/db/database.dart` | `schemaVersion` 2 → **3**；`onUpgrade` 建 `app_meta`（**真机覆盖安装验迁移**） |
| `lib/data/repositories/app_meta_repository.dart` **新增** | `get(key)` / `set(key, value)` / `remove(key)` |
| `lib/features/search/application/search_query.dart` | 加账户名命中 + 日期区间过滤 + 高亮区间（纯函数，可单测） |
| `lib/features/search/application/search_history.dart` **新增** | 历史读写（最近 10 条、去重、清空） |
| `lib/features/search/presentation/search_overlay.dart` | 高亮 `RichText` + 区间 chips + 历史 chips |
| `test/features/search/search_query_test.dart`（改）+ `search_history_test.dart`（新） | 命中口径 / 区间过滤 / 高亮区间 / 历史去重与截断 |

### D.5 待确认（需要新依赖）

| 项 | 问题 | 备选 |
|---|---|---|
| 拼音 / 首字母 | 需要汉字→拼音表（`lpinyin` 等纯 Dart 包，或内置一张常用字表），**当前无依赖** | ① **不做（默认）**；② 引入 `lpinyin`（纯 Dart，无 native 钩子，风险低）；③ 只做「声母首字母」的轻量内置表（覆盖常用 3–4 千字，包体 +~60KB） |

---

## E. 日历增强

### E.1 目标（DoD）

1. **长按某天 → 快速记一笔**：长按日历格子直接进 `/record?date=YYYY-MM-DD`（现在只能先选日期再点「记一笔」）。
2. **日历页内翻月**：日历网格支持左右滑动翻月（现在是点顶部年月 → 月份选择子页）。
   滑动阈值 1/3 格宽，跨月时**顶部年月与下方日列表同步刷新**（复用现有 `calendarProvider`）。

### E.5 待确认（需要新依赖 / 数据）

| 项 | 问题 | 备选 |
|---|---|---|
| 农历 / 节假日 | 需要农历算法与每年更新的节假日数据 | ① 不做（默认）；② 引入 `lunar` 类纯 Dart 包只做农历；③ 引入包 + 每年手工更新节假日表 |
| 长按与滑动的手势冲突（月历在 `SingleChildScrollView` 里） | 竖向滚动由外层接管，横向滑动给翻月 | 用 `GestureDetector` 的横向 drag + `HitTestBehavior`；**真机走查必须覆盖「上下滚不动卡住」这一项** |

---

## F. 签字

| 角色 | 结论 | 日期 |
|---|---|---|
| 用户 | ⬜ 待签字（可分批签：只签 A 也可开工） | |

**签了哪些批就做哪些批**；未签的批次保持 `⬜ 待排期`。

---

## G. 实施记录

_（每批交付后回写：日期 / 文件 / 门禁结果 / 真机走查结论 / commit + tag）_
