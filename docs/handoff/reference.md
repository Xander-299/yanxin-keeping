# 项目参考（索引）

> 原来的单文件 141 KB 交接档案，按主题拆成了 5 份。**按需要读，不必通读。**
> 当前状态请先看仓库根的 [`HANDOFF.md`](../../HANDOFF.md)。

| 文档 | 什么时候读 |
|---|---|
| [`reference.md`](reference.md) | 环境事实、架构决策、关键资料、接手指南 —— **开工前读这份** |
| [`open-issues.md`](open-issues.md) | 有哪些未解决的问题、待确认事项 |
| [`pitfalls.md`](pitfalls.md) | 56 条「盲区防护」：踩过的坑与判据，改代码前扫一眼 |
| [`history.md`](history.md) | 已完成的工作、已尝试但放弃的方案（**别重复做**） |
| [`status-log.md`](status-log.md) | 逐版本状态流水 + 极简版摘要（历史，不是现状） |
| [`session-log.md`](session-log.md) | 逐轮会话记录：根因、取证、验证过程 |

> 文中的本机绝对路径已统一替换为 `<占位符>`，实际取值见 [`env.example.sh`](../../env.example.sh)。

# 项目/任务

把已归档的 uni-app 记账 App（旧仓库 `<OLD_REPO>`）重写为 Flutter 应用，新仓库 `<REPO>`。
**F0–F6 已完成（含 M1/M2 等价验收 + P1–P6 修复闭环）；F7.1 日历 / F7.2 统计 / F7.3 预算 / F7.4 搜索 / F7.5-a 搜索浮层化 / F7.5-b 资产页 均已交付。
F7.6 卡通视觉改版（按用户给定页面原型全站换浅色）：**P1 / P2 / P3 全部交付并真机走查通过，视觉改版收尾**（版本 `v0.7.6`）。**

# 核心目标

按 `SPEC-flutter-migration.md`（已签字）逐模块移植，每步：**需求 → 小 SPEC → 人工签字 → 实现 → 测试门禁 → 文档 → master 直推**。
F7 之后为「持续加功能」阶段，SPEC 未签字不动产品代码。

# 用户需求与约束

- 【已确认】目标栈 **Flutter**，**只做 Android**（无 Mac，iOS 不做）
- 【已确认】数据库 **drift**（编译期参数绑定，根治旧栈 ADR-5 手写 SQL 拼接）
- 【已确认】不做旧 App 数据迁移工具，手工重建账本；旧仓库只读归档
- 【已确认】远端 **SSH** `git@github.com:Xander-299/yanxin-bookkeeping-flutter.git`；`master` 直推
- 【已确认】功能需求以「小 SPEC 签字稿」形式落 `docs/spec/SPEC-F7.x-*.md`（F7.3 / F7.4 / F7.5 各一份）
- 【默认处理】旧栈 T2.8 真机复验：不做（用户未答复，按「不做」）

# 背景知识

- 旧栈：M1 已签字（8/8）、M2 代码完结（147 单测全绿）、M3–M8 未开工
- 旧栈可移植资产：`src/db/*`、`src/repositories/*`、`src/modules/bill-import/*`、`src/utils/*`（≈2700 行 JS）；UI 层 100% 重写
- 仍有效的 ADR：ADR-1 客户端发号（UUID v4）、ADR-2 金额 `int` 分、ADR-6 不接支付 API、ADR-7 `source`+`fingerprint` 唯一索引、ADR-8 DDL 对齐 schema v1、ADR-9 表由 drift 声明式生成 + **索引一律原始 SQL**。**ADR-4/5 已随换栈作废**
- 移植对拍基准：旧 147 个 vitest 单测；F5 已用真实支付宝/微信回单逐行对拍通过

# 已确认事实

