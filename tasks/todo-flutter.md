# 迁移任务清单（Flutter）

> 配套 `SPEC-flutter-migration.md`（**未签字前不许开工**）
> 每步：实现 → 测试门禁 → 勾选 → 再进下一步

## F0 环境搭建 ✅ 已完成（2026-09-09）

- [x] Flutter 3.47.2 → `D:\Download\Flutter\flutter`（Dart 3.13.2）
- [x] JDK 17.0.20.1+1 → `D:\Download\Java\jdk-17.0.20.1+1`，已 `flutter config --jdk-dir`
- [x] cmdline-tools → `D:\Download\Java\Android\cmdline-tools\latest`
- [x] `flutter doctor --android-licenses` 已全部接受
- [x] 门禁：`flutter doctor` → Flutter ✅ / Android toolchain ✅ / Network ✅；残留告警均为 Windows桌面、web、wmic 沙箱拦截，与 Android 无关
- [x] 真机：Redmi K50 无线 adb 可见
- [ ] 清理 `D:\Tencent\yanxin-flutter\_sdk`（2.1GB 临时 zip，F1 后删）

## F1 空壳 + 依赖（analyze/test 已过，剩 APK 门禁）

- [x] `flutter create --platforms=android --org com.teacodeman --project-name yanxin .`
- [x] 依赖锁定（见 README「版本锁死的理由」）：drift 2.31.0 / drift_flutter 0.2.8 / sqlite3 2.9.4 / drift_dev 2.31.0 / build_runner 2.15.1 / flutter_riverpod 3.4.3 / go_router 18.0.1 / uuid 4.6.0
- [x] `flutter pub get` 通过
- [x] `analysis_options.yaml` 收紧（strict-casts/inference/raw-types + prefer_const + avoid_print 等）
- [x] lib 骨架：main.dart（ProviderScope）+ app.dart（go_router + 占位首页）+ 冒烟测试
- [x] `flutter analyze` → **No issues found!**
- [x] `flutter test` → **All tests passed!**（踩坑：沙箱吞 PROGRAMFILES(X86) + 代理劫持 WebSocket，解法固化在 `env.sh` 的 `fx-test`/`fx-qa`）
- [x] git init + 提交 `ba45fba` + 远端 origin 已配（远端仓库待用户网页创建）
- [x] 门禁：`flutter build apk --debug` 成功（2026-09-09，第 8 次构建，`build/app/outputs/flutter-apk/app-debug.apk` 169MB）
- [x] 已推送 `origin/master`（`git@github.com:Tea-Codeman/yanxin-bookkeeping-flutter.git`）
- [x] F5 再装：excel / csv / gbk_codec / file_picker

> **坑**：`flutter pub add` 本机卡死 20min+ → 改「Python 查 pub API → 手写 pubspec → `pub get`」。
> **坑**：sqlite3 3.x 带 C 构建钩子，无 VS 的 Windows 跑不了 `flutter test` → 锁 2.9.4。
> **坑**：把 `<USER_HOME>\.gradle\caches` 复制到工作区会让 Gradle **启动即挂死**（`--status` 都无响应）→ 必须让 Gradle 用**全新空目录**自行下载（腾讯/阿里云镜像很快）。

## F2 core/utils ✅ 已完成（2026-09-09）

- [x] `money.dart`（整数分，格式化/解析）
- [x] `id.dart`（UUID v4）
- [x] `fingerprint.dart`（入账指纹算法，与旧版逐字节一致）
- [x] `date.dart`（月份边界、月初月末、按天分组）
- [x] 门禁：移植 money/id/date 全部旧用例 + 指纹 golden 向量 → `flutter test` 27/27、`flutter analyze` 0 issue

## F3 数据层 ✅ 已完成（2026-09-09）

- [x] drift tables：books / accounts / categories / transactions / schema_meta（DDL 对齐 schema v1，已对拍 `sqlite_master`）
- [x] 7 条索引原样落地（含 `DESC` 与 `idx_tx_fingerprint` 部分唯一索引，见 `core/db/schema_v1.dart`）
- [x] schemaVersion=1（drift 托管 `PRAGMA user_version`）+ onCreate 建表建索引
- [x] repositories：book / account / category / transaction（含 `active_book_id` 持久化）
- [x] `importTransaction()` 指纹幂等入账（先查后插，`ImportResult` sealed 类）
- [x] 门禁：移植 db + repositories 用例（软删、指纹唯一、迁移幂等、账本隔离、月份边界）→ `flutter test` **56/56**、`flutter analyze` **No issues found**
- [x] `dart run build_runner build` 生成 `lib/core/db/database.g.dart`（已入库）

> **坑**：drift 的 `@TableIndex` 不支持 `DESC` / 部分索引 `WHERE` → 索引一律在 `onCreate` 走原始 SQL。
> **坑**：`Transactions` 表数据类名必须改成 `TxRow`（`@DataClassName`），否则与 drift 自带 `Transaction` 撞名。
> **坑**：`drift` 与 `matcher` 都导出顶层 `isNull` → 测试里 `import 'package:drift/drift.dart' hide isNull`。

## F4 UI 基础（M1 等价）✅ 完成（2026-09-09 代码 + 真机验收通过）

- [x] 首页：hero（月切换 ‹ ›，canNext 不超前当前月）+ 按天分组流水列表 + 空态 + FAB
- [x] 记一笔：支出/收入 tab + 金额键盘 + 分类选择（宫格弹层）+ 备注
- [x] 编辑已有流水（路由 extra 传流水 id）
- [x] 长按删除（软删，带确认弹窗）
- [x] 账本管理：列表 + 新建 + 切换（active_book_id 落库，BUG-016 语义）
- [x] 分类管理：支出/收入分组 + 新建自定义分类 + 删除自定义分类（预置不可删）
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **68/68**（含 6 条 widget 测试走完整 UI 路径）
- [x] M1 等价验收 8 项（真机，2026-09-10 用户确认通过）

> **坑 1**：Riverpod 3 未公开导出 `Override` 类型 → ProviderScope.overrides 别写类型注解。
> **坑 2**：`AsyncValue.valueOrNull` 在 Riverpod 3 已移除 → 用 `.value`。
> **坑 3**：go_router 实例必须是 App State 成员，不能是顶层 final——否则多个测试共享导航状态，前一个测试 push 过的页面会污染后一个测试。
> **坑 4**：showDialog 里的 TextField + controller 必须放 StatefulWidget，无状态 build 里 new controller 会丢输入。
> **坑 5**：测试里写库（create）是真实异步，pumpAndSettle 可能在写库完成前返回 → 用 pumpUntil(finder) 轮询。

