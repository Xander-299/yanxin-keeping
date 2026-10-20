# 颜芯记账（Flutter 版）

本地优先的个人记账 App。Flutter 3.47.2 / Dart 3.13.2，目标平台 **Android**。

**数据全部留在手机本地** —— 无账号、无服务器、无网络请求、无广告、无埋点。

---

## 📲 快速体验（不用装任何开发环境）

直接下载 **release APK** 装到手机即可：

| 版本 | 适用设备 | 大小 | 下载 |
|---|---|---|---|
| **通用包**（推荐） | 绝大多数手机（arm64 / armv7 / x86_64 全含） | 64 MB | [下载](https://github.com/Xander-299/yanxin-bookkeeping-flutter/releases/download/v0.7.16/yanxin-v0.7.16-universal-release.apk) |
| **arm64 单独包** | 只想给现代 arm64 机（体积小 2/3） | 22 MB | [下载](https://github.com/Xander-299/yanxin-bookkeeping-flutter/releases/download/v0.7.16/yanxin-v0.7.16-arm64-release.apk) |

- Release 页：<https://github.com/Xander-299/yanxin-bookkeeping-flutter/releases/tag/v0.7.16>
  > 📦 v0.7.16 的安装包仍在旧仓库的 Release 下；从下一版起发到本仓库。
  > 自己出包见 [方式三](#方式三从源码构建)。
- 版本 **0.7.16**（versionCode 2001）· 最低 **Android 7.0** · 正式签名（`CN=yanxin`）
- 安装说明与自动记账配置见 👉 **[部署与体验教程](#-部署与体验教程)**

---

## 🧭 功能地图

### 核心记账

| 模块 | 路由 | 做什么 |
|---|---|---|
| **首页流水** | `/` | 按天分组的流水列表、月份切换（‹ ›）、月度收支 hero、预算卡；**左滑露出红色「删除」** |
| **记一笔** | `/record` | 自绘金额键盘 + 分类宫格 + 备注 + **日期选择** + **账户选择**；底部主按钮吸底常驻（随键盘上移） |
| **搜索** | 浮层（**不是路由**） | 覆盖首页的毛玻璃浮层；命中 **分类名 / 账户名 / 备注 / 金额「元.分」文本**；支持「仅支出/仅收入/转账」类型指令 + 时间区间（全部/本月/近3月）+ 命中高亮 + 搜索历史 |
| **日历** | `/calendar` | 月历标注（支出红 / 收入绿）、日汇总、选中日账单；**长按格子 → 记这一天的账**、**左右滑翻月** |
| **统计** | `/stats` | 分类占比圆环（自绘 `CustomPainter`，不引图表库）、近 6 月趋势双柱、当月汇总 |
| **报表** | `/reports` | 三档切换：明细清单 / 分类汇总 / 账户汇总；每组最多 200 行 |
| **预算** | 首页卡 | 月度预算设定、环形进度、日均支出、**剩余每日可消费**；超支预警 |
| **资产** | `/assets` | 净资产卡 + 账户列表（类型图标 / 名称 / 余额）；账户增改删（**有流水的账户禁删**） |

### 数据进出

| 模块 | 做什么 |
|---|---|
| **账单导入** | 微信（旧版 CSV / 2025+ xlsx）、支付宝（旧版 CSV / 新版 GBK 回单）；**解析五层** + 指纹幂等入账 + 试算报告 |
| **数据导出** | 流水 CSV + 完整备份 JSON；走 **SAF 系统文件选择器**（免存储权限） |
| **账本 / 分类 / 账户** | 多账本切换与管理、分类增删改、账户图标与颜色 |

### 自动记账（可选）

| 模块 | 做什么 |
|---|---|
| **通知监听自动入账** | 监听**微信 / 支付宝**的支付通知 → 自动解析金额方向 → 静默入账 → 发「已自动记账 N 笔」回执通知（可**一键撤销**）；三层采集 + 活性诊断页 |
| **分享记账** | 零权限兜底：在微信/支付宝里「分享」账单文本到本 App → 同样自动入账 |

### 其它

- **新手引导**：首次安装弹 7 页全屏导览（可从「我的 → 新手引导」重看）
- **主题**：全站**卡通浅色**一套设计令牌（`Tok.*`），产品代码零裸色值

---

## 🔔 自动记账是怎么工作的

```
系统绑定 NotificationListenerService
  → Kotlin 只做「包名过滤 + 取文案 + 落盘 JSONL」（不解析、不碰库）
  → Dart drain() → 纯函数解析（金额 / 方向 / 商户）→ importRows()（drift 唯一 DB writer）
  → 记批次 → 首页提示条 + 「已自动记账 N 笔」回执通知（可一键撤销）
```

**三层采集**（因为支付通知在国产 ROM 上极不可靠）：

| 层 | 通道 | 触发 | 实测（Redmi K50） |
|---|---|---|---|
| 1 | `onNotificationPosted` | 通知发布 | ⚠️ 该机型**完全不投递** → 降级为可选加速 |
| 2 | `AutoBookGuard` 补抓守护 | `AlarmManager` 60s 周期 + 醒来续期 | ✅ 每 ~53 秒准点 |
| 3 | `onNotificationRemoved` | 通知被撤回那一刻 | ✅ 实测**独立救回过 1 笔** |

三层**共用同一条判定链 + 持久指纹集** → 同一笔不会记两遍。

> 为什么需要第 3 层：支付通知**只活 26 秒**（点进「支付成功」页微信就 `cancel()`），
> 撤回后连 `getActiveNotifications()` 都捞不到 → 撤回那一刻是**唯一**的救援窗口
> （Android 保证此时 `extras` 仍完整，只丢 `contentView` / `largeIcon`）。

**诊断**：App 内「我的 → 自动记账」有诊断页，逐层显示「服务有没有绑上 / 最近捕获 / 待入账 / 上次检查结果」，
出问题时先看它，能直接定位是哪一层断了。

---

## 🏗️ 项目结构

```
lib/
├── app.dart                     路由表（go_router：壳路由 + 全屏页）
├── main.dart                    入口（ProviderScope + drift 初始化）
├── core/                        基础设施（不依赖任何 feature / data）
│   ├── db/                      drift 数据库：tables / database / schema_v1 / schema_v2
│   ├── providers/               data_epoch（写操作后的统一失效信号）
│   ├── theme/                   tokens.dart（设计令牌）+ toon/（卡通通用件，按组件分文件）
│   ├── utils/                   money / id / fingerprint / date / highlight
│   └── constants/               preset.dart（预置分类、账户类型、默认账本名）
├── data/
│   ├── providers/               数据层 DI：database + book / account / category 等 provider
│   └── repositories/            6 个仓储：book / account / category / transaction / budget / app_meta
└── features/                    按业务垂直切分，每个模块 application（逻辑）+ presentation（UI）
    ├── nav/                     AppShell：抽屉 + 底栏 4 tab + 壳路由
    ├── ledger/                  首页：LedgerController / MonthHero / BudgetCard / TxGroupList / SwipeActionRow
    ├── record/                  记一笔：金额键盘 / 分类宫格 / 日期选择 / 账户选择
    ├── calendar/                日历：CalendarController / MonthGrid / MonthPickerPage
    ├── stats/                   统计：stats_aggregate / CategoryPie / TrendBars
    ├── reports/                 报表：report_aggregate / ReportsController / ReportGroupList
    ├── search/                  搜索：search_query（命中口径）/ SearchOverlay / 搜索历史
    ├── assets/                  资产：asset_aggregate / account_meta / AccountFormSheet
    ├── import/                  导入：解析五层（bill_decode / bill_xlsx / bill_csv / bill_parse / bill_profiles）
    ├── export/                  导出：csv_export / ExportSheet
    ├── autobook/                自动记账（Dart 侧）：rules（解析规则）/ bridge / batches / diagnostics / controller / page
    ├── onboarding/              新手引导：7 页导览 + 矢量插画
    ├── book/ category/ profile/ 账本管理 / 分类管理 / 我的
    └── shared/                  跨模块共用小部件（命名弹窗）

android/app/src/main/kotlin/com/teacodeman/yanxin/
├── MainActivity.kt              MethodChannel 接线
└── autobook/                    自动记账原生侧（7 文件）
    ├── AutoBookListenerService.kt   通知监听 + 三层采集判定链
    ├── AutoBookGuard.kt             AlarmManager 补抓守护层
    ├── AutoBookQueue.kt             JSONL 落盘队列（取走即清空 + 失败回写）
    ├── AutoBookSeen.kt              持久指纹集（补抓去重）
    ├── AutoBookDiagnostics.kt       跨进程诊断落盘
    ├── AutoBookNotifier.kt          回执通知（撤销 / 查看）
    └── AutoBookChannel.kt           平台通道

tool/                            开发工具链（Python + Dart）：门禁等效 / APK 核验 / 发布 / 设备调试
test/                            52 个测试文件 · 485 个用例（目录与 lib/ 结构镜像）
docs/spec/                       各阶段签字的 SPEC
docs/dev/                        真机走查手册、Windows 环境重建
docs/handoff/                    交接档案（reference 长期参考 / session-log 逐轮记录）
docs/acceptance-*.md             各阶段真机走查验收报告
docs/design/                     页面原型参考图
```

### 分层约定

```
presentation（UI）→ application（Controller / 纯函数）→ data（仓储 / 规则）→ core（基础设施）
```

- **drift 是唯一 DB writer** —— Kotlin 侧只落盘，不碰数据库。
- **纯函数优先** —— 解析规则、金额计算、命中口径、聚合统计全部是无副作用纯函数，`test()` 直接覆盖。
- **常驻 provider 必须 `ref.watch(dataEpochProvider)`** —— 否则「刚记一笔后搜索搜不到」这类过期快照 bug 会回来。
- **纯 UI 的模块可以只有 `presentation/`** —— `book` / `category` / `profile` / `nav` 的数据与状态
  在 `lib/data/providers/` 或对应 controller 里，这是有意为之的例外，不是漏了 `application/`。

---

## 🛠 部署与体验教程

### 方式一：装 APK 体验（推荐给非开发者）

1. **下载** —— 用上面表格里的链接，或打开 [Release 页](https://github.com/Xander-299/yanxin-bookkeeping-flutter/releases/tag/v0.7.16) 点资产。
2. **传到手机** —— 数据线 / 微信「文件传输助手」/ 网盘都行。
3. **安装** —— 用文件管理器点 APK 安装。系统提示「未知来源」时，允许**当前这个文件管理器**安装即可。
4. **启动** —— 桌面出现黄色「记账」图标。首次会弹 7 页新手引导，滑完即可用。

> ⚠️ **不要从应用商店找** —— 本项目未上架应用商店。
> ⚠️ 卸载即删除全部数据（无云端）。想留档请先「我的 → 数据导出」。

### 方式二：开启自动记账（可选）

手动记账开箱即用。想让 App **自动从微信/支付宝通知里记账**，需要两步授权：

**第 1 步 · 授予「通知使用权」**

| 品牌 | 路径 |
|---|---|
| 小米 / Redmi | 设置 → 通知与控制中心 → 通知使用权 → 找到「颜芯记账」→ 打开 |
| 华为 / 荣耀 | 设置 → 应用和功能 → 应用管理 → 颜芯记账 → 通知使用权 → 打开 |
| OPPO / vivo / 小米 | 设置 → 通知管理 → 通知使用权（各机型叫法略有差异） |

**第 2 步 · 允许发通知**：系统设置 → 应用 → 颜芯记账 → 通知 → 打开。

**第 3 步 · 验证**：去微信/支付宝付一笔钱（任意金额），然后**打开一次本 App** —— 流水应自动出现，首页顶部显示「已自动记账 1 笔 · 合计 ¥x」。

> ⚠️ **国产 ROM 必读**（小米/Redmi 实测踩过的坑）：
> - **强行停止 App 或覆盖安装后，系统会自动解绑通知监听服务**（但设置里仍显示「已开启」）。
>   → 遇到「自动记账不生效」，**把通知使用权关掉再打开一次**即可恢复。
> - 支付通知在部分 ROM 上**只存活约 26 秒**（点进「支付成功」页就被撤回）。
>   → **付完款后尽快打开一次本 App**，它会主动回捞通知栏里还存在的记录。
> - App 内「我的 → 自动记账」有**诊断页**，逐层显示「服务有没有绑上 / 最近捕获 / 待入账 / 上次检查结果」，
>   出问题时先看那一页，能直接定位是哪一层断了。

### 方式三：从源码构建

**环境要求**：Flutter 3.47.2（Dart 3.13.2）· JDK 17 · Android SDK（platform 36 + build-tools 36）· Git。

```bash
git clone git@github.com:Xander-299/yanxin-flutter.git
cd yanxin-flutter

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 drift 代码（改表结构后必须重跑）

flutter test          # 门禁
flutter analyze

# 出包（release）
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> ⚠️ **依赖版本是锁死的，别随手升级**：
> `drift 2.31.0` / `sqlite3 2.9.4` / `build_runner 2.15.1` / `flutter_riverpod ^3.4.3` / `go_router ^18.0.1`。
> sqlite3 3.x 起带 native-assets 构建钩子（需本机 MSVC），build_runner 2.16+ 要求 analyzer ≥13 与 drift_dev 冲突。

> ⚠️ **release 签名**：`android/key.properties`（**不入版本控制**）四键齐全时用正式签名，
> 缺失时自动回退 debug 签名 —— 所以 clone 仓库的机器也能出包。
> ⚠️ `android/local.properties` 也**不入版本控制**，且**会被 flutter 工具改写**（跑一次 `flutter build` 就重写）。
> 装机前用 `aapt dump badging <apk> | head -1` 确认 versionCode。

### 方式四：发一个 Release

```bash
# 1. 构建（产物在 build/app/outputs/flutter-apk/）
flutter build apk --release --target-platform android-arm,android-arm64,android-x64

# 2. 发布到 GitHub Release（令牌从 git credential manager 现场取，不落盘）
python tool/publish_release.py --tag v0.7.16 \
    --name "颜芯记账 v0.7.16" \
    --notes-file docs/release-notes-v0.7.16.md \
    --apk build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔧 技术选型

| 关注点 | 选型 | 理由 |
|---|---|---|
| 数据库 | **drift 2.31.0** + sqlite3 2.9.4 | 编译期参数绑定（根治旧栈手写 SQL 拼接）；**零迁移**演进到 schema v3 |
| 状态管理 | **Riverpod 3** | 常驻 provider + `dataEpoch` 版本号，替代逐个手工 refresh |
| 路由 | **go_router 18** | `StatefulShellRoute` 壳路由（底栏 4 tab 保留各自页面栈） |
| 金额 | **`int` 分** | 全程整数，**禁止浮点**（0.1 + 0.2 问题不存在） |
| 主键 | UUID v4 | 客户端发号，离线可用 |
| 入账指纹 | `crypto` SHA-1 | 纯 Dart，无 native 钩子 |
| 文件选择 | `file_picker` | Android SAF，免存储权限 |
| xlsx 读取 | `archive` + 手写正则 | **不用 `excel` 包**：数值过 double 会丢 31 位单号精度 |
| CSV / GBK | 自研逐字符状态机 + `gbk_codec` | 无成熟纯 Dart 方案；回环校验判坏件 |
| 自动记账 | **Kotlin 原生**（`NotificationListenerService` + `MethodChannel`） | **零新增 pub 依赖**；Dart 侧只做纯函数解析，drift 单写者 |

---

## 📚 文档索引

| 文档 | 内容 |
|---|---|
| [`CHANGELOG.md`](CHANGELOG.md) | 版本变更记录 + tag 表 |
| [`HANDOFF.md`](HANDOFF.md) | 交接文档：当前状态、决策依据、踩坑记录 |
| [`SPEC-flutter-migration.md`](SPEC-flutter-migration.md) | 迁移总 SPEC（已签字） |
| [`docs/PRD-yanxin-flutter.md`](docs/PRD-yanxin-flutter.md) | 功能需求汇总（FR 编号 + 状态） |
| [`docs/spec/SPEC-F7.15-auto-bookkeeping.md`](docs/spec/SPEC-F7.15-auto-bookkeeping.md) | 自动记账 SPEC（架构 / 忽略规则 / Android 硬约束） |
| [`docs/acceptance-*.md`](docs/) | 各阶段真机走查验收报告 |
| [`tasks/todo-flutter.md`](tasks/todo-flutter.md) | 迁移任务清单 |
| [`docs/release-notes-v0.7.16.md`](docs/release-notes-v0.7.16.md) | v0.7.16 Release 说明（安装 + 权限 + 隐私） |
| [`docs/RESUME.md`](docs/RESUME.md) | **简历用项目介绍**（规模 / 技术难点 / 迭代记录 / 为什么要重写） |

---

## 📊 项目规模

| 维度 | 数据 |
|---|---|
| 代码量 | Dart **98 文件 / 25,361 行** · Kotlin **8 文件 / 1,507 行** |
| 测试 | **52 个测试文件** · 485 个用例（静态计数，另有 18 处数据驱动循环展开） |
| 迭代 | **140 次提交** · **16 个版本 tag**（`v0.7.1`–`v0.7.16`） |
| 验证环境 | MuMu 模拟器 + **Redmi K50 真机**（MIUI/HyperOS，adb 全包走查） |

---

## 📄 License

仅供学习与个人使用。