| 项 | 值（**A 机 = 本机**） |
|---|---|
| Flutter / Dart | **3.47.2 / 3.13.2**（stable），`<FLUTTER_HOME>` |
| JDK | **Temurin 17.0.20.1+1**，`<JDK17_HOME>`（**勿用 JDK 25**；系统默认可能是 25，必须 `source env.sh`） |
| Android SDK | `<ANDROID_SDK>`（platforms **35/36**、build-tools 36.0.0、**ndk 28.2.13676358**、cmake 3.22.1、licenses 已接受） |
| Gradle 缓存 | `<REPO>\.gradle-home`（**5.3 GB，完好**）；`gradle.properties` 含代理 systemProp。<br>⚠️ 其中 `wrapper/dists/gradle-9.3.1-all/`（**754 MB**）自 2026-09-23 起**已无用**（wrapper 改指 `-bin.zip`，277 MB），手工删掉可回收 754 MB |
| Pub 缓存 | `<PUB_CACHE>` |
| 工程 | applicationId `com.teacodeman.yanxin`；version `0.1.0+1`；**DB schemaVersion = 3**（v2 加 `budgets`，v3 加 `accounts.icon` / `accounts.color`） |
| 模拟器 | MuMu 12 @ `<EMULATOR_HOME>`，adb `127.0.0.1:16384` / `7555`，设备名 `emulator-5554` |
| 联网 | 代理 `http://<PROXY_HOST>:7890`；`PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` 走 `*.flutter-io.cn` |
| **门禁（最新闭合口径 = 2026-10-08 · F7.15 全闭合）** | `flutter analyze` **No issues found**（等效手段 `python tool/dart_analyze_fallback.py`，全项目 19s；全项目残留 5 条为 `D://`/`d://` 双身份的既有环境假阳性）；`flutter test` **479 passed / 0 skipped**（✅ **2026-10-08 用户终端全量** = `test()` **391** + `testWidgets` **88**；上一版 400 的口径见 F7.14 段）；真机走查 ✅ **D1–D10 全部通过**（F7.14，MuMu 12，AI 经 adb 全包，0 崩溃）+ **F7.15 断点 ①–⑤ 全过**（Redmi K50，2026-10-08）。<br>✅ **F7.15（自动记账）已全闭合**（tag **`v0.7.15`**）：analyze 等效全项目 `No issues found!` ✅ + 终端 `flutter test` **479 passed** ✅ + APK 构建/核验通过 ✅ + **真机走查断点 ①–⑤ 全过（含用户实付支付宝 ¥0.01 端到端入账）** ✅ + 本机纯 `test()` **386 例全绿**（14 个 `testWidgets` 文件本机跑不了，已由用户终端覆盖）。<br>⚠️ **2026-09-23 起本机 Dart 起不了「需要管道 stdio」的子进程** → 这两个命令**在本机直连跑不了**（见「未解决问题」第 1 条）；本机等效工具（均已入库）：`python tool/dart_analyze_fallback.py`（≡ analyze，含全部 lint）+ `python tool/dart_test_fallback.py`（≡ test，**纯 `test()` 实测全绿，`testWidgets` 跑不了**；多实例并行加 `FX_TEST_WORK_SUFFIX`）+ `python tool/data_layer_probe.py`（数据层实跑）+ `python tool/build_kernel_fallback.py`（≡ `flutter assemble` 的 kernel 步骤）+ `python tool/verify_apk_kernel.py`（**装机前核验 APK 内 kernel sha256 + grep 新文案**）+ 图标 / pubspec 链 `inspect_icons.py` / `check_pubspec.py`（生成用 `gen_launcher_icons.py`），前两者配合 `./gradlew assembleDebug -x compileFlutterBuildDebug` 出 APK。 |
| git | **最后打 tag 的代码基线** = **`84a35ed`**（= F7.16 C 收口段）；**最新 tag = `v0.7.16`**（2026-10-20 收口，指向收尾提交 = `origin/master` HEAD；F 阶段一版一 tag，表在 `CHANGELOG.md` 顶部）。<br>✅ **F7.15 线 7 个提交 + F7.16 三段（`d44f8c6` / `85e416d` / `84a35ed`）均已推远端**，10-20 收口提交为最后一笔。<br>⚠️ 用户改的桌面名 `android:label="颜芯记账"` **已随 `3ec2381` 提交入库**（工作区干净）—— 别再当「未提交改动」处理。 |
| 源码规模 | `lib/` **98** 个 `.dart`（F7.15 +9 = `lib/features/autobook/`），`test/` **51** 个 `.dart`（49 个 `*_test.dart` + 2 个 helper；其中 **14** 个文件含 `testWidgets`），`tool/` **14** 个脚本 = **11 个 Python + 3 个 `.dart`**（Python：4 个门禁等效 —— `dart_analyze_fallback` / `dart_test_fallback` / `build_kernel_fallback` / `data_layer_probe`；`verify_apk_kernel.py` 装机核验；F7.15 走查取证 —— `parse_notif_dump` / `watch_notifications`；4 个图标与 pubspec 工具 —— `png_util` / `gen_launcher_icons` / `inspect_icons` / `check_pubspec`）；用例 **479 passed / 0 skipped**（**2026-10-08 用户终端实跑**）= `test()` **391** + `testWidgets` **88**（F7.14 口径 400，本批 **+79** 全落在 `test()`）；autobook 三文件 `rules` 47 + `flow` 15 + `real_samples` 16 = **78**；`lib/core/db/database.g.dart` 已入库。<br>另新增 Kotlin 源（本项目首个平台通道）：`android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/` **5 个 `.kt`** + `MainActivity.kt`。 |