## F4.5 首页改版 + 底部导航 ✅ 代码完成（2026-09-10，真机验收待做）

- [x] 全局深色主题（近黑底 #0C0C0C + 琥珀橙 #FFAF38，对齐 app_template/home_ui.jpg）
- [x] 底部导航 4 tab（首页/日历/资产/我的）+ 中央橙色「记一笔」；StatefulShellRoute.indexedStack
- [x] 日历 / 资产 = 占位页；「我的」= 占位骨架 + 分类管理入口
- [x] 首页：header（左=账本名开抽屉，右=搜索/报表/统计占位图标）+ 琥珀 hero 月支出卡（保留 ‹ › 翻月）+ 预算占位卡（纯静态）+「本月账单」列表
- [x] 账本抽屉：全部账本（当前高亮）+ 右下角「管理账本」
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **69/69**
- [x] 真机验收（首页视觉 + 抽屉切账本 + 底栏四 tab + 占位反馈）→ 2026-09-11 MuMu 12 走查通过

> **坑 6**：go_router `context.push` 的 Future 在 StatefulShellRoute 壳下**不兑现 .then 回调**
> → 保存后的列表刷新必须由记一笔页在 pop 前自己 `refresh()`，不能靠调用方 `.then`。

## F5 账单导入（M2 等价）✅ 代码完成（2026-09-10，真机验收待做）

- [x] `gbk_codec` 验证：纯 Dart 回环校验替代 U+FFFD 检测（gbk_bytesDecode 无 FFFD）；sdk 上界走 dependency_overrides
- [x] CSV 解析（逐字符状态机）+ 微信/支付宝 profiles（列名回退数组、方向映射、状态白/黑名单）
- [x] xlsx 解析：**不用 excel 包**（数值过 double 会丢 31 位单号精度）→ archive 解压 + 移植旧栈手写正则解析器；Excel 序列号本地时区换算
- [x] categorize 关键词规则（39 条有序表，模式小写化等价 /i）
- [x] importer：drift 单事务 + 指纹 IN 分批预查（参数绑定，escapeLiteral 不再需要）+ 文件内去重 + dryRun 哨兵回滚
- [x] 导入页 UI（我的页入口 → 选文件 → 预览可单条取消 → 确认导入 → 报告对话框 → 首页 refresh）
- [x] 门禁：移植 bill-import 6 组用例 + **真实件对拍逐行一致**（微信 xlsx 335 笔/导入 327、支付宝 GBK 32 笔/导入 28、31 位单号不丢精度）；`flutter test` **143/143**、analyze 0 issue
- [x] 真机验收（M2 等价 8 项）→ 2026-09-11 MuMu 12 走查全过（详见 `docs/acceptance-M1-M2.md`）


## F5.5 首次使用验收修复 ✅（2026-09-11）

用 `first-run-acceptance` 在 MuMu 12 隔离环境实走 M1/M2，报告 `docs/acceptance-M1-M2.md`。

- [x] **P1（阻断）** 导入成功但首页看不到数据、无引导 → `ledger_controller.jumpToMonth()`
      + 报告框拆「去看账单 / 完成」+ 月份说明
- [x] **P2（阻断）** 预算卡假数据与 hero 矛盾 → 「示例」标签 + 卡片底部说明（非真实数据）
- [x] **P3** 二次导入「导入完成 / 0 笔」自相矛盾 → 标题改「没有新增」；
      `ImportReport.uncategorized` 改为只统计真正入库的未匹配行
- [x] **P4** 首页空态不可见（大屏下被挤到折叠下方）→ 空态压成紧凑单行 + 「记一笔」入口 + 导入指路
- [x] **P5** 保存按钮藏在折叠下方 → 记一笔页 AppBar 加常驻「保存」
- [x] **P6** 预览页看不出如何取消单条 → 补勾选说明 + 全选/全不选
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **151/151**
      （146 + 新增 5 条回归：bill_importer P3 / import_page ×2 / home_empty_state / record_save_entry）

> **坑**：`find.widgetWithText(AppBar, '保存')` 返回的是 **AppBar 本身**，直接 tap 会点到标题区；
> 点击要用 `find.text('保存')`，前者只用于断言「在 AppBar 里」。


## F6 验收收尾

- [x] M2 等价验收 8 项（真机）→ MuMu 12 走查通过（SAF 唤起 / 微信 335→327 / 支付宝 GBK 32→28 /
      **二次导入 0 新增** / 翻月可见 / 退款跳过 / force-stop 持久化）
- [x] README / CHANGELOG 建立
  - [x] README 迁移进度表更新至 F5 完成，技术选型补全（archive 手写正则、file_picker、crypto、gbk_codec）
  - [x] 纠正 README 中 xlsx 选型误记（写 `excel` 包，实际是 `archive` + 手写正则）
  - [x] 新增 `CHANGELOG.md`（Keep a Changelog 格式，F0–F5 + Unreleased）
- [x] 旧仓库 README 顶部加「已迁移至 yanxin-flutter」说明

## F7 后续

### F7.1 日历页 ✅（2026-09-11）

- [x] 路由：`/calendar` 分支由占位页换成 `CalendarPage`；新增 `/month-picker` 子页路由
- [x] `CalendarController`（`calendarProvider`）：与首页 `ledgerProvider` 状态分离，各自记月份
- [x] `calendar_aggregate.dart`：按天聚合 / 日均支出（整数四舍五入）/ 紧凑金额，纯函数单测
- [x] 月历网格：日期下方标支出（负数·红）/ 收入（正数·绿），今天琥珀、选中日琥珀描边
- [x] 日历下方汇总条：月结余 + 日均支出（当月按已过天数、历史月按整月天数）
- [x] 选中日期账单区：日期头「今天 9月11日 周五」+ 流水列表；空态给「记一笔」入口
- [x] 月份选择子页：按年 12 个月缩略日历，有账日期标琥珀，点某天跳月选日并返回
- [x] 「记录某一天的账」：`/record?date=<ms>`，记一笔页新增「日期」字段（可改，上限今天）
- [x] 跨 tab 一致性：记一笔 / 删除后同时刷新首页与日历
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **166/166**（新增 15 条）

### F7.2 统计·报表页 ✅（2026-09-12）

- [x] 路由 `/stats`；首页 header「统计」图标由占位 SnackBar 改为真实入口
- [x] `stats_aggregate.dart`（纯函数）：`categoryBreakdown`（按分类汇总降序 + 占比）、
      `trendRange` / `monthlyTrend`（近 6 月、缺月补 0、跨年）
