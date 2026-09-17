# 变更日志

本项目变更记录格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

> 迁移期（F0–F6）尚未发布正式版本号，先按「阶段 / 日期」归档；首个正式版发布后改为语义化版本号。

## [Unreleased]

### 新增 — F7.5-b 资产页（2026-09-17）

- **背景**：底栏「资产」tab 一直是 `PlaceholderPage`，但**账户数据早已入库**
  （`accounts` 表 + `AccountRepository` 完整 CRUD、新建账本自带「现金」、导入自动建账户、
  记一笔默认写 `accounts.first`）——缺的只是界面。SPEC：`docs/SPEC-F7.5-assets.md`（已签字）。
- **口径**：账户余额 = **初始余额 + Σ收入 − Σ支出**，**transfer 不计**
  （`transfer_group_id` 仍是预留字段，转账的「从哪到哪」没落库语义，硬算必错）。
  净资产 = 各未删账户余额之和，**全时间累计**（资产是存量，不按月筛选）。
- **页面**：净资产卡（≥0 琥珀橙 / <0 红，副行「N 个账户 · 全时间累计」）+ 账户行
  （类型图标 / 名称 / 「类型 · 收 X / 支 Y」/ 余额，负余额红字）+ 无账户空态。
- **账户 CRUD**：AppBar `+` 新增、点行编辑，底部 sheet 三字段（名称 / 类型下拉 / 初始余额元）。
  **有流水的账户禁止删除**（弹「还有 N 笔流水，请先改到别的账户」），防止流水指向不存在的账户。
- **刷新机制改了一处**：新增 `dataEpochProvider`（数据版本号），资产页 watch 它；
  记一笔 / 导入 / 首页删除 / 日历删除 / 搜索删除 5 个写操作点各自 bump 一行即可。
  原因：HANDOFF 记载过「漏刷 `statsProvider` 出 bug」——逐个 provider 手工 `refresh()` 是已知脆弱点，
  新增一个消费方就要补 N 处。**本次不动 stats / calendar / ledger 的既有 refresh 调用**（避免回归）。
- **不改 schema**：无新表无新字段，`schemaVersion` 仍为 2，`database.g.dart` 未变，老库升级零风险。
- **门禁**：`flutter analyze` No issues found；`flutter test` **266 通过 0 skip**
  （新增 13 条：聚合纯函数 10 + 资产页 widget 3）。
- **取舍**：初始余额**不接受负数**（`yuanToCents` 正则不放宽，不松动「金额恒正」铁律）；
  信用卡期初欠款暂由记支出体现。
- **真机走查（MuMu 12 / 900×1600 竖屏，首次使用验收规范）**：15 步全过，
  **阻断 0 / 卡住 0 / 状态丢失 0**；覆盖「空名称拦截」「金额三位小数拦截（弹窗不关、内容不丢）」
  「新增 → 净资产 0→100」「编辑回填」「删除二次确认 → 列表与净资产自动重算」
  「记一笔 88.88 支出 → 净资产 -88.88 红字、账户行支 88.88」「冷启动持久化」
  「有流水的账户禁删（拦截后编辑弹窗保留、账户未被删）」。报告 `docs/acceptance-F7.5b-assets.md`。
  遗留体验摩擦 1 条：账户图标 / 颜色无法设置（`icon` / `color` 列已存在，仅界面未暴露）。
- **本次修正的实走方法**：空 `TextField` 不出现在语义树里，早期按推算坐标点击落到遮罩区，
  表现为「弹窗莫名关闭 + 键盘不拉起」，一度被误判为阻断 bug；用「保存 / 取消」按钮坐标
  反推弹窗边界后复测推翻。坑已写进 `.workbuddy/skills/mumu-flutter-ui-smoke/SKILL.md`。

### 新增 — F7.5-a 搜索浮层化 + 类型筛选建议（2026-09-12）

- **背景**：F7.4 的搜索是**全屏独立路由**（`/search`），进去后首页被完全遮住、像换了个 App；
  且没有任何筛选入口——想「只看支出」只能靠关键词碰运气。用户需求（原话）：
  **「提示块提供搜索建议，比如仅支出，仅收入，转账等，不用提供历史记录，然后搜索功能是显示在
  首页的上层，提示块以下的区域做透明玻璃效果，使其能看见首页」**。