**依赖版本锁死（不能随意升级）**：
`drift 2.31.0` / `drift_flutter 0.2.8` / `sqlite3 2.9.4` / `drift_dev 2.31.0` / `build_runner 2.15.1` /
`flutter_riverpod ^3.4.3` / `go_router ^18.0.1` / `uuid ^4.6.0` / `path ^1.9.1` / `cupertino_icons ^1.0.8` /
`crypto 3.0.7` / `archive ^4.2.0` / `gbk_codec 0.4.0`（走 `dependency_overrides`）/ `file_picker ^12.2.0`

**提交历史（两台机器 + 一次「无共同祖先」的合并）**：
- **A 机旧历史**：`… → c17abfd`（F7.1 日历）→ `caca7c0` → `13f3578`（F7.1 文档回写）
- **B 机历史**（由 zip 快照 `git init` 重建，**与 A 机无共同祖先**）：
  `0fa12fa`（F1–F7.2 + 换机环境）→ `ef4b869`（文档）→ `7f0372e`（统计页刷新修复 + 构建链路）→ `de67377`（F7.3 预算实装）
  → **`0b0ba90`（merge 并入远端 F7.1 历史，`--allow-unrelated-histories -X ours`）** → `8f6979f`（F7.3 文档）
  → `52fde16`（技能更新）→ `c6b616e`（F7.4 搜索）→ `78065a7`（文档）→ `6319796`（搜索无结果态 UI）
  → `e0cf8fd`（文档）→ `764d1e2`（F7.5-a 搜索浮层化）→ `f95ba97`（文档回写）
- **A 机接手续做（当前线）**：`94bbb33`（走查截图不再入库）→ `1f6f690`（**F7.6 P1**）
  → `3d4e749`（**F7.6 P2**）→ `aa96f01`（P2 走查修复）→ `5f0d369`（**F7.6 P3**）
  → `d3b2076`（P3 走查补做 + **版本记录机制 `v0.7.6`**）→ `909c3dc`（**F7.7 backlog SPEC**）
  → `8f1058b`（走查技能补「run-as + 设备 sqlite3 改库」一节）→ `c7cd43f` / `42abab1` / `26169b1`（HANDOFF 交接文档）
  → **`2f6db4c`（F7.7 A 批：报表明细 `/reports` + A.0 记一笔选账户）** → `67bed1a`（A 批文档回写）
  → **`bd65f21`（新增 `tool/dart_analyze_fallback.py`：analyze 等效门禁 0 issue）**
  → **`47e1bf6`（修 F1 阻断：报表随写操作刷新；+ `tool/data_layer_probe.*` + 首用验收报告）** → `cc222cb`（文档回写哈希）
  → **`e8804a4`（修首轮 `flutter test` 报回的 3 个用例：点错保存按钮 / 目标在绘制区外）**
  → **`ecf5e09`（当前 HEAD：新增 `tool/dart_test_fallback.py`，test 等效门禁打通 + `real_bills_test` 加载期加固）**

# 当前方案与关键决策

- **drift 版本下探**：drift 2.34.x 会拉 `sqlite3 3.x`（带 native-assets C 构建钩子，无 MSVC 必挂）→ 锁 drift 2.31.0。build_runner 锁 2.15.1（2.16+ 要 analyzer ≥13，与 drift_dev 2.31 冲突）。**装了 VS Build Tools 才可整体升级**
- **指纹用 `crypto` 包**：`dart:convert` 不含 sha1；选纯 Dart 的 `crypto`
- **`groupByDay` 签名**：Dart 泛型上界不能是 record 类型 → 用 `int Function(T) occurredAtOf` 选择器
- **索引不走 drift 声明**：`onCreate` 执行 `kSchemaV1Indexes` 原始 SQL（不支持 `DESC` / 部分索引）
- **`Transactions` 数据类名 → `TxRow`**（`@DataClassName`），否则与 drift 自带 `Transaction` 撞名
- **`importTransaction` 先查后插**：不解析 `SqliteException` 消息判重（文案依赖 sqlite 版本）
- **xlsx 不用 `excel` 包**：数值过 double 会丢 31 位单号精度 → `archive` 解压 + 手写正则解析器
- **Gradle 缓存**：`GRADLE_USER_HOME` 进工作区；**只能全新空目录**，复制必挂
- **搜索口径（F7.7 D 批后）**：入口是**覆盖首页的浮层**（`showSearchOverlay`，**不是路由**）；数据 = 当前账本全量（`listByBook`）+ **内存过滤**（无需防抖）；命中 = 分类名 / **账户名** / 备注 / 金额「元.分」文本**子串并集**（账户查不到回退空串，避免空词误命中）；另有**类型指令**（`parsePlan`）+ **时间区间**（全部 / 本月 / 近3月，与关键词、类型取**交集**，可单独生效）；命中处标 `brandTint2` 高亮（`lib/core/utils/highlight.dart`）；关键词历史落 `schema_meta` KV（键 `search_history`，最近 10 条）。<br>⚠️ **`searchProvider` 必须在 `build()` 里 `ref.watch(dataEpochProvider)`** —— 它是常驻 provider（非 autoDispose），不接版本号就会「刚记一笔/刚加账户后搜不到」（F7.4 起的老 bug，D 批走查才暴露）。
- **构建链路（2026-09-24 定）**：`flutter build` 与 `gradlew assembleDebug` **都会撞 231** → 必须走
  `python tool/build_kernel_fallback.py` + `./gradlew assembleDebug -x compileFlutterBuildDebug`；
  装机前从 APK 里读 `assets/flutter_assets/kernel_blob.bin` 比对 sha256 + grep 新文案（防「装到旧包」）。