- [x] `StatsController`（`statsProvider`）：与首页 / 日历各自独立记月份；`shiftMonth` / `setKind` / `refresh`
- [x] 分类占比卡：`SegmentedButton` 支出/收入切换 + 自绘圆环（`category_pie.dart`）+ 图例（占比 + 千分位金额）
- [x] 近 6 月趋势卡：每月双柱（支出红 / 收入绿），`trend_bars.dart`
- [x] 当月汇总卡：收入 / 支出 / 结余；空态「YYYY年M月还没有支出记录」
- [x] 新增 `TransactionRepository.listByRange()`（跨月 / 跨年一次查齐）
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **179/179**（新增 13 条）

> **坑**：Flutter 3.32+ 起 `SegmentedButton` 的回调叫 **`onSelectionChanged`**，旧的 `onSelected` 已移除。
> **坑（本机）**：Windows 自带 `winsqlite3.dll` 不支持 `RETURNING` → 自带新版 `sqlite3.dll`（见 CHANGELOG 环境节）。

### F7.3 月度预算实装 ✅（2026-09-12）

- [x] schema v2：新增 `budgets` 表 + 部分唯一索引 `idx_budget_book_period`；
      `onUpgrade(from<2)` 只加表建索引（v1 五张表零改动）
- [x] `BudgetRepository`（`lib/data/repositories/budget_repository.dart`）：先查后写、软删、跨账本隔离
- [x] `budget_metrics.dart`（纯函数）：进度 / 剩余额度 / 本月日均 / 剩余每日可消费 / 超支
- [x] `BudgetCard` 替换 `budget_card_placeholder`（占位卡删除，「示例」chip 与说明文案移除）
- [x] 未设预算 → 空态引导；设置弹窗（快捷键 + 校验 + 删除二次确认）
- [x] `MonthBudgetController`（`monthBudgetProvider`）：watch 首页状态，翻月/换账本自动重查
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **199 通过 + 6 skip**（新增 26 条）
- [x] MuMu 15 真机：旧版本覆盖安装（v1→v2）不丢数据、设置/超支/删除/持久化/记一笔自动刷新全过

### F7.4 流水搜索 ✅（2026-09-12）

- [x] `TransactionRepository.listByBook(bookId)`：全时间、未删、倒序（搜索页一次读齐）
- [x] `search_query.dart`（纯函数）：`normalizeQuery` / `matchesQuery` / `filterTx` / `amountTextOf`
      —— 分类名 + 备注 + 金额三类取并集，空查询不返回全量
- [x] `search_controller.dart`（`searchProvider`）：内存过滤，逐键即时出结果，无需防抖
- [x] `/search` 全屏页：AppBar 即输入框（autofocus）+ **一键清空**；结果复用 `TxGroupList`（点=编辑、长按=删除）
- [x] 结果条 `共 N 笔 · 支出 X · 收入 Y`（复用 `summarize`）；超 200 条截断并提示
- [x] 三种状态：未输入（引导 + 示例词）、无结果（回显关键词 + 清空）、有结果
- [x] 首页 header 搜索图标接线（tooltip 去「建设中」）；删除/编辑后 `searchProvider` +
      首页/日历/统计/`yearDayIndex` 全刷
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **226 通过 + 6 skip**（新增 27 条）
- [x] MuMu 15 真机：分类 / 备注 / 金额各搜一次、一键清空、结果点开编辑、长按删除全过
- [x] **UI 微调**（2026-09-12 追加）：无结果态由 `Center` 居中改为**顶部对齐 + 占屏高 1/5**
      （`_NoResult`，高度按整屏算避开键盘压扁；内容紧凑化 + 滚动兜底）

### F7.5-a 搜索浮层化 + 类型筛选建议 ✅（2026-09-12）

- [x] `/search` 路由与 `SearchPage` 删除，改 `showGeneralDialog` 打开 `SearchOverlay`
      （首页留在页面栈里当背景，毛玻璃透出；文件改名 `search_page.dart` → `search_overlay.dart`）
- [x] 毛玻璃：`BackdropFilter(sigma 12)` 铺满全屏 + 半透明遮罩；**不透明**提示块盖住上半部分
- [x] 提示块：关闭按钮 + 输入框 + 一键清空 + 三个类型 chips（仅支出 / 仅收入 / 转账）
- [x] `search_query.dart` 新增 `SearchPlan` / `parsePlan` / `stripTypeWords`：类型词解析成
      `Transactions.type` 条件（**独立成词**才生效，多词**以最后出现为准**）；`filterTx` 改按 plan 过滤
- [x] chip 点击把词**填进输入框**（补尾随空格）+ 高亮由输入框内容推导；再点同一 chip = 取消
- [x] 三种关闭方式：关闭按钮 / 点玻璃空白区 / 系统返回键
- [x] 门禁：`flutter analyze` No issues found；`flutter test` **247 通过 + 6 skip**（新增 21 条）
- [x] MuMu 15 真机：SPEC §6 十条全过（老数据零丢失）；另修掉 3 个真机才暴露的问题
      （引导态空白点击关不掉 / chip 对勾致位移 / chip 后接着敲字失配），①③ 已补 widget 回归

> **坑（真机才暴露）**：① `SingleChildScrollView` 的 Scrollable 以 `HitTestBehavior.opaque` 命中
> 整块区域 → 盖在底层的「点空白关闭」手势收不到点击，改用 `Align` 只占内容高度；
> ② `ChoiceChip` 默认 `showCheckmark: true`，选中时会变宽把后面的 chip 挤位移 → `showCheckmark: false`；
> ③ 填入词与用户后续输入之间必须有**空格分隔**，否则类型指令不识别。

### F7.5-b 资产页（2026-09-17 交付，SPEC 已签字）

- [x] 小 SPEC `docs/SPEC-F7.5-assets.md`（已签字：范围全量、初始余额不允许负数）
- [x] `asset_aggregate.dart` 纯函数：`AssetItem` / `AssetSummary` / `buildAssetSummary`
      （余额 = 初始 + Σ收入 − Σ支出，**transfer 不计**；含 `txCount` 用于删除拦截）
- [x] `account_meta.dart`：账户类型 → 中文名 + 图标（cash / bank / credit / alipay / wechat / other）
- [x] `assets_controller.dart`：`AsyncNotifier<AssetSummary>`，watch 当前账本 + **数据版本号**；
      账户增 / 改 / 软删
- [x] `assets_page.dart`：净资产卡（≥0 琥珀橙 / <0 红）+ 账户列表（图标 / 名称 / 类型 + 累计收支 / 余额）+ 空态
- [x] `account_form_sheet.dart`：新增 / 编辑底部弹窗（名称 + 类型下拉 + 初始余额）；
      **有流水的账户禁止删除**（提示「还有 N 笔流水」）