- **浮层化**：`/search` 路由与 `SearchPage` **一并删除**，改为 `showGeneralDialog` 打开
  `SearchOverlay`（`lib/features/search/presentation/search_overlay.dart`，原 `search_page.dart` 改名）——
  首页留在页面栈里当背景（DialogRoute 非 opaque，下层路由不会被 Offstage）。
  **不给同一功能留两条路**：那会变成两份 UI + 两套刷新链路（本项目已因「同一个东西两份状态」踩过坑）。
- **毛玻璃**：`BackdropFilter(blur sigma 12)` 铺满全屏 + 半透明遮罩；**不透明提示块**盖住上半部分
  ——视觉上「提示块以下才是玻璃」，且提示块边缘不会出现接缝。结果列表浮在玻璃之上（条目自带 `Card` 背景）。
- **类型筛选（本次核心）**：「仅支出 / 仅收入 / 转账」这几个字**不在业务字段里**
  （备注 / 分类名 / 金额都匹配不到），直接当关键词搜恒为空 → 改为解析成 `Transactions.type` 条件：
  - `仅支出` → 该账本全部支出；`仅收入` / `转账` 同理。`仅支出 餐饮` → **类型 ∩ 关键词**。
  - 纯函数实现（`search_query.dart` 的 `parsePlan` / `stripTypeWords`）；类型词**须独立成词**
    —— `转账手续费` 不会被误判成指令，仍走普通关键词匹配。
  - 同时出现多个类型词时**以最后出现的为准**。
  - 词是**真的填进输入框**（可见 / 可编辑 / 可一键清空），chip 高亮**由输入框内容推导**
    → 不会出现「chip 亮着但输入框空着」这种双份状态。填入时补**尾随空格**，方便接着敲关键词。
- **交互**：三种关闭方式（关闭按钮 / 点玻璃空白区 / 系统返回键）；无结果态沿用 F7.4 的
  「顶部对齐 + 占屏高 1/5」；结果条目**点=编辑、长按=删除**，删改后浮层内 + 首页 / 日历 / 统计 /
  `yearDayIndex` 全刷。
- **门禁**：`flutter analyze` No issues found；`flutter test` **247 通过 + 6 skip**
  （新增 21 条：类型指令解析 11 + 浮层 widget 10）。
- **真机走查（MuMu 15，覆盖安装老数据零丢失：支出 120.00 / 收入 50.00 / 预算 3,000）**：
  SPEC §6 十条全过。另抓到 **3 个只有真机才暴露**的问题并修掉：
  ① **引导态点提示块以外的空白关不掉浮层**（无结果态却可以）——`_Intro` 当时用
  `SingleChildScrollView`，Scrollable 的 `RawGestureDetector` 以 `HitTestBehavior.opaque`
  命中了整块下方区域，点击传不到底层玻璃的关闭手势 → 改用 `Align(topCenter)`，只占内容高度、空白可穿透；
  ② **选中 chip 的对勾让 chip 变宽，把后面几个整排挤位移** → `showCheckmark: false`；
  ③ **点 chip 后接着敲字拼成 `仅支出11`，指令失效、结果恒为空** → 填入时补尾随空格。
  ①②③ 中 ①③ 已补 widget 回归测试。
- **转账说明**：`Transactions.type` 支持 `transfer`（此时 `categoryId` 为 NULL），但**记账页没有转账入口**，
  现有数据基本为空 —— 该 chip 仍保留：点了走类型筛选，命中为空则显示无结果态。

### 优化 — 搜索页无结果态改为「顶部对齐 + 占屏高 1/5」（2026-09-12）

- **问题**：无结果提示原用 `Center` 垂直居中，四周留大片空白；且提示与输入框离得太远
  ——用户刚敲完词、视线还在输入框附近，提示却飘在屏幕正中。