- **各页月份状态互相独立**：`ledgerProvider` / `calendarProvider` / `statsProvider` / `monthBudgetProvider` 各自记月份；**写操作后必须逐个刷新**（曾漏 `statsProvider` 出 bug）
- **`env.sh` 双机器自动识别**（2026-09-17 新增）：按「哪台机器的 Flutter SDK 目录存在」分流路径，一份文件两边都能用、可入库

# 关键资料

- **「功能需求文档」在哪**：`docs/PRD-yanxin-flutter.md` —— 汇总稿（FR 编号 + 状态图例 + 口径 + backlog），
  **只看这一份就能知道 App 现在该有哪些行为**。注意它是**汇总不是签字件**，新需求仍要另出小 SPEC。
- `SPEC-flutter-migration.md`（已签字）、小 SPEC：`docs/spec/SPEC-F7.3-budget.md`、`docs/spec/SPEC-F7.4-search.md`、`docs/spec/SPEC-F7.5-search-overlay.md`、`docs/spec/SPEC-F7.5-assets.md`、`docs/spec/SPEC-F7.6-cartoon-ui.md`（F7.6 视觉改版，已交付）、**`docs/spec/SPEC-F7.7-backlog.md`（F7.7 五批 backlog —— **A–E 五批全部已签字并已交付**；其 §G 是实施记录 + 环境阻塞原理 + 「SPEC 前提修正」三处：C 批 schema、D 批 KV 复用、E 批 date 单位）**、
  **`docs/spec/SPEC-F7.15-auto-bookkeeping.md`（✅ 已签字、**已交付 `v0.7.15`（2026-10-08 用户终端全量通过）** —— §3.1 架构 / §3.5 忽略规则 / §3.7 通知栏三处 Android 硬约束 / §8 实施记录 + 走查补丁 + 真机走查与修复）**
- **F7.15 自动记账代码位置**：原生侧 `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/`
  （`AutoBookListenerService` 监听 / `AutoBookQueue` JSONL 队列 + `restore()` / `AutoBookNotifier` 回执通知 /
  `AutoBookChannel` MethodChannel `yanxin/autobook` / `AutoBookDiagnostics` 诊断落盘）+ `MainActivity.kt`；
  Dart 侧 `lib/features/autobook/`（`data/{auto_book_rules,auto_book_bridge,auto_book_batches,auto_book_diagnostics}.dart`
  + `application/{auto_book_controller,auto_book_notice,auto_book_accounts}.dart` + `presentation/auto_book_page.dart`
  & `widgets/auto_book_banner.dart`）；走查截图 `.workbuddy/qa-f715/`。
- **页面原型（视觉唯一依据）**：`<PROTOTYPE_DIR>`（`index.html` + `styles.css` + `data.js` + `screens.js` + `app.js`）；
  改任何 UI 前先并排对拍。旧参考图 `docs/design/*.jpg`（深色）**已被取代**。
- `tasks/todo-flutter.md`（F0–F7.6 已勾选；F7.5 剩余项已并进 `docs/spec/SPEC-F7.7-backlog.md`）、`CHANGELOG.md`（**含版本规则与 tag 表**）、`README.md`
- `docs/acceptance-M1-M2.md`（首用验收 M1/M2 报告）
- `env.sh` — **每次开终端必 `source env.sh`**（自动识别 A/B 机）
- `android/gradle.properties` — 含 **`kotlin.incremental=false`**（修跨盘 Kotlin 崩溃，**勿删**）与 `android.builder.sdkDownload=false`
- 参考图 `docs/design/*.jpg`；旧栈资产 `<OLD_REPO>\src\{db,repositories,modules/bill-import,utils}`
- 真机走查：`docs/dev/android-ui-smoke.md`；`uiautomator` 语义树脚本 `tool/ui_dump.py`
- 验收报告：`docs/acceptance-M1-M2.md`（首用验收 M1/M2）、`docs/acceptance-F7.5b-assets.md`（资产页真机走查）、
  `docs/acceptance-first-run.md`（首次使用验收 F7.7-a，2026-09-23）、
  **`docs/acceptance-F7.7-DE.md`（F7.7 D/E 批走查，2026-09-24 —— 含抓到的搜索快照 bug 与「构建路径变通」）**