- [x] `data_epoch.dart`：数据版本号 provider，5 个写操作点（记一笔 / 导入 / 首页删除 /
      日历删除 / 搜索删除）bump，替代「逐个 provider 手工 refresh」
- [x] `/assets` 分支的 `PlaceholderPage('资产')` → `AssetsPage`
- [x] 门禁：analyze 0 issue；test **269 通过 0 skip**（新增 16：聚合 10 + 资产页 widget 6）
- [x] **MuMu 12 真机走查（首次使用验收规范）**：15 步全过，阻断 0 / 卡住 0 / 状态丢失 0；
      报告 `docs/acceptance-F7.5b-assets.md`
- [x] 账户图标选择（体验摩擦 F1：`accounts.icon` / `color` 列已存在，界面未暴露）
      → **F7.7 C 批已实现**（schema v2→v3 补列 + 表单图标/颜色两块）→ `v0.7.9`

### F7.6 卡通浅色视觉改版（2026-09-23 全部交付，版本 `v0.7.6`，SPEC 已签字）

- [x] 小 SPEC `docs/SPEC-F7.6-cartoon-ui.md`（已签字：全站硬替换浅色 / 分 3 批 / 零新依赖）
- [x] **P1**（2026-09-18）：`core/theme/tokens.dart` + `toon.dart` 底座、`buildToonTheme`、底栏、
      首页（header / hero / 预算卡 / 流水列表 / 空态）、记一笔、分类弹层、删除弹窗、账本抽屉
- [x] **P2**（2026-09-19）：日历 / 月历格子 / 月份选择 / 统计 / 趋势柱 / 资产 + `ToonIconButton.muted` + `ToonDashedBorder`
- [x] **P3**（2026-09-23）：我的页 / 账本管理 / 分类管理 / 导入三步（步骤条 + 勾选行 + 报告卡）/
      日期选择弹层（新增 `date_picker_sheet.dart` + `MonthGrid.maxDate`）/ 预算弹层 / **账户弹层补做** /
      搜索浮层三态 / 资产页空态 / 日历留白微调 / **裸色值清零**
- [x] 令牌新增 `redInk`（`#A8321F`，红底提示条上的深红文字）
- [x] 门禁：analyze 0 issue；test **269 通过 0 skip**
- [x] **MuMu 12 真机走查**：13 屏全过（我的 / 分类 / 账本抽屉 + 账本管理 / 预算弹层与保存链路 /
      搜索三态 / 导入三步全链路 / 记一笔日期弹层 / 资产页空态 / 账户弹层增改删拦截），**阻断 0**
- [x] 走查补做：① 账户弹层其实没卡通化（P2 只取色，SPEC 误记「已复核」）；② 资产页 AppBar `+` 换 `ToonIconButton`
- [x] 版本记录：`v0.7.6` tag + `CHANGELOG.md` 顶部版本规则与 tag 表（F7 阶段一版一 tag）

### F7.7 backlog 五批（`docs/SPEC-F7.7-backlog.md`；**A–E 五批全部交付 ✅（v0.7.7 / v0.7.8 / v0.7.9 / v0.7.10）**）

- [x] 小 SPEC 起草（`docs/SPEC-F7.7-backlog.md`，`909c3dc`）：5 批 A→E，各打一个 tag `v0.7.7`…`v0.7.10`
      （**D/E 合并为一个 tag `v0.7.10`**）
- [x] **A 批签字**（2026-09-23）：A.0 做 / D.5 拼音不做 / E.5 农历不做；且裁定「报表页流水行只读不可点」
- [x] **A 批真机走查通过（2026-09-23，MuMu 12 无阻断）→ `v0.7.7` 已打 tag 并推远端**；
      F2 / F5 两项「待裁定」用户裁定**保持现状**不改
- [x] **A.0 前置**：记一笔支持选账户（第 4 个 `ToonField`「账户」+ `showAccountPicker()` 底部弹层；默认仍首个账户）
- [x] **A 报表明细清单**：新页 `/reports`（AppBar「报表」+ 月份切换 + `ToonSeg` 明细·分类·账户 + 独立记月份 + 卡通空态）
- [x] 4 处「报表（建设中）」占位点亮：首页 header→分类档 / 首页「全部账单」→明细档 /
      日历页 header→明细档+月份对齐 / 月份选择页 header→明细档+月份对齐
- [x] 口径：`listByMonth` 取数；分类档收支两段 + 转账单列；账户档按 `account_id` 聚合；软删/空 id 归「其他账户」
- [x] `TxTile` 回调改可空（支持只读行）+ `neutral`（转账行配色）；三处既有调用点行为不变
- [x] 新增测试 **18** 例：`report_aggregate_test`（9）/ `reports_page_test`（7）/ `record_account_test`（2）
      （⚠️ 2026-09-23 修正：此前写「20 例：11+7+2」是误记，静态计数实为 18）
- [x] **`flutter analyze` 0 issue** —— ✅ **等效达成**（2026-09-23）：`python tool/dart_analyze_fallback.py` →
      `No issues found!`（Python 托管**同一个** `analysis_server_aot.dart.snapshot` + 同一套 `analysis_options.yaml`；
      已用探针校准确认 lint 规则在线）。原理与协议三坑见 `docs/SPEC-F7.7-backlog.md` §G
- [x] **`flutter test` 的等效手段已入库** —— `tool/dart_test_fallback.py`（Python 起 `frontend_server`
      编译 + `flutter_tester.exe` 执行；参数抄 flutter_tools 源码）。**实测纯 `test()` 226 例全绿 / 0 失败**
- [x] **`flutter test` 全绿 0 skip（A 批）** —— ✅ **2026-09-23 用户终端全量通过（289 passed / 0 skipped）**
      （本机半验：纯 `test()` 226/226 全绿；63 个 `testWidgets` 本机跑不了，已由用户终端覆盖）。
      首轮反馈的 4 个失败已处理（3 个是测试写法问题已修 / 1 个 GBK 无法复现）；
      第二轮 `real_bills_test` 的 `loading` 已定性为「唯一在加载期做 IO 的文件」并加固（懒读 + 降级跳过）