- **改法**（`lib/features/search/presentation/search_overlay.dart` 的 `_NoResult`；F7.5 已由 `search_page.dart` 改名）：
  - 外层改 `Align(topCenter)` + `SizedBox(height: MediaQuery.sizeOf(context).height / 5)`：
    提示块紧贴输入框下方，高度固定占**整屏** 1/5；
  - 高度按整屏而非 body 计算——本页输入框 `autofocus`，键盘弹起会压扁 body，
    按 body 算的话提示块会跟着一起缩；
  - 内容同步紧凑化（图标 40→32、间距 12→6/4、按钮 `visualDensity.compact` + `tapTargetSize.shrinkWrap`），
    保证塞得进 1/5 高度；极小屏（逻辑高 < 约 550）由 `SingleChildScrollView` 兜底，不会 RenderFlex 溢出。
- **验证**：门禁 analyze 0 issue / test 226 通过 + 6 skip（`_NoResult` 的断言文案未改，测试无需调整）；
  MuMu 15 走查：搜 `zzz` → 提示块落在输入框下方、占屏高约 1/5、下方留白；
  搜 `11` → 有命中态（共 1 笔 · 支出 11.12）不受影响。

### 新增 — F7.4 流水搜索（2026-09-12）

- **背景**：首页 header 的搜索图标一直是占位（点了弹「功能建设中」）；账记得越多，找一笔旧账越难
  ——只能按月翻首页/日历。用户需求：**按分类 / 备注 / 金额搜索 + 输入框一键清空**。
- **取数**：新增 `TransactionRepository.listByBook(bookId)`（全时间、未删、`occurred_at` 倒序）。
  搜索页进页**一次性读齐**当前账本流水 + 分类名表（万级行 <10ms），之后**逐键内存过滤**
  ——无需防抖、不逐键查库，输入手感即时。
- **匹配口径**（`lib/features/search/application/search_query.dart`，纯函数可单测）：
  - 查询串预处理：去首尾空白、去 `¥` `￥` 与千分位逗号、英文转小写、限长 50；
  - **分类名**：按 `categoryId` 解析出的名字做子串包含（`categoryId` 为空按「未分类」）；
  - **备注**：子串包含，大小写不敏感；
  - **金额**：格式化为「元.分」文本后子串包含（查 `88` 命中 `88.00 / 188.00 / 88.88`；
    查 `88.8` 命中 `88.80`；查 `0.5` 命中 `10.50`）；
  - 三类取**并集**；空查询不返回全部流水（显示引导）。
- **UI**：新增 `/search` 全屏页（首页 header 搜索图标进入）——
  - `AppBar` 即输入框（`autofocus`），右侧**一键清空**（有输入才出现，点击清空并保持焦点）；
  - 结果按天分组复用 `TxGroupList`（点=编辑、长按=删除，与首页一致）；
  - 顶部结果条：`共 N 笔 · 支出 X · 收入 Y`（复用 `summarize`，与首页/统计页口径一致）；
    超过 200 条只显示最近 200 条并提示补充关键词；
  - 三种状态齐备：未输入（引导 + 示例词可点）、无结果（回显关键词 + 清空）、有结果（列表 + 汇总）；
  - 删除/编辑后的刷新链路与首页对齐：`searchProvider` + 首页/日历/统计 + `yearDayIndex` 全刷。
- **验证**：门禁 `flutter analyze` No issues found、`flutter test` **226 通过 + 6 skip**（新增 27 条：
  匹配纯函数 19 + 搜索页 widget 7 + 仓储 1）；**MuMu 15 真机冒烟**：搜「餐饮」→ 共 2 笔（支出 100.00）、
  搜 `88.88` → 共 1 笔、搜「午餐」（库中无此备注）→ 无结果态、一键清空 → 回引导态、
  记一笔 1.23 + 备注 `coffee` → 搜 `coffee` 命中 1 笔、点结果进编辑页数据正确、
  长按删除 → 无结果态且**首页 / 预算卡回滚到 120.00**（跨页刷新正常）。

### 新增 — F7.3 月度预算实装（2026-09-12，schema v2）

- **背景**：首页预算卡原是写死的示例数字（`1,000.00 / 101.52 / 10.2%`），与同屏 hero 的
  真实月支出自相矛盾（首用验收 P2）。当时的「示例」chip 只是止损，本次把它做成真功能。