- **本机等效工具**（Dart 起不了子进程时用，均已入库）：`tool/dart_analyze_fallback.py`（≡ analyze）、
  `tool/dart_test_fallback.py`（≡ test，纯 `test()` **312** 例）、`tool/data_layer_probe.py` + `.dart`（数据层实跑）、
  **`tool/build_kernel_fallback.py`（≡ `flutter assemble` 的 kernel 步骤，配合
  `./gradlew assembleDebug -x compileFlutterBuildDebug` 出 APK）**
- **常用命令**：
  - 门禁：`source env.sh && fx-qa`（analyze + 去代理 test）
  - 仅测试：`source env.sh && fx-test`
  - 代码生成：`source env.sh && dart run build_runner build`
  - debug APK：`source env.sh && flutter build apk --debug`（**正常环境用这条**）
  - **本机 debug APK（Dart 231 环境下唯一可行路径）**：`source env.sh` →
    `python tool/build_kernel_fallback.py` → `( cd android && ./gradlew assembleDebug -x compileFlutterBuildDebug )`
    → 装机前核验 APK 内 `assets/flutter_assets/kernel_blob.bin` 的 sha256 + grep 新增文案
  - **release APK**：`source env.sh && flutter build apk --release` → `build\app\outputs\flutter-apk\app-release.apk`
  - 上架 AAB：`flutter build appbundle --release`（**需先配正式签名**）
  - 装到 MuMu：`adb -s emulator-5554 install -r -t <apk>`（debug 包 **`-t` 必须**）
  - 推远端：`git push`（SSH，免凭据）

# 我的偏好与工作方式

- 简洁中文回复；✅ 式状态汇总；技术总结用 **root-cause + fix + commit hash + next-actions** 结构
- 里程碑节奏：需求 → 小 SPEC → **人工签字** → 实现 → 测试门禁 → 文档 → master 直推
- 通过 `HANDOFF.md` / `BUG.md` + `@skill` 标签延续工作；真机测试后反馈 UI/UX 回归
- 换机器 / 清理文件后要求先体检环境再交接

# 新 Agent 接手指南

