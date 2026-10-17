# 颜芯记账（Flutter 版）

本地优先的个人记账 App。Flutter 3.47.2 / Dart 3.13.2，当前目标平台 **Android**。

> 这是 uni-app 版的**重写**。旧仓库 `Tea-Codeman/yanxin-bookkeeping`（uni-app Vue3 + Vite）已归档为只读，不再开发。
>
> 📅 **本文状态核对于 2026-10-17**（基线 `4480fc0`）—— 版本号取自本机 Flutter SDK 的
> `bin/cache/flutter.version.json`，阶段状态逐条比对 `CHANGELOG.md` tag 表与 `tasks/todo-flutter.md`。
> 若久未更新，**以 CHANGELOG 为准**。

## 为什么要重写

| 旧栈痛点 | Flutter 后 |
|---|---|
| `plus.android` 桥接地狱（运行时 Java 实例须 `invoke` 直调） | `file_picker` 插件一行拿字节 |
| `plus.sqlite` **无参数绑定**，所有值手工转义（旧 ADR-5） | drift 编译期生成参数绑定 |
| HBuilderX 手工打包，无 CI | `flutter build apk` + CI 自动化 |
| x86_64 模拟器必然白屏，只能真机 | 官方模拟器可用（含 MuMu 等第三方模拟器） |
| 自研 `xlsx.js`（fflate + 手写解码） | `archive` 解压 + 手写正则解析器（**不用 `excel` 包**：数值过 double 会丢 31 位单号精度） |

## 技术选型

| 关注点 | 选型 |
|---|---|
| 数据库 | **drift 2.31.0** + `drift_flutter 0.2.8` + `sqlite3 2.9.4`（编译期参数绑定，类型安全） |
| 状态管理 | Riverpod 3 |
| 路由 | go_router 18（`StatefulShellRoute.indexedStack` 壳 + 底栏 4 tab） |
| 金额 | `int` 分（ADR-2） |
| 主键 | UUID v4，客户端发号（ADR-1） |
| 入账指纹 | `crypto 3.0.7` SHA-1（纯 Dart，无 native 钩子） |
| 文件选择 | `file_picker 12`（Android SAF，免存储权限） |
| xlsx 读取 | `archive`（ZIP 解压）+ `bill_xlsx.dart` 手写正则解析器 |
| CSV / GBK | 自研逐字符状态机 + `gbk_codec`（纯 Dart 映射表，回环校验判坏件） |
| 自动记账 | **零新 pub 依赖** —— Android `NotificationListenerService` + `MethodChannel`（仅 Kotlin 原生） |

> ⚠️ **drift/sqlite3 版本锁死的理由**：sqlite3 3.x 起带 C 构建钩子（native-assets），Windows 上 `flutter test` 需要本机 MSVC 编译器，本机无 VS 会失败。因此锁 `drift 2.31.0 / drift_flutter 0.2.8 / sqlite3 2.9.4 / build_runner 2.15.1`（build_runner 2.16+ 要求 analyzer >=13，与 drift_dev 2.31 冲突）。装了 VS Build Tools 后可整体升级。

## 目录结构

```
lib/
  core/
    db/          drift database / tables / migrations
    providers/   data_epoch（写操作后 bump，常驻 Notifier 借它感知变化）
    theme/       卡通浅色设计 token
    utils/       money / id / fingerprint / date
    constants/   preset_categories
  data/
    repositories/
  features/
    ledger/  record/  category/  book/  import/  export/
    calendar/  stats/  reports/  search/  assets/
    onboarding/  profile/  nav/  shared/
    autobook/    自动记账（Dart 侧：解析规则 / 队列 / 诊断 / 页面）
  app.dart  main.dart

android/app/src/main/kotlin/.../autobook/    自动记账原生侧（7 个文件）
tool/                                        Python 兜底工具链 + 图标生成 + 通知取证
test/
```

> ⚠️ **自动记账的原生/Dart 边界**：Kotlin 侧**只做「包名过滤 + 取文案 + 落盘队列」**，
> **不做金额解析、不碰数据库**；解析与入账全在 Dart，drift 是唯一 DB writer。
> 这条边界是 F7.15 定的，破坏它会让「记错账」无法在 Dart 单测里覆盖。

## 本地开发