- **数据层（`schemaVersion 1 → 2`）**：
  - 新增 `budgets` 表：`book_id` + `period('YYYY-MM')` + `amount_cents` + 同步元数据五件套，
    与其它业务表同构（软删 / `dirty` / 金额整数分 / 客户端 UUID 主键）。
  - 部分唯一索引 `idx_budget_book_period(book_id, period) WHERE deleted_at IS NULL`：
    同月重复设置走更新；删掉后可重设。
  - `onUpgrade(from < 2)` **只加表 + 建索引**，v1 五张表与 7 条索引一字未改 → 老库升级零数据风险。
  - 新增 `BudgetRepository`（先查后写，不依赖 sqlite 错误消息判重；软删；跨账本隔离）。
- **计算层**：新增 `budget_metrics.dart`（纯函数）——进度（环形封顶 1.0，文案显示真实值可 > 100%）、
  剩余额度（可为负）、本月日均（复用日历页口径：当月按已过天数、历史月按整月）、
  剩余每日可消费（当月含今天；历史月不适用显示「—」；超支归 0）。
- **UI**：
  - `BudgetCard` 替换 `budget_card_placeholder.dart`（占位卡删除，**「示例」chip 与说明文案一并移除**）。
  - 未设预算时给可点的空态引导（「设置N月预算」），**页面上不再出现任何假数字**。
  - 底部弹窗就地设置：常用额度快捷键（1000/2000/3000/5000）+ 金额校验 + 有预算时「删除预算」（二次确认）。
  - 已消费 / 日均直接取首页已加载流水 → 记一笔 / 删一笔后卡片随首页刷新，**无需额外接线**。
- **验证**：门禁 `flutter analyze` No issues found、`flutter test` **199 通过 + 6 skip**（新增 26 条）。
  MuMu 15 真机：**旧版本覆盖安装（v1 库 → v2）数据零丢失**（108.88 / 50.00 全在）、
  设置 2000 → 5.4% / 1891.12 / 每日 99.53、改 100 → **超支态**（108.9% / -8.88 /「已超支」/ 每日 0.00）、
  删除 → 回到未设置、force-stop 重启后 3,000.00 仍在、记一笔 11.12 → 卡片自动变 120.00 / 4.0%。

### 修复 — 统计页不随记账刷新（2026-09-12，MuMu 冒烟发现）

- 现象：记一笔/导入/删除后，首页与日历都会刷新，**统计页仍是旧数据**（收入 50.00 已入账，统计摘要仍显示 0.00）。
- 根因：`statsProvider` 是常驻 `AsyncNotifierProvider`，`build()` 只在首次进页执行一次；
  `refresh()` 虽已预留但**无任何调用方**。
- 修复：与首页/日历的既有刷新模式对齐，补齐四处调用——
  `record_page`（保存后）、`import_page`（导入后）、`home_page` / `calendar_page`（删除后）。
- MuMu 模拟器复验：记 20.00 后统计支出 88.88 → 108.88；门禁复跑 analyze 0 issue、test 173 通过 + 6 skip（skip 为缺真实账单样本，基线一致）。

### 环境 — MuMu 冒烟链路补齐（2026-09-12）

- 补装 **NDK r28c（28.2.13676358）** 与 **CMake 3.22.1**（腾讯镜像 + 7890 代理，8 线程分片下载 ~60s，
  脚本 `.workbuddy/dl_ndk.py`）；`android/gradle.properties` 加 `android.builder.sdkDownload=false`
  绕开新版 cmdline-tools sdkmanager 被 AGP 调用即崩（0xC0000409）的问题。
- `flutter build apk --debug` 本机跑通（177MB，增量 ~32s）；MuMu 15 由平板横屏 2560×1440 切为
  手机竖屏 1080×1920（`MuMuManager.exe setting -k resolution_mode phone.1` + restart）。

### 新增 — F7.2 统计·报表页（2026-09-12）