1. **当前最重要的事（2026-10-20 17:10）**：**F7 阶段 16 个版本全部交付并已打 tag** ——
   **F7.16 三段修复已转正 `v0.7.16`**（10-20 收口）。最后一个遗留项「**扩展内置监听应用清单**」
   **已由用户拍板关闭（不做）**，理由见下方。**本项目当前无未收口批次，等用户排新需求。**
   10-09 → 10-20 期间**零功能代码改动**（10-17 三连更只改 `README.md`；10-20 只改文档 + 角标）。
   三段均已真机验证：
   - ✅ **A · 补抓**（`d44f8c6`）：修「服务未连接期间发布的支付通知永久丢失」—— 新增 `catchUp()` 扫
     `getActiveNotifications()` + `AutoBookSeen`（新，持久指纹集 `pkg|title|text|postTimeMs`，cap 200）。
     Redmi K50 实测把 22:29:37 那笔支付宝 ¥3.00 补记入账（DB **165→166**）。
   - ✅ **B · 微信支付「识别不到」**（`85e416d`）：`[N条]` 折叠前缀被误判成组摘要而静默丢弃 → 改成
     **归一化**（剥 `^\s*\[\d+条\]\s*` 再解析，`combined`/`externalId` 用归一化文本）。
   - ✅ **C · 撤回通道 + 补抓守护层**（`84a35ed`，本轮）：用户提案「悬浮窗」**经查证否决**；
     实测支付通知**只活 26 秒**、点进支付成功页即被撤回 → 新增 **`onNotificationRemoved` 兜底**
     （撤回那一刻 extras 仍完整，AOSP 保证只丢 `contentView`/`largeIcon`）+ **`AutoBookGuard` 守护层**
     （`AlarmManager` 60s 周期 + 醒来续期）+ 通道可用性诊断（8 字段 + `/autobook`「采集通道」一行）。
     两笔真实 ¥0.01 均自动入账（DB **163→164**、¥2363.42→**¥2363.43**），
     **其中一笔由 `removed → CAPTURED` 独立救回**（发生在通知已被撤回、补抓已捞不到之后）。
   - ✅ **原先「尚未收口的一件事」已关闭（2026-10-20）**：**扩展监听应用清单 → 裁定不做。**
     理由（用户原话「其它平台本质是银行卡支出」）：**其它平台的支付最终都是银行卡支出** ——
     京东/拼多多/抖音的普通支付资金流经微信或支付宝 → 现有两来源**已覆盖**；
     再监听电商 App 只会拿到同一笔的第二条通知。而现 `externalId` 含 `pkg` → 跨来源必然不重 →
     要支持扩展**必须先做跨应用去重**（引入重复记账风险换已被覆盖的信号，收益为负）。
     **银行短信**（`com.android.mms`）本批**不纳入**（需 `READ_SMS` 敏感权限 + 与支付通知重叠区更大）。
     ⚠️ **若将来**用户要做「绕过微信/支付宝的支付渠道」（白条 / 月付 / 云闪付 NFC）单独记账，
     **必须先做跨应用去重**（同金额 + 时间窗口 → 只留一条），否则一定重复记账。
   - 📌 **2026-10-17 新增交付：README「项目简介（简历可用）」章节**（`82767d9`）——
     用户明确说要**拿本项目当简历项目**。已写好一段可直接取用的介绍，位置在 README 文首
     （「为什么要重写」之前），含：实测规模表（Dart 98 文件/25,361 行 · Kotlin 8 文件/1,507 行 ·
     52 测试文件 · 140 提交 · 16 tag · 约 6 周）、技术栈一行、**8 条带实测证据的技术难点**、
     **16 行版本迭代记录**（`v0.7.1`–`v0.7.16`）、工程实践 4 条。
     ⚠️ **若后续有新交付，必须同步更新这两处**：README 的「项目规模」数字与「版本迭代记录」表
     （后者要与 `CHANGELOG.md` tag 表逐条一致）。
     ⚠️ **测试数别写错**：README 写的是 **485 个用例（静态计数）**，并注明另有 **18 处数据驱动循环展开**；
     全量实跑数更高（用户终端曾跑出 **479 passed**）—— **别把静态数当运行时所例**。
   - ⚠️ **别再按已证伪的方向做**（本轮实测推翻）：
     ① **悬浮窗 / 无障碍**：读不到别屏内容 + Play 政策封杀（Android 17.2 起 APM 直接切断）；
     ② **`requestRebind` / 重绑自愈**：能恢复连接与补抓，**救不了 posted 推送投递**
     （实测重绑后发 8 条探针，posted 仍 0 条）；
     ③ **「logcat 里 `posted pkg=` 为 0」不能证明回调没来**（代码对非白名单不打日志）→
        **必须用内存计数差分**判别（本次靠 `skippedNotWatched` 4730→4847 与 catchUp 扫描量比对才拿到真结论）。
   - ⚠️ **装包后测守护层必须给足时间**：`adb install -r` 会 **force-stop 应用并清掉已排期闹钟**，
     装完立刻测会得到「守护层从不被触发」的**假结论**（本轮先误判了一轮）。
     正确姿势：**装完 → 重绑监听 → 等 ≥60 秒**再读 `tickCatchUpTotal`。实测守护层每 **~53 秒**准点触发。

   - 📌 **F7.15 自动记账已交付 `v0.7.15`（代码基线 `e4e53b4`，已推远端，无遗留项）**：架构（Kotlin 只做包名过滤+落盘、
     Dart 解析入账，drift 唯一 DB writer）、平台侧、Dart 侧、真机走查（断点①–⑤含用户实付支付宝 ¥0.01 端到端）、
     用户终端全量 `flutter test` **479 passed / 0 skipped**、模拟器 `ACTION_SEND` 走查均通过。
     入口 = `lib/features/autobook/`（Dart 9 文件）+ `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/`
     （Kotlin 5 文件）；SPEC = `docs/spec/SPEC-F7.15-auto-bookkeeping.md`（§3.1 架构 / §3.7 三处 Android 硬约束 / §8 实施记录）。
     **别重写、别换个形式做**。⚠️ 本机跑不了 `testWidgets`，**别拿本机脚本当最终判据**；analyze 等效全项目 `No issues found!`。
   - ⚠️ **现场教训（对真实使用有影响，务必记牢）**：**MIUI/HyperOS 在 `force-stop` 后会解绑监听服务**，而设置与
     `dumpsys` 都显示「已授权」→ 难查的「开关开着但没工作」；`force-stop` / 覆盖安装后**必须重绑一次**
     （重绑姿势：**先 `disallow_listener` 再 `allow_listener`，单独 allow 不生效**；判定只看 `Live notification listeners`）。
     **重绑会把仍在通知栏的活跃通知重投**（实测延迟 1 分 37 秒）→ 页面提示真能救回数据，不必重付。

   **已交付的历史轮次（均已推远端 `origin/master`，别重写）**：
   - **F7.14 新手引导**（`v0.7.14`，`c5ea1b5`）：7 页全屏导览 + 「我的」重看入口 + **老用户不弹**
     （判定 = 无标记 **且** `ActiveBookIdController.isFreshInstall`）；入口 `lib/features/onboarding/`，
     SPEC `docs/spec/SPEC-F7.14-onboarding.md`，报告 `docs/acceptance-F7.14-onboarding.md`（D1–D10 全过）。
     ⚠️ 加首启副作用必须同步改测试基建（`pumpApp` 默认预写 `onboarding_done`，见「盲区防护」第 49 条）。
   - **F7.13 统计图表修复**（`v0.7.13`，`0773333`）：圆环 `drawArc(useCenter: true)` 楔形 + 趋势零值月不画柱；
     报告 `docs/acceptance-F7.13-stats-charts-fix.md`。
   - **F7.9 吸底保存 + 启动图标 adaptive**（`v0.7.12`，`1f3ec96`）：⚠️ 吸底按钮**必须放 body 的 `Column`**，
     **不能用 `Scaffold.bottomNavigationBar`**（它按屏幕高贴底、**不随键盘上移**）。
   - **F7.7 五批（A–E）+ F7.8 左滑删除**（`v0.7.7`–`v0.7.11`）：全部交付，**无待签字批次**。
   - **已关闭的测试反馈**：`real_bills_test.dart` 曾报 `loading ...`（全仓唯一在 `main()` 里做 IO 的文件）
     → 已加固为懒读 + 降级 `markTestSkipped`，复跑未再出现（**若再复现，要那行 `loading` 的完整 `[E]` 块**）。
     另 2026-09-30 修掉 `budget_card_test` 两条「只在月末必挂」的日期 flake（`a545687`，见「盲区防护」第 55 条）。