每次开终端先加载环境（Windows / Git Bash），它把本机所有踩坑配置都收拢了：

```bash
source env.sh
```

常用命令（**在 B 机 / Dart 工具链正常的机器上**）：

```bash
flutter pub get                                              # 走 env.sh 里的 7890 代理
dart run build_runner build --delete-conflicting-outputs     # drift 代码生成
fx-qa                                                        # analyze + test（自动去代理/补 VS 环境变量）
fx-test                                                      # 只跑单测
flutter build apk --debug
```

> ⚠️ **A 机（panda / D:）上上面这些直连命令全部跑不了** —— 见下一节「本机 Dart 工具链不可用时的兜底」。
> `env.sh` 会自动识别机器（看哪个 Flutter SDK 目录存在），无需手工改路径。

> ⚠️ **`flutter test` 直接跑会踩两个坑**（env.sh 已处理）：
> ① 沙箱吞掉了 `PROGRAMFILES(X86)`，VS 探测直接抛错 → 需手动注入；
> ② 代理会劫持测试进程的 WebSocket（`Invalid WebSocket upgrade request`）→ 跑测试必须去代理。

### ⚠️ 本机 Dart 工具链不可用时的兜底（**必读**）

本机（A 机）Dart 在 Windows 上**起不了需要管道 stdio 的子进程**
（`ProcessException: 所有的管道范例都在使用中 (CreateFile failed 231)`，
`runtime/bin/process_win.cc:744`）→ `flutter analyze` / `flutter test` /
`flutter pub get` / `build_runner` / `flutter build apk` **直连全废**。
**这是主机级问题，与项目代码无关** —— 别怀疑代码、别换 Dart 版本。

| 想做的事 | 直连命令（不可用） | 兜底 |
|---|---|---|
| analyze | `flutter analyze` | `python tool/dart_analyze_fallback.py`（≡ analyze，**含 lint**，全项目约 19s） |
| 单测 | `flutter test` | `python tool/dart_test_fallback.py <路径>`（只覆盖 `test()`，**`testWidgets` 跑不了 → 需你在终端跑**） |
| 构建 APK | `flutter build apk` | `python tool/build_kernel_fallback.py` → `(cd android && ./gradlew assembleDebug -x compileFlutterBuildDebug)` |
| 核验装的是不是新包 | — | `python tool/verify_apk_kernel.py "文案1" "文案2"` |

⚠️ **`source env.sh` 不能省**：不 source 则 `GRADLE_USER_HOME` 未注入 → Gradle 退回
**拒删**的 `<USER_HOME>\.gradle` → `journal-1.lock (拒绝访问。)`，**2 秒即 BUILD FAILED** ——
表现像「链路坏了」，实为环境变量没注入。

⚠️ **后台命令 ~15 分钟上限**：全量 test（40 文件）实测 15m03s 被掐断，输出停在中间
且**没有汇总行**（状态仍报 completed，极易误判跑完）→ **分批跑**。
并行跑 `dart_test_fallback.py` 必须用 `FX_TEST_WORK_SUFFIX=<后缀>` 隔离产物目录。

> **版本号有三个来源，装机前必须分清**（本项目踩过 `INSTALL_FAILED_VERSION_DOWNGRADE`）：
>
> | 来源 | 当前值 | 入版本控制？ | 用途 |
> |---|---|---|---|
> | `pubspec.yaml` `version:` | `0.1.0+1` | ✅ | **新克隆的默认值** → versionCode=**1** |
> | `android/local.properties` `flutter.versionCode` | **`2001`** | ❌ `.gitignore` 忽略 | **实际装机用的值**（`build.gradle.kts:38` → `versionCode = flutter.versionCode`） |
> | git tag / 「我的页」角标 | `v0.7.15` | ✅ tag | 人看的版本号（`tag = v0.7.<N>` ↔ `F7.<N>`） |
>
> ⚠️ `local.properties` **不入版本控制**，且 `2001` 是**手工设的、不是从 tag 推导的** →
> **新克隆 / 新机器上 versionCode 一定是 1**，直接 `install -r` 到走查机必报降级失败。
> **装机前先把它改成设备上已装包的值**。
> ⚠️ 该文件**还会被 flutter 工具改写**：跑一次 `flutter build apk --release` 就会写入
> `buildMode=release` + `versionCode=1` → 之后 `assembleDebug` 出的包也变 1，同样降级失败。
> 验证成品：`aapt dump badging <apk> | head -1`。