- **统计页**（`/stats`）：首页 header 的「统计」图标由「建设中」占位改为真实入口。
  - 分类占比：支出 / 收入切换（`SegmentedButton`）+ 自绘圆环（`CustomPainter`，未引图表库）
    + 图例（色块 / 分类名 / 占比 / 金额，千分位）；圆心显示该方向合计。
  - 近 6 个月趋势：每月两根柱（支出红 / 收入绿，中国习惯），缺月补 0，跨年柱标签带年份。
  - 当月汇总：收入 / 支出 / 结余；月份切换 `‹ ›` 与首页同样受「不能超过当前月」约束。
- 新增 `TransactionRepository.listByRange()`（一次取齐跨月 / 跨年区间，避免逐月查询）；
  `StatsController`（`statsProvider`）与首页 `ledgerProvider`、日历 `calendarProvider` 一样独立记月份。
- 测试：新增 13 条（聚合纯函数 9 + 统计页 widget 4）；门禁 `flutter test` **179/179**（166 + 13）。

### 环境 — 换机重装（2026-09-12）

- 新机器（用户 Administrator，只有 C:/M 盘，无 D 盘）重搭环境：Flutter 3.47.2 / Dart 3.13.2 →
  `C:\src\flutter`；JDK 17.0.12 → `M:\QQcache`；Android SDK → `C:\src\Android`；Gradle 缓存 → `C:\src\gradle-home`。
  `env.sh` 路径已全部重指向，并新增两条本机专属坑的说明（sqlite3.dll、bash PATH 兜底）。
- ⚠️ **Windows 自带 `winsqlite3.dll` 太老**：不支持 `RETURNING`（需 SQLite ≥ 3.35），drift 的
  `insertReturning` 全线报 `near "RETURNING": syntax error`，60 条测试挂掉。
  解法：官方 sqlite-dll-win-x64（3.53.4）放到 `C:\src\sqlite3`（进 PATH）+ 复制一份到 flutter_tester 同目录。

### 新增 — F7.1 日历页（2026-09-11）

- **日历 tab**：`/calendar` 由占位页替换为真实页面 —— 月历网格把每天的支出标负数（红）、
  收入标正数（绿），今天与选中日分别用琥珀色文字 / 描边。
- **月汇总条**：日历下方显示「月结余 / 日均支出」；日均支出当月按已过天数折算、历史月按整月天数，
  全程整数运算取整到分。
- **选中日账单**：下方列出选中日期的流水（点击编辑、长按删除），空态给「这天没有账单哦，赶紧记一笔吧~」
  与「记一笔」按钮。
- **月份选择子页**（`/month-picker`）：按年展示 12 个月的缩略日历，有账的日期标琥珀色，
  点某天即跳到该月并选中该日；底部分页「上一年 / 下一年」。
- **记录某一天的账**：记一笔页新增「日期」字段（可点改、上限今天），路由支持 `/record?date=<毫秒>`，
  日历页「记一笔」自动带入选中日期。
- 新增 `TransactionRepository.listByYear()`（一次查全年，供缩略图索引有账日期）；
  `CalendarController` 与首页 `ledgerProvider` 状态分离，两个 tab 各自记住月份。
- 测试：新增 15 条（聚合纯函数 8、仓储 1、日历 widget 6）；门禁 `flutter test` **166/166**。

### 修复 — 首次使用验收 P3–P6（2026-09-11）

- **P3 二次导入报告自相矛盾**：零新增时标题由「导入完成」改为「没有新增」，正文改为
  「这 N 笔之前已经导入过了，没有重复记账」；`ImportReport.uncategorized` 改为只统计
  **真正入库**的未匹配行（重复跳过的行与分类规则无关，此前会在 0 新增时虚报「未匹配分类 167 笔」）。
- **P4 首页空态不可见**：空态由居中大块改为紧凑单行（图标 + 说明 + 「记一笔」按钮 + 导入指路），
  修复大屏/横屏下 hero + 预算卡占满首屏导致空态被挤到折叠下方、用户只看到一片空白的问题；
  文案从「点底部的 ＋」改为真实存在的「记一笔」入口。
- **P5 保存入口藏在折叠下方**：记一笔页 `AppBar` 新增常驻「保存」按钮（底部按钮保留），
  大屏下填完金额 + 分类后无需滚动即可保存。
- **P6 预览页看不出如何取消单条**：预览顶部补「勾选的条目会导入，点条目可取消它」说明，
  并新增「全选 / 全不选」切换。