2. **要真机走查**：两条构建路径 —— ① **正常环境（用户终端）**：`source env.sh && flutter build apk --debug`；
   ② **本机（Dart 231 故障下唯一可行）**：`source env.sh` → `python tool/build_kernel_fallback.py` →
   `( cd android && ./gradlew assembleDebug -x compileFlutterBuildDebug )`。
   ⚠️ **装机前必验包新鲜度**：从 APK 读 `assets/flutter_assets/kernel_blob.bin` 比对 sha256（与盘上一致）
   + grep 本次新增文案（如「最近搜过」「近3月」）—— 否则极易「装到旧包」而误判「改了没用」。
   然后 `adb -s emulator-5554 install -r -t <apk>`（debug 包 **`-t` 必须**）装到 MuMu 12，
   照 `docs/dev/android-ui-smoke.md` 走（**adb 命令一律加 `MSYS_NO_PATHCONV=1`**）。
   D/E 批走查记录（含逐步期望值）可直接对拍：`docs/acceptance-F7.7-DE.md`。
3. **占位项（未做功能，别当 bug）** —— **已全部点亮**：4 处「报表」入口（A 批）+「我的 → 数据导出」（B 批）
   + 账户图标 / 颜色（C 批）→ **当前无占位页**（`PlaceholderPage` 仍留在 `lib/features/nav/` 备用）。
   **已裁定不做**（别当 bug 报）：**D.5 拼音 / 首字母匹配**、**E.5 农历 / 节假日**、**报表页流水行长按删除**（只读行）。
   资产 tab 是真实资产页，不是占位。
3b. **视觉规则（F7.6 起）**：全站**只有卡通浅色一套主题**（深色已删）；色值一律走 `Tok.xxx` 令牌，
   **产品代码里禁止出现裸 `Color(0x…)`**（除 `lib/core/theme/` 内）；造型走 `ToonCard / ToonButton /
   ToonPress / ToonSeg / ToonField …` 通用件，别自己拼描边阴影。
3c. **版本规则（2026-09-23 起）**：迁移期拿 F 阶段号当版本号 —— `tag = v0.7.<N>` ↔ `F7.<N>`，
   同阶段内的多批交付合并成一个版本。每次功能更新：CHANGELOG 加段落 → `git tag -a v0.7.N` → `git push --tags`。
   **回滚**：`git checkout v0.7.13` 看/跑旧版，`git revert <commit>` 在 master 上撤单次改动。tag 表在 `CHANGELOG.md` 顶部。