- [x] **真机走查（A 批）阻断 0** —— ✅ 2026-09-23 用户 MuMu 12 走查通过
- [x] **tag `v0.7.7`**：✅ 已打并推远端（CHANGELOG `[Unreleased]` 已移成 `## [v0.7.7]`）
- [x] **B 数据导出**（✅ 已签字「全部按 B.4 默认」并实现，2026-09-23）：
      `csv_export.dart`（CSV 表头 日期,类型,金额,分类,账户,备注,来源 + BOM/CRLF/RFC4180；备份 JSON schemaVersion 2 金额整数分）+
      `export_sheet.dart` 底部弹层（SAF 保存、取消静默）+ 我的页入口 + `_BrandTip` 文案 + `budget_repository.listByBook`；
      新增测试 34 例（纯 31 全绿 ✅ 等效实测 + testWidgets 3 本机跑不了）；
      ✅ **真机走查已由 AI 经 adb 全包完成（2026-09-23）**：`gradlew assembleDebug` 直连构建（绕开 231）+ 装 +
      语义树/截图走查，CSV 与 JSON 两路径、SnackBar、取消静默、报表回归全过；
      ✅ **全部收尾（2026-09-23）**：`flutter test` 用户终端 **315 passed / 0 skipped**（达预期）+
      真机走查由 AI 经 adb 全包完成（`gradlew assembleDebug` 直连构建绕开 231）→ **`v0.7.8` 已打 tag 推远端**
- [x] C 账户图标 / 颜色（已签字开工，2026-09-23）：⚠️ SPEC 前提有误——accounts 表本来**没有** icon/color
      （在 books/categories 上）→ 实际做了 **schema v2→v3**（ALTER TABLE ADD COLUMN DEFAULT ''，
      onUpgrade 带 PRAGMA table_info 存在性防御）；表单加图标/颜色两块（跟随类型 + 8 候选）、
      资产页头像接自选值、仓储/controller 透传；新增纯测试 +14（account_meta 9 / account_repo 4 /
      db 迁移 1，等效实测全绿）+ analyze 0 issue；
      ✅ **全部收尾（2026-09-24）**：用户终端 `flutter test` **329 passed / 0 skipped**（达预期）+
      真机走查（MuMu 12，AI 经 adb 全包）**含 v0.7.8 老库覆盖安装验迁移**（老数据原样、新列落默认、
      改图标/颜色后重启仍持久、0 崩溃）→ **`v0.7.9` 已打 tag 推远端**（`f782ec2`）
- [x] D 搜索增强（2026-09-24 签字「DE都签字」）：⚠️ **SPEC 前提两处错**——§D.3 的「新建 `app_meta` 表 +
      schema 2→3」两处都不成立（`schema_meta` KV 早就存在、版本号也已到 v3）→ **复用既有 KV，本批零迁移**。
      实现：关键词高亮（分类/备注/**账户名**/金额，`core/utils/highlight.dart` 纯函数）、账户名命中、
      搜索历史（KV `search_history`，最近 10 条 / 去重 / 清空）、时间区间（全部/本月/近3月，独立一行 chips）；
      ✅ **全部收尾（2026-09-25）**：analyze 0 issue + 用户终端 `flutter test` **361 passed / 0 skipped**
      （本批 +32；改动的 search 纯测试 54 例本机实测全绿）+ 真机走查（MuMu 12，AI 经 adb 全包）通过，
      记录见 `docs/acceptance-F7.7-DE.md` → **`v0.7.10` 已打 tag 推远端**（`16b6a00`）。
      走查抓到并修 **1 个老 bug**：搜索结果是过期快照（`searchProvider` 未接 `dataEpochProvider`）
      → 「刚记一笔 / 刚加账户后搜不到」，已加回归测试 `search_freshness_test`
- [x] E 日历增强（2026-09-24 签字）：长按日历格子 → `/record?date=<**毫秒**>`（⚠️ SPEC §E.1 写的
      `YYYY-MM-DD` 与既有约定不符，改为毫秒）+ 顺带选中那天；左右滑动翻月（阈值 1/3 格宽，
      只注册横向 drag → 竖向仍归外层滚动）；
      ✅ **实现 + 走查完成（2026-09-24）**：与 D 批**合并打 `v0.7.10`**（✅ 2026-09-25 已打 tag 推远端）；
      走查通过（长按带对日期 / 左右滑翻月 / 右滑回退且日列表同步 / 竖向未误翻月 / 0 崩溃）；
      「竖向仍能滚动页面」由 widget 测试兜底（内容刚好一屏时真机测不出位移）
- [x] **F7.7 backlog 五批（A→E）全部落地** → 无待签字批次；下一轮等用户排新需求

### F7.8 流水左滑删除（用户新需求，2026-09-25 · **已交付 / 已打 `v0.7.11`**）

- [x] 小 SPEC 起草并签字（`docs/SPEC-F7.8-swipe-delete.md`，含 §7 三项用户裁定）：
      ① 长按取消、只留左滑；② 滑出红色「删除」按钮 → 点按钮才删（否掉「滑走即删」）；
      ③ 范围 = 首页 + 日历日账单 + 搜索结果 3 处（报表页流水行仍只读）
- [x] 通用件 `SwipeActionRow` + 纯函数 `resolveSwipeOpen`
      （`lib/features/ledger/presentation/widgets/swipe_action_row.dart`）：只注册横向 drag
      （竖向滚动 / 月历翻月不受影响）、84 px 动作区、行程 ≥45% 或向左甩 ≥350 px/s 吸附、
      160 ms easeOut、单开靠外层 `ValueNotifier<String?>`
- [x] 3 处接入：`TxGroupList`（首页 + 搜索浮层）、`calendar_page.dart` 的 `_SelectedDaySection`；
      `onDelete` 类型 `ValueChanged<TxRow>` → `Future<void> Function(TxRow)`；
      `TxTile` 摘掉 `onLongPress`（长按仍归日历格子「记这一天的账」）；
      **报表页未改**（不传回调 → 不包滑动件，保持只读）
- [x] 零新依赖（不引 `flutter_slidable`）、**不动 schema**（仍 v3）
- [x] 测试：改 2 例（`widget_test.dart` / `search_overlay_test.dart` 的长按用例 → 左滑口径）
      + 新增 10 例（`test/features/ledger/swipe_action_test.dart`：`resolveSwipeOpen` 5 + 行行为 5）
- [x] **`flutter analyze` 0 issue** —— 等效达成（`python tool/dart_analyze_fallback.py`）；顺带修掉 1 个
      `directives_ordering`（`calendar_page.dart` 新增 import 位置不合字母序）
- [x] **`flutter test` 371 passed / 0 skipped** —— ✅ **2026-09-25 用户终端全量通过**（本批 +10）
- [x] **真机走查（MuMu 12，AI 经 adb 全包）通过、0 崩溃** —— `docs/acceptance-F7.8-swipe-delete.md`：
      D1–D7 全过（左滑后金额节点 x `450 → 363` / 点动作区弹「删除这笔」/ 取消回弹且数据不动 /
      多行单开 / 点已展开行只收起不跳编辑 / 竖向滚动与月历翻月正常 / 报表页零位移无「删除」节点）