## 迁移进度

见 [`SPEC-flutter-migration.md`](SPEC-flutter-migration.md) 与 [`tasks/todo-flutter.md`](tasks/todo-flutter.md)。

| 阶段 | 内容 | 状态 |
|---|---|---|
| F0 | 环境搭建 | ✅ |
| F1 | 空壳 + 依赖 | ✅ |
| F2 | core/utils | ✅ |
| F3 | 数据层（drift schema v1 + repositories） | ✅ |
| F4 | UI 基础（M1 等价） | ✅ 真机验收通过 |
| F4.5 | 首页改版 + 底部导航 | ✅ |
| F5 | 账单导入（M2 等价） | ✅ 代码 + MuMu 走查通过 |
| F6 | 真机验收 + 文档收尾 | ✅ |
| F7.1 | 日历页（月历标注 + 日账单 + 月份选择子页） | ✅ |
| F7.2 | 统计·报表页（分类占比圆环 + 近 6 月趋势） | ✅ |
| F7.3 | 月度预算实装（schema v2 + 真实预算卡） | ✅ |
| F7.4 | 流水搜索（分类 / 备注 / 金额 + 一键清空） | ✅ |
| F7.5 | 搜索浮层化（覆盖首页，非路由）+ 资产页（净资产 + 账户 CRUD） | ✅ 真机走查通过 |
| F7.6 | 卡通浅色视觉改版（全站硬替换，P1 底座/首页/记一笔 · P2 日历/统计/资产 · P3 我的/账本/分类/导入/弹层/搜索） | ✅ 三批全部走查通过 |
| F7.7 | A 报表明细清单 · B 数据导出 · C 账户图标/颜色（schema v3）· D 搜索增强 · E 日历增强 | ✅ 五批全部（`v0.7.7`–`v0.7.10`） |
| F7.8 | 流水左滑删除（首页 / 日历日账单 / 搜索结果 3 处） | ✅ `v0.7.11` |
| F7.9 | 记一笔保存入口吸底常驻 + 启动图标 adaptive icon | ✅ `v0.7.12` |
| F7.14 | 新手引导（7 页全屏导览 + 「我的」重看入口；老用户不弹） | ✅ `v0.7.14` |
| F7.15 | **自动记账**（通知使用权为主 + 零权限兜底）+ 真机走查收口 | ✅ `v0.7.15` |
| F7.16 | 自动记账三段修复：A 补抓 · B `[N条]` 折叠前缀误杀 · **C 撤回通道 + 补抓守护层** | 🚧 三段已实现并真机验证，**未打 tag**（扩展监听清单待做） |
| — | 统计页图表两处绘制修复 | ✅ `v0.7.13` |
| F7.5-剩余 | 分类预算 | ⬜ 待排期（属新功能，须先出小 SPEC 签字） |

> ⚠️ **F7.16 为何不打 tag**：2026-10-08 用户提的「**扩展内置监听应用清单**」需求未落地。
> 现 `externalId = sha1(pkg|title|text|postTime)` **含 pkg，跨来源必然不重** ——
> 京东/拼多多/抖音的普通支付资金流经微信或支付宝，直接加白名单会**重复记账**。
> 故**跨应用去重是必做前置**，完成后一并转 `v0.7.16`。

**版本与回滚**：迁移期版本号直接取 F 阶段号 —— `tag = v0.7.<N>` ↔ `F7.<N>`，同阶段多批交付合一个版本。
回滚用 `git checkout v0.7.5`（看旧版）或 `git revert <commit>`（在 master 上撤单次改动）。
tag 表与规则见 [`CHANGELOG.md`](CHANGELOG.md) 顶部。

**验收基线**：M1/M2 首次使用验收报告 → [`docs/acceptance-M1-M2.md`](docs/acceptance-M1-M2.md)（MuMu 12 隔离环境实走）。

**变更历史**：见 [`CHANGELOG.md`](CHANGELOG.md)。

## 自动记账（F7.15 交付 / F7.16 加固）