### 文档

- 新增 `CHANGELOG.md`；README 迁移进度表更新至 F5 完成，技术选型补全（`archive` 手写正则解析器、
  `file_picker`、`crypto`、`gbk_codec`），纠正 xlsx 选型误记为 `excel` 包的说法。

## [F5] 账单导入（M2 等价） — 2026-09-10

### 新增

- 账单解析五层（旧栈 `bill-import` 移植）：ZIP 魔数识别 → xlsx / CSV 分支 →
  行矩阵化 → 归一化 → 微信 / 支付宝 profile 适配。
- 微信 xlsx：`archive` 解压 + 手写正则解析器（不经 `double`，保住 31 位交易单号精度）；
  Excel 日期序列号按本地时区换算。
- CSV：逐字符状态机解析；支付宝 GBK 走 `gbk_codec`，用重编码回环校验判坏件。
- 分类关键词规则表（39 条有序规则）+ 未命中落「其他」。
- 导入编排 `importRows()`：单事务 + 指纹 `IN` 分批预查（500/批）+ 文件内去重 +
  `dryRun` 哨兵回滚；`importTransaction()` 指纹幂等入账（ADR-7）。
- 导入页 UI：选文件 → 预览（可单条取消）→ 确认导入 → 结果报告。

### 修复 — 首次使用验收 P1/P2（同批次）

- **P1 导入后首页看不到数据**：`ledger_controller` 新增 `jumpToMonth()`（可跳历史月，
  不受 `canGoNext` 限制）；报告对话框「好的」拆为「完成」+「去看账单」，正文说明数据落在哪个月。
- **P2 预算卡假数据与 hero 矛盾**：预算占位卡加「示例」标签与底部说明，明确非真实消费数据。

## [F4.5] 首页改版 + 底部导航 — 2026-09-10

### 新增

- 全局深色主题（近黑底 `#0C0C0C` + 琥珀橙 `#FFAF38`）。
- `StatefulShellRoute.indexedStack` 底栏 4 tab（首页 / 日历 / 资产 / 我的）+ 中央「记一笔」。
- 首页改版：账本 header + 琥珀 hero 月支出卡（`‹ ›` 翻月）+ 预算占位卡 + 「本月账单」分组列表。
- 账本抽屉（全部账本 + 管理账本入口）。

### 性能

- 消除记一笔 push 转场卡顿：去掉异步门闩 + 零重复查询。

## [F4] UI 基础（M1 等价） — 2026-09-09

### 新增

- 首页（hero 翻月 + 按天分组流水列表 + 空态）、记一笔（支出/收入 + 金额键盘 + 分类宫格 + 备注）、
  编辑流水、长按软删、账本管理（新建 / 切换隔离）、分类管理（预置不可删 + 自定义）。

## [F3] 数据层 — 2026-09-09

### 新增

- drift schema v1：`books / accounts / categories / transactions / schema_meta`，7 条索引
  原样落地（含 `DESC` 与 `idx_tx_fingerprint` 部分唯一索引，走 `onCreate` 原始 SQL）。
- 4 个 repository + `active_book_id` 持久化 + `importTransaction()` 指纹幂等入账。

## [F2] core/utils — 2026-09-09

### 新增

- `money`（整数分）、`id`（UUID v4）、`fingerprint`（入账指纹，与旧版逐字节一致）、
  `date`（月份边界 / 按天分组）。移植旧用例 + 指纹 golden 向量。

## [F1] 空壳 + 依赖 — 2026-09-09

### 新增

- `flutter create` 骨架、依赖锁定（drift / sqlite3 / Riverpod / go_router 等）、
  `analysis_options.yaml` 收紧（strict-casts/inference/raw-types）。
- `env.sh` 环境脚本（代理、VS 环境变量注入、`fx-qa` / `fx-test` 门禁命令）。

## [F0] 环境搭建 — 2026-09-09

### 新增

- Flutter 3.47.2 / Dart 3.13.2、JDK 17、Android SDK cmdline-tools、licenses 全部接受。
- Android 构建链路修复（国内镜像、Gradle 缓存策略）。