- [x] 走查抓到 **1 个只有真机能发现的视觉 bug**（未滑开时红色动作区透过行露出 —— `TxTile` 无自身底色）
      → 行包 `ColoredBox(color: Tok.paper)` 修复并复验
- [x] 新增 `tool/verify_apk_kernel.py`（装机前核 APK 内 `kernel_blob.bin` sha256 + grep 新文案，防「装到旧包」）
- [x] **tag `v0.7.11`**：✅ 已打并推远端（tag 对象 `6357de1` → 提交 `e984023`；CHANGELOG 已转正）

### F7.9 记一笔双保存入口收敛（用户新需求，2026-09-25 · **已交付 / 已打 `v0.7.12`**）

- [x] 小 SPEC 起草并签字（`docs/SPEC-F7.9-record-sticky-save.md`）：用户四选一裁定
      **底部主按钮改吸底常驻 + 删顶部入口**（否掉「去底部、只留顶部」）
- [x] `record_page.dart`：删 AppBar `actions` 的「保存」；`body` 改
      `Column(Expanded(滚动区) + 吸底栏)`，滚动区 bottom padding `24 → 16`
- [x] ⚠️ **SPEC 前提修正**：初稿写「用 `Scaffold.bottomNavigationBar`」**不成立** ——
      它按 `size.height - h` 贴**屏幕**底，只有 body 会被 `viewInsets.bottom` 压缩 →
      键盘弹起会被盖住。改 body 内 `Column`（已回写 §3 / §6）
- [x] 吸底栏：`Tok.paper` 底 + 顶部墨色描边（与 AppBar 底边对称）+ `SafeArea(top: false)` +
      `ToonButton(block: true)`（文案：新建「记一笔」/ 编辑「保存修改」）
- [x] 零新依赖、**不动 schema**（仍 v3）
- [x] 测试：重写 `record_save_entry_test`（矮视口 800×400 口径：AppBar 无「保存」/ 吸底按钮唯一且在视口内 /
      滚动 400px 后按钮 y 不变 / 走同一套校验）+ `record_account_test` 的 `_tapSave` 改点吸底按钮
      + **删 3 处 `ensureVisible`**（`widget_test` ×2 / `calendar_page_test` ×1 —— 吸底按钮不在
      `Scrollable` 内，`Scrollable.of` 返回 null 会直接抛错）
- [x] **`flutter analyze` 0 issue** ✅（等效达成）；顺带修 `sort_pub_dependencies` 1 条 info
- [x] **`flutter test` 372 passed / 0 skipped** —— ✅ **2026-09-25 用户终端全量通过**（本批 +1）；
      首轮曾 1 例失败（`home_empty_state_test` 仍断言 AppBar 有「保存」）→ **`661ec6b` 已修**
- [x] **真机走查（MuMu 12，AI 经 adb 全包）** ✅ 0 崩溃 —— `docs/acceptance-F7.9-record-sticky-save.md`：
      D1 无顶部入口 / D2 未滚动即在视口内 `@(450,1528)` / D3 矮视口 900×1000 后仍 `@(450,928)` /
      D5 保存链路（286.88 → 299.22）/ D6 编辑态文案「保存修改」/ D8 0 崩溃；
      ⚠️ **D4 键盘项未直接取证**（MuMu 有硬件键盘映射不弹软键盘）→ 改矮视口做等价验证
- [x] **tag `v0.7.12`**：✅ 已打并推远端（tag 对象 `dcab296` → 提交 `1f3ec96`；CHANGELOG 两段已合并转正）

### 启动图标 adaptive icon（2026-09-25 · **已交付 / 含于 `v0.7.12`**）

- [x] 问题：`flutter_launcher_icons` 只产 legacy `mipmap-*/ic_launcher.png`、**默认不产 adaptive** →
      API 26+ 回落 legacy，系统给图标**套白底 + 圆形遮罩**（真机一圈白边）
- [x] 补 `mipmap-anydpi-v26/ic_launcher.xml` + `values/ic_launcher_background.xml`（`#FFD81B`）+
      5 个 density 前景层（108/162/216/324/432）+ 前景源图（1024²、透明底、66% 安全区）
- [x] `pubspec.yaml`：`flutter_launcher_icons` 从 `dependencies` 移回 `dev_dependencies`（重复声明）+ 补配置段
- [x] 新增工具（纯 Python 标准库）：`tool/png_util.py` / `gen_launcher_icons.py` / `inspect_icons.py` / `check_pubspec.py`
- [x] **顺带修构建阻塞**（`b795541`）：`signingConfigs { }` 必须声明在 `buildTypes { }` **之前**，
      否则 `getByName("release")` 在配置阶段先求值报错，**连 `assembleDebug` 都挂**
- [x] 验证：`inspect_icons` + `check_pubspec` 全绿 + debug APK 构建成功（过 aapt2）+ 装机桌面无白底白圈

### F7.13 统计页图表两处绘制修复（用户反馈，2026-09-25 · **已交付 / 已打 `v0.7.13`**）

- [x] 问题：用户报「统计页面中的统计图样式有问题」→ MuMu 走查 + 截图放大定位到两处
- [x] **A · 分类占比圆环画成「风车楔形」**：`_DonutPainter` 的 `drawArc` 误传 `useCenter: true`
      —— 该参数**与描边样式无关**，为 true 时路径 `moveTo(圆心)` 再连回圆心，
      `strokeWidth = outer * 0.34`（约 25px）的粗描边把两条半径线画成实心带 → 五瓣叠成风车 + 盖住圆心文字。
      同项目 `toon.dart` 的 `_RingPainter` 传的是 `false`（对照即知是笔误）。**两处 → `false`**（含空态底槽）
- [x] 接缝改**两端各让一半**（`start + gap/2`、`sweep - gap`）：原先整段缝从瓣尾扣，
      首尾收口宽成 `gap·n`（5 瓣时 5.7° vs 其余 1.1°）；缝隙提为常量 `kDonutGap`
- [x] `_DonutPainter` → 公开 `DonutPainter`（纯 `test()` 内可直接构造）
- [x] **B · 趋势图零值月仍画柱**：`_Bar` 里 `cents == 0 → height = 2.0` 的基座占位 →
      4 个月无数据看着像「每月都有小额收支」→ 用户裁定**不画**；抽纯函数
      `double? trendBarHeight(cents, max)`（**返回 null = 不画**；`cents <= 0 || max <= 0` 都走 null，顺带挡住除零）
- [x] `_Bar` 早退 `if (height == null) return SizedBox(width: kTrendBarWidth)` —— **保留同宽占位**，
      否则有数据的柱子会左右漂移、标签错位；宽度硬编码 13 → 常量 `kTrendBarWidth`
