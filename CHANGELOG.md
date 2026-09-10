# 变更日志

本项目变更记录格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

> 迁移期（F0–F6）尚未发布正式版本号，先按「阶段 / 日期」归档；首个正式版发布后改为语义化版本号。

## [Unreleased]

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