链路：系统绑定 `NotificationListenerService` → Kotlin 抓通知（**只做包名过滤 + 落盘**）
→ `autobook_queue.jsonl` → Dart `drain()` → 纯函数解析 → `importRows()` 复用导入链路。

**三层采集**（F7.16 真机实证后确立，见 `docs/SPEC-F7.15-auto-bookkeeping.md` §10）：

| 层 | 通道 | 触发 | 实测 |
|---|---|---|---|
| 1 | `onNotificationPosted` | 通知发布 | ⚠️ 时通时不通 → **降级为可选加速** |
| 2 | `AutoBookGuard` 补抓守护 | `AlarmManager` 60s 周期 + 每次醒来续期 | ✅ 每 ~53 秒准点 |
| 3 | `onNotificationRemoved` | 通知被撤回那一刻 | ✅ **实测独立救回过 1 笔** |

三层**共用同一条 `handle()` 判定链 + `AutoBookSeen` 持久指纹** → 同一笔不会记两遍。

**为什么需要三层**：支付通知**只活 26 秒**（Redmi K50 实测 `19:16:03` 出现 →
`19:16:31` 被撤回，触发点是**用户点进支付成功页**）；撤回后
`getActiveNotifications()` 捞不到 → 层 3 是那一刻唯一的救援机会
（AOSP 保证撤回时 `extras` 仍完整，只丢 `contentView` / `largeIcon`）。

⛔ **已证伪、别再重试的方向**（都有实测依据）：

- **悬浮窗（`SYSTEM_ALERT_WINDOW`）** —— 只授权「在别应用上层画窗口」，
  **读不到别屏任何文字**；要读屏得换 `AccessibilityService` → Play 政策仅允许
  「服务身心障碍者」，Android 17.2 起 APM 模式下**非无障碍工具被系统直接切断**。
- **`requestRebind()` / 重绑自愈** —— 能恢复连接与补抓，**救不了 posted 推送投递**
  （实测重绑后发 8 条探针，posted 仍 0 条）。
- **用 logcat 判断回调是否到达** —— 代码只在 `decision != NOT_WATCHED` 时打日志，
  `posted pkg=` 为 0 **不能**证明回调没来；**唯一可信判据是内存计数差分**。

⚠️ **装包后测守护层必须给足时间**：`adb install -r` 会 **force-stop 应用并清掉已排期闹钟**
→ 装完立刻测会得到「守护层从不被触发」的**假结论**（已误判过一轮）。
正确姿势：**装完 → 重绑监听（`disallow` → 2s → `allow`）→ 等 ≥60 秒**再读 `tickCatchUpTotal`。

⚠️ **装机要用正式签名**：`assembleDebug` 出的是 **debug keystore** 包，而设备上是正式签名包
→ `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。**别卸载**（会丢账本）→ 正确做法是
`zipalign -f 4` + `apksigner sign --ks <key.properties 的 keystore>` **重签**
（装前先 `apksigner verify --print-certs` 比对指纹须与设备已装包**完全一致**）。
拉设备上的 drift 库必须用 **`adb exec-out`**（`adb shell cat` 会传输截断 → `database disk image is malformed`）。

## 架构红线

- ❌ 手写 SQL 字符串拼接（一律走 drift 生成的参数绑定）
- ❌ 用浮点表示或计算金额（一律 `int` 分）
- ❌ 物理 DELETE 业务数据（一律软删 `deleted_at`）
- ❌ 绕过 `importTransaction()` 直接写 `transactions` 表
- ❌ xlsx 数值经 `double` 中转（会丢 31 位单号精度，解析器必须按字符串走）
- ❌ 在 Kotlin 侧解析金额 / 写数据库（自动记账的原生侧**只落盘**，drift 是唯一 DB writer）
- ❌ 绕过 `AutoBookSeen` 直接把通知塞进队列（三层通道共用它去重，绕过就会重复入账）

## 开发规范

- **首次使用验收**：新增功能、改动入口文案/默认值/授权流程后，重跑 `first-run-acceptance`。
  规则、准备条件三分类与复查触发条件见
  [`docs/acceptance-first-run.md`](docs/acceptance-first-run.md)（F7.7-a 报表页 / 冷启动全链路，含数据层实跑）；
  M1/M2 基线报告见 [`docs/acceptance-M1-M2.md`](docs/acceptance-M1-M2.md)。