- [x] 零新依赖、**不动 schema**（仍 v3）
- [x] 测试 **+11**（纯 `test()` 10 + `testWidgets` 1）：`category_pie_test.dart` 5 例（**记录型 Canvas** ——
      `implements Canvas` + `noSuchMethod` 只实现 `drawArc` / `drawCircle`，直喂 painter 断言入参）+
      `trend_bars_test.dart` 5 例（0 分 → null / `max = 0` 全不画 / 等比缩放 / 极小金额仍正高 / 负数按无数据）+
      `stats_page_test.dart` +1 例（独立 pump `TrendBars`，断言 `Tooltip` 恰好 1 个 + 无数据月标签仍在）
- [x] **`flutter analyze` 0 issue** ✅（等效达成）
- [x] **`flutter test` 383 passed / 0 skipped** —— ✅ **2026-09-25 用户终端全量通过**（本轮 +11）
- [x] **真机走查（MuMu 12，AI 经 adb 全包）** ✅ 0 崩溃 —— `docs/acceptance-F7.13-stats-charts-fix.md`：
      圆环无楔形、缝隙均匀；4–7 月零柱、8/9 月柱位置与高度**零漂移**（前后对比图在 `.workbuddy/qa-stats/`）
- [x] ⚠️ 踩坑：`gradlew` 必须在 `source env.sh` **之后**跑 —— 否则 `GRADLE_USER_HOME` 未注入 →
      `journal-1.lock (拒绝访问。)` 2 秒即 BUILD FAILED（像「构建链路坏了」，实为环境变量缺失）
- [x] **tag `v0.7.13`**：✅ 已打并推远端（tag 对象 `19fb246` → 提交 `0773333`；CHANGELOG 已转正）

### F7.7-a 首次使用验收（2026-09-23，报告 `docs/acceptance-first-run.md`）

验收对象：零配置新用户「第一次打开 → 记下第一笔账 → 在首页 / 报表看到这笔账被正确归集」。
手法：数据层**实跑**（`python tool/data_layer_probe.py`，真实仓储 + 真实聚合，内存库，**13/13 断言通过**）
+ UI 层静态走查（本机跑不了 UI）。六维度：D1 通过 / D2 通过（A 类前置 0）/ D3 部分 / D4 通过 /
**D5 不通过** / D6 部分。

- [x] **F1（阻断）报表页不随写操作刷新** —— 新用户顺着报表空态「去记一笔」记完第一笔，回报表仍显示「这个月还没有记账」
      （`reportsProvider` 常驻 + `/record` push 在其上；`ReportsController.refresh()` 全库零调用）
      → 修：`build()` 里 `ref.listen(dataEpochProvider) → refresh()`（保留档位 / 月份，**不用 `watch`**）
- [x] 新增测试 2 例（`reports_page_test` 7 → 9）：空月写账后自动刷新且保留档位 / 翻月后写账仍停原月
- [x] 新增工具 `tool/data_layer_probe.py` + `tool/data_layer_probe.dart`（`flutter test` 不可用时的数据层替代）
- [x] **F2（已裁定 · 保持现状，2026-09-23）** 首页 header「报表」与「全部账单 ›」**不带年月** → 报表落到「它自己记得的月份」
      （日历页 / 月份选择页入口都带）。SPEC §A.2.3 未写这两条
- [ ] **F3（反馈不可懂）** 8 处 `加载失败：$e` 直出异常字符串、无重试 → 抽 `LoadFailure`，先接首页 / 报表页
- [ ] **F4（摩擦）**「我的 → 设置」副标题承诺「主题、默认账户、货币单位」但整行不可点（文案 1 行）
- [x] **F5（已裁定 · 保持现状，2026-09-23）** 入口「全部账单 ›」vs 落地页标题「报表」（SPEC 要求入口文案保持）
- [ ] **F6（摩擦）** 记一笔页返回即丢已输金额 / 备注（可加 `PopScope` 二次确认）

### F7.5 剩余项（待排期 · **属新产品功能，须先出小 SPEC 并签字**）

- [x] 资产页（F7.5-b 已交付）
- [x] 数据导出（「我的」页占位 → **F7.7 B 批已实现**，`v0.7.8`）
- [ ] 分类预算（每个分类单独额度）
- [x] 搜索增强：关键词高亮、账户名匹配、搜索历史、日期区间筛选、拼音 / 首字母匹配
      （转 F7.7 D 批 → ✅ `v0.7.10`；**拼音 / 首字母匹配用户裁定不做**）
- [x] 日历增强：农历 / 节假日、长按某天快速记一笔、日历页内直接改月份
      （转 F7.7 E 批 → ✅ `v0.7.10`；**农历 / 节假日用户裁定不做**）
- [x] 报表：按分类/账户的明细清单 —— 即首页/日历页 header 的「报表」占位（**F7.7 A 批已实现**）

> **F7.3 坑**：① drift 的数据库迁移必须在**真机覆盖安装**路径上验，内存库单测只能证明
> `onUpgrade` 逻辑本身；② Riverpod 3.4.3 的 `AsyncNotifierProvider.family` 没有稳定的取参入口
> （`FamilyAsyncNotifier` 已移除），需要「按月份取数」的 provider 时，改成 watch 首页状态更稳。

### F7.14 新手引导（7 页全屏导览）—— 用户新需求，**已交付 ✅ `v0.7.14`**（2026-09-25）

> 需求：让第一次使用的用户知道「没有明显标识的按钮 / 隐藏手势」是做什么的。
> SPEC：`docs/SPEC-F7.14-onboarding.md`（用户裁定四项：全屏分页导览 / 四项内容全覆盖 /
> 「我的」新增重看入口 / **老用户不弹**）。**零新依赖、不动 schema（KV 复用 `schema_meta`，DB 仍 v3）**。

- [x] 调研：全站 **17 处**「无文字 / 只有手势」入口（底栏中央歪 4° 方块、首页三图标、日历三图标、
      hero `‹ ›`、预算铅笔、资产页 `+` 与账户行、报表三档；**3 处连 tooltip 都没有**的隐藏手势：
      日历长按记账 / 月历左右滑翻月 / 流水左滑删除）
- [x] SPEC 起草 + 用户签字（四项裁定）
- [x] 新增 `lib/features/onboarding/`（keys / prompt provider / page / slides / art 共 5 个文件）
- [x] 7 页内容：欢迎 → 中央「记一笔」→ 右上三图标 → 翻月 + 预算铅笔 → 三个隐藏手势 → 资产页与报表页 → 完成
- [x] 迷你示意图**全矢量手绘**（`MiniScreen` / `HighlightBox` / `Callout`；复刻真实比例与 IconData；零图片资源）
- [x] 判定逻辑：「无 `onboarding_done`」**且**「本次启动前无主账本记录」（`isFreshInstall`）才弹
      —— ⚠️ 不能用「走了 `ensureDefaultBook` 分支」当判据（当前账本被软删也会命中）
