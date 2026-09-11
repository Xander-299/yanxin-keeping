# 变更日志

本项目变更记录格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

> 迁移期（F0–F6）尚未发布正式版本号，先按「阶段 / 日期」归档；首个正式版发布后改为语义化版本号。

## [Unreleased]

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