4. **代码结构**（都已落库）：
   - `tool/dart_analyze_fallback.py` — **`flutter analyze` 的等效替代**（本机 Dart 起不了子进程时用；原理与协议三坑见 SPEC §G）
   - `tool/dart_test_fallback.py` — **`flutter test` 的等效替代**（Python 起 `frontend_server` 编译 + `flutter_tester.exe` 执行；
     **纯 `test()` 用例等价**，`testWidgets` 跑不了。参数抄 flutter_tools 源码，别自己发明）
   - `tool/data_layer_probe.py` + `.dart` — 数据层脱离 Flutter 真跑（复制 `lib/` 到 `.dart_tool/` 临时包 + 内存库）
   - **`tool/build_kernel_fallback.py` — `flutter assemble` 的 kernel 步骤等效替代**（Python 起 `frontend_server`
     产 `app.dill` → 复制成 `flutter_assets/kernel_blob.bin`，打印 sha256；配合
     `./gradlew assembleDebug -x compileFlutterBuildDebug` 出 APK。参数抄构建日志里 `kernel_snapshot_program` 的命令行）
   - `lib/core/providers/` — database / book_providers / category_providers（DI + 当前账本）/ **account_providers**（A 批新增，账户名映射与选账户共用）
   - `lib/core/db/` — `tables.dart`（5 张表 + **budgets** + **schema_meta** KV）、`schema_v1.dart` / `schema_v2.dart`（索引原始 SQL）、`database.dart`（**schemaVersion 3**；`onUpgrade`：v1→v2 只加 budgets、v2→v3 加 `accounts.icon` / `accounts.color`）
   - `lib/features/nav/` — AppShell（抽屉 + 底栏 + 壳路由）+ PlaceholderPage
   - `lib/features/ledger/` — 首页（`LedgerController` + `MonthHero` + **`BudgetCard`** + `budget_metrics` / `budget_controller` / `budget_edit_sheet` + `BookDrawer` + `TxGroupList`）
   - `lib/features/calendar/` — `CalendarController` + `calendar_aggregate` + `MonthGrid`（**E 批：长按格子 → `/record?date=<毫秒>`；横向 drag 翻月，阈值 1/3 格宽**）+ `MonthPickerPage`
   - `lib/features/stats/` — `application/{stats_aggregate,stats_controller}.dart` + `presentation/stats_page.dart` + `widgets/{category_pie,trend_bars}.dart`
   - `lib/features/assets/` — `application/{asset_aggregate,account_meta,assets_controller}.dart` + `presentation/assets_page.dart` + `widgets/account_form_sheet.dart`（`account_meta` 含 **C 批：图标 / 颜色取值约定与回退**）
   - `lib/features/search/` — `application/{search_query,search_controller,search_history}.dart` + `presentation/search_overlay.dart`（**`showSearchOverlay` 打开，不是路由**；`search_query.dart` = 命中口径（分类名 / **账户名** / 备注 / 金额子串）+ `parsePlan` 类型指令 + 时间区间，并 re-export `highlightRanges`；`search_history.dart` = 最近 10 条历史）
   - `lib/core/utils/highlight.dart` — **D 批新增**：`highlightRanges(text, query)` 纯函数（算命中区间供 UI 打底色，`MatchRange` = `({int start, int end})`；`test/` 有独立单测）
   - `lib/features/import/` — 解析五层 + `bill_importer.dart` + `import_page.dart`
   - `lib/features/reports/` — **A 批新增**：`application/{report_aggregate,reports_controller}.dart` + `presentation/reports_page.dart` + `presentation/widgets/report_group_list.dart`（三档明细 / 分类 / 账户）
   - `lib/features/onboarding/` — **F7.14 新增**：`onboarding_keys.dart`（`kOnboardingDoneKey`）+ `application/onboarding_prompt.dart`（`onboardingPromptProvider` = 无标记 **且** `ActiveBookIdController.isFreshInstall`）+ `presentation/onboarding_page.dart`（`PageView` 7 页 + 进度点 + 跳过 / 下一步 / 开始记账；**「看过」标记收口在 `dispose()`**，故无需 `PopScope`）+ `presentation/widgets/onboarding_slides.dart` + `onboarding_art.dart`（全矢量 `MiniScreen` / `HighlightBox` / `Callout`）
   - `lib/data/repositories/` — book / account / category / transaction / **budget** / **app_meta**（D 批：`schema_meta` KV 薄封装，`get` / `set` / `remove`）
   - 路由：壳 `/` `/calendar` `/assets` `/profile`；全屏 `/record`（extra=流水 id，**`?date=<毫秒>`** 默认日期 —— E 批长按日历即用它）`/books` `/categories` `/import` `/month-picker` `/stats` **`/reports`（extra=`ReportsArgs{tab,year,month}`）** **`/onboarding`（F7.14；在 shell 之外 → 盖住底栏；首启由 `AppShell` 首帧后 push，另可由「我的 → 新手引导」push）**（**搜索无路由**）
5. **不要重复**：不要重装 Flutter/JDK/SDK；不要升 drift/sqlite3/build_runner；不要用 `pub add`；不要复制 gradle 缓存；不要回头做旧栈 T2.8；不要把 `env.sh` 改回 `env -u` 写法；**不要删 B 机的 `<SQLITE3_DIR>`**
6. **信息不足先问用户**：真机冒烟需要用户给设备或装模拟器（推送已配 SSH，不必再要 token）；以及「继续在 A 机开发，还是回 B 机」

---