- [x] 「看过」标记收口在 `dispose()`（跳过 / 完成 / 系统返回三条 pop 路径一处写入；失败静默）
- [x] 接线：`/onboarding` 路由 + `AppShell` 首帧后触发 + 「我的」条目卡首位入口
- [x] 测试基建：`pumpApp` 默认预写标记（否则内存库=全新安装，首启弹窗会打断既有 9 个测试文件）
- [x] 新增 `onboarding_slides_test.dart`（10 例纯 `test()`）—— 本机实测 **10 passed** ✅
- [x] 新增 `onboarding_flow_test.dart`（7 例 `testWidgets`）
- [x] analyze 等效：**新增文件单独跑 `No issues found!`** ✅
- [x] analyze 等效：全项目残留 5 个 error 均为 `D://`/`d://` 双身份**既有环境假阳性**（未改动的
      `lib/features/ledger` 单独跑即复现 3 个）；**本批新增文件 0 issue** ✅
- [x] **用户终端 `flutter test`：400 passed / 0 skipped** ✅ = `test()` 312 + `testWidgets` 88（本批 +17）
- [x] 真机走查 **D1–D10 全部通过、0 崩溃** ✅（MuMu 12 / 900×1600 @320dpi，AI 经 adb 全包）
      → `docs/acceptance-F7.14-onboarding.md`（首启弹 / 已看过不弹 / **老用户不弹且不被误写标记** /
      **系统返回也写标记** /「我的」入口可重看 / 矮视口不溢出 / 引导前后业务数据零改动）
- [x] 收尾四步已执行：CHANGELOG 转正 `## [v0.7.14]` + tag 表补行 → 我的页角标 `v0.7.14`（随代码批 `02f9041`）
      → `git tag -a v0.7.14`（tag 对象 `b3c08c2` → 提交 `c5ea1b5`）→ 直推 + `ls-remote` 核对
      → 文档收尾（HANDOFF / SPEC §8 / 本文件 / memory）

### F7.15 自动记账（通知使用权为主 + 零权限兜底）—— 用户新需求，**已实现、待验收 🔵**（2026-09-30）

> 需求：用户要「自动记账」，并先问权限方案；选完组合后又追加「能不能在通知栏里确认入账」。
> SPEC：`docs/SPEC-F7.15-auto-bookkeeping.md`（**已签字**：方案 A + D3 + 强化导入 / 静默直入 /
> 按来源建账户 / 仅微信+支付宝 / **设计乙 = 静默入账 + 通知栏回执（撤销·查看）**）。
> **零新 pub 依赖、零 Gradle 新依赖、不动 schema**（批次记录复用 `schema_meta` KV，DB 仍 v3）。

- [x] 现状盘点：`transactions.source` 注释早已预留 `notification|shortcut`；`fingerprint.dart` 与
      `transaction_repository.dart:5` 的文档都写着「供自动记账调用」→ 数据层**无需改动**
- [x] SPEC 起草 + 用户签字（四项裁定 + 设计乙改选 + §3.5 忽略规则默认值）
- [x] Android 侧（**本项目首次**平台通道）：`AutoBookListenerService`（包名白名单 + 5 秒粗筛 + 入队）/
      `AutoBookQueue`（JSONL 队列 + 命令文件 + 500 条 / 7 天纪律）/ `AutoBookNotifier`（两态通知 +
      `撤销`·`查看` + `IMPORTANCE_LOW` + `FLAG_IMMUTABLE`）/ `AutoBookChannel`（8 个方法）
- [x] `MainActivity` 接线（注册通道 + `ACTION_SEND` 文本入队 + 通知按钮落命令）+ `AndroidManifest`
      （`POST_NOTIFICATIONS` / `<service>` `exported=false` + `BIND_NOTIFICATION_LISTENER_SERVICE` /
      `ACTION_SEND` filter）+ 矢量通知小图标 `ic_stat_autobook.xml`
- [x] Dart 侧：`lib/features/autobook/`（rules / bridge / batches / accounts / controller / notice /
      page / banner 共 8 个文件）+ `/autobook` 路由 + 「我的」条目 + 首页提示条 + `AppShell` drain 触发点
- [x] `ImportReport` 追加 `importedIds` / `importedAmountCents`（有默认值 → 既有调用方零改动）
- [x] 新增 `auto_book_rules_test.dart`（**38 例纯 `test()`**）+ `auto_book_flow_test.dart`（**9 例纯 `test()`**）
      —— 本机实测 **47 passed** ✅
- [x] analyze 等效：**全项目 `No issues found!`** ✅
- [x] 本机回归：core 39 / data 25 / import 74 / assets 19 全绿 ✅
- [x] 构建 debug APK（`build_kernel_fallback.py` + `gradlew assembleDebug -x compileFlutterBuildDebug`）
      → 验证 **Kotlin 首编译通过**（这是首条平台通道，必须真编一次）
- [x] **门禁期修复**（2026-09-30）：终端全量 `flutter test` 报 `budget_card_test` 两条用例失败
      → 根因 = **月末 flake**（「剩余额度」与「剩余每日可消费」在当月最后一天必然同值，
      裸 `find.text(数值)` 命中 2 个），非 F7.15 引入 → 改按容器定位 + 日期相关值不写字面量，
      并加纯函数守卫（提交 `a545687`；详见 CHANGELOG `[Unreleased] · G · 修复`）
- [ ] **用户终端重跑**：先单跑 `flutter test test/features/ledger/budget_card_test.dart` 复核这 2 条，
      再跑全量 `flutter test`（本机跑不了 14 个 `testWidgets` 文件；
      `test/data/repositories/transaction_repository_test.dart` 在本机 runner 里编译阶段挂住）
- [ ] **真机走查**：`adb shell cmd notification post` 造合成通知 → 验「解析 → 去重 → 入账 → 撤销 → 回执通知」；
      权限引导页（去开启 / 返回自检 / 通知权限被拒态）；分享记账；首页提示条与 `/autobook` 页
- [ ] **用户在自己手机上抓真实通知文案回填规则表**（模拟器验不了真实格式）→ 视情况调整 §3.5 忽略规则
- [ ] 收尾四步：CHANGELOG `[Unreleased]` 转正 `## [v0.7.15]` + 我的页角标 → tag → 直推核对 → 文档收尾
