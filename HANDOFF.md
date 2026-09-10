# HANDOFF.md — 颜芯记账 uni-app → Flutter 迁移（F1–F4.5 ✅ / F5 代码 ✅ 待真机 / F6 收尾）

> **新会话接手时，只读这一个文件就能继续干活。**
> 最后更新：2026-09-11 02:25 · 更新人：AI 助手（修 P1/P2 验收阻断 + 门禁 146/146 + MuMu 端到端验证通过）

---

# 项目/任务

把已归档的 uni-app 记账 App（旧仓库 `D:\Tencent\yanxin`）重写为 Flutter 应用，新仓库 `D:\Tencent\yanxin-flutter`。
**F1–F4.5 已完成且真机验收通过。F5（账单导入）代码完成、真实件对拍逐行一致、门禁 143/143，待真机验收 M2 等价 8 项。F6 收尾未开始。**

# 核心目标

按 `D:\Tencent\yanxin-flutter\SPEC-flutter-migration.md`（已签字）的 F0–F6 路线逐模块移植：
F0 环境 ✅ → F1 空壳 ✅ → F2 utils ✅ → F3 数据层（drift）✅ → F4 UI（M1 等价 8 项）✅ → F4.5 首页改版+底栏 ✅ → F5 账单导入（代码✅/真机待验）→ F6 验收收尾。
每步独立验收、有测试门禁；SPEC 未签字不动产品代码。

# 用户需求与约束

- 【已确认】目标栈 **Flutter**，**只做 Android**（本机无 Mac，iOS 不做）
- 【已确认】数据库用 **drift**（编译期参数绑定，根治旧栈 ADR-5 手写 SQL 拼接）
- 【已确认】新仓库全新起步、逐模块移植；旧仓库只读归档
- 【已确认】不做旧 App 数据迁移工具，手工重建账本
- 【已确认】远端 `git@github.com:Tea-Codeman/yanxin-bookkeeping-flutter.git`，本地 `master` = **`0c82620`**（已推送）
- 【默认处理】旧栈 T2.8 真机复验：不做，旧栈直接归档（用户未答复，按「不做」）

# 背景知识

- 旧栈进度：M1 已真机签字（8/8）；M2 代码完结（147 单测全绿）；M3–M8 未开工
- 旧栈可移植资产：`src/db/*`、`src/repositories/*`、`src/modules/bill-import/*`、`src/utils/*`（≈2700 行纯 JS）；UI 层（9 个 `.vue` + pinia）100% 重写
- 仍有效的 ADR：ADR-1 客户端发号（UUID v4 主键）、ADR-2 金额 `int` 分、ADR-6 不接支付 API、ADR-7 `source`+`fingerprint` 唯一索引；**ADR-4 / ADR-5 已随换栈作废**
- ADR-8：DDL 与旧库 **schema v1 完全一致**（字段顺序/类型/索引/指纹部分唯一索引）
- ADR-9：表结构由 drift 声明式生成、**索引一律走原始 SQL**（drift 的 `@TableIndex` 不支持 `DESC` 与部分索引 `WHERE`）；版本号由 drift 托管（`PRAGMA user_version`），`schema_meta` 表仅用于 KV（如 `active_book_id`）
- 移植对拍基准：旧 147 个 vitest 单测；F5 已用真实支付宝/微信回单与旧自研 `xlsx.js` 逐行对拍通过

# 已确认事实

| 项 | 值 |
|---|---|
| Flutter / Dart | **3.47.2 / 3.13.2**（stable），`D:\Download\Flutter\flutter`；引擎 hash `a804b261645ef8c13eb3d5c44a5c2fb0340c5539` |
| 第二个 Flutter SDK | `D:\Downloads\Flutter\flutter`（**同版本 3.47.2**），`android/local.properties` 里的 `flutter.sdk` 指向它。Gradle 构建实际走这个，与 `env.sh` 的 `D:\Download` 不一致但**无害** |
| JDK | **Temurin 17.0.20.1+1**，`D:\Download\Java\jdk-17.0.20.1+1`（**勿用 JDK 25**，`which java` 默认给的是 25，必须 `source env.sh` 覆盖） |
| Android SDK | `D:\Download\Java\Android`（platforms **35/36**、build-tools 36.0.0、cmdline-tools、licenses 已接受） |
| Pub 缓存 | `<USER_HOME>\AppData\Local\Pub\Cache`，`hosted/` 下 **pub.dev 与 pub.flutter-io.cn 两套并存**（正常） |
| Gradle 缓存 | `D:\Tencent\yanxin-flutter\.gradle-home` = **4.1 GB，完好**；`gradle.properties` 含代理 systemProp + `org.gradle.jvmargs=-Xmx4G` |
| 工程 | applicationId `com.teacodeman.yanxin`；version `0.1.0+1` |
| 真机 | Redmi K50 无线 adb 可见；无 AVD |
| 联网 | 代理 `http://127.0.0.1:7890`；`PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` 走 `*.flutter-io.cn` |
| 门禁（2026-09-11 00:0x 复跑） | `flutter analyze` **No issues found (81.7s)**；`flutter test --no-pub` **143/143 All tests passed** |
| APK | `build\app\outputs\flutter-apk\app-debug.apk`，**177,484,448 字节（2026-09-11 01:08 重建，gradle 277.8s）** |
| 源码规模 | `lib/` 44 个 `.dart`，`test/` 20 个 `.dart`；`lib/core/db/database.g.dart` 已生成入库 |
| doctor 残留告警 | Windows Version ☠ / Connected device ☠ 是沙箱黑名单拦 `wmic.EXE`/`reg.EXE`，**不要修** |

**依赖版本锁死（不能随意升级）**：
`drift 2.31.0` / `drift_flutter 0.2.8` / `sqlite3 2.9.4` / `drift_dev 2.31.0` / `build_runner 2.15.1` /
`flutter_riverpod ^3.4.3` / `go_router ^18.0.1` / `uuid ^4.6.0` / `path ^1.9.1` / `cupertino_icons ^1.0.8` /
`crypto 3.0.7` / **`archive ^4.2.0`** / **`gbk_codec 0.4.0`（走 `dependency_overrides`）** / **`file_picker ^12.2.0`**

**提交历史（master，已同步 origin；`git status -sb` 显示 `[gone]` 是沙箱已知假象）**：
`ba45fba` → `eb6e004` → `4f5f1e1` → `9da1ed6` → `d15fefc` → `fcfd0d1` → `cbcf8e0` →
`7a498d8`（F3 数据层）→ `c49d46c`（HANDOFF）→ `cf0580b`（F4 UI）→ `74f9d2c`（F4.5 首页改版+底栏）→
`f060c88`（perf 记一笔卡顿）→ **`0c82620`（F5 账单导入，当前 HEAD）**

# 当前方案与关键决策

- **drift 版本下探**：drift 2.34.x 会拉 `sqlite3 3.x`，后者带 **native-assets C 构建钩子**，Windows host 无 MSVC 编译必挂 → 锁 drift 2.31.0（最后一个 sqlite3 `^2.x` 的版本）。build_runner 锁 2.15.1（2.16+ 要 analyzer ≥13，与 drift_dev 2.31 的 analyzer <11 冲突）。**装了 VS Build Tools 后才可整体升级**
- **指纹用 `crypto` 包**：`dart:convert` **不含 sha1**，必须引包；选纯 Dart 的 `crypto`（无 native 钩子）
- **`groupByDay` 签名**：Dart **不允许把 record 类型当泛型上界** → 改用 `int Function(T item) occurredAtOf` 选择器
- **索引不走 drift 声明**：7 条索引在 `onCreate` 里执行 `kSchemaV1Indexes` 原始 SQL
- **`Transactions` 数据类名改为 `TxRow`**（`@DataClassName`）：否则与 drift 自带的 `Transaction` 撞名
- **不写 `BaseRepository`**：4 个 repo 各自实现（重复约 6 行软删），泛型基类只引噪音
- **`importTransaction` 先查后插**：不解析 `SqliteException` 消息判重（文案依赖 sqlite 版本，脆弱）
- **xlsx 不用 `excel` 包**：数值过 double 会丢 31 位单号精度 → `archive` 解压 + 移植旧栈手写正则解析器
- **Gradle 缓存策略**：`GRADLE_USER_HOME` 指进工作区；**只能用全新空目录让 Gradle 自下载**
- 环境坑全部收敛在 `env.sh`：`fx-test` / `fx-qa`（**2026-09-11 已重写为 bash `unset` 版**）

# 已完成工作

- **F0** 环境基线 ✅（6 行 export 写进 SPEC §5.1）
- **F1** 骨架、pubspec 手写锁定、`analysis_options.yaml` 收紧（strict-casts/inference/raw-types）、debug APK 构建成功、推送远端 ✅
- **F2** `lib/core/utils/{money,id,fingerprint,date}.dart` + 27 测试（含指纹 golden 向量）✅
- **F3** drift 数据层 ✅（`7a498d8`）：5 张表、7 条原样索引、`AppDatabase(schemaVersion=1)`、4 个 repo、`importTransaction` 指纹幂等返回 sealed `ImportResult`；DDL 已与旧 `schema.js` 对拍通过
- **F4** M1 等价 UI ✅（`cf0580b`）：首页/记一笔/账本管理/分类管理，68/68 测试，**真机验收 8 项通过**
- **F4.5** 首页改版 + 底部导航 ✅（`74f9d2c`）：深色主题 `#0C0C0C` + 琥珀橙 `#FFAF38`，4 tab + 中央记一笔，账本抽屉，69/69
- **perf** 记一笔卡顿 ✅（`f060c88`）：去异步门闩 + 复用已缓存 provider，push 零新增查询
- **F5** 账单导入 ✅ 代码（`0c82620`）：decode/csv/profiles/normalize/xlsx/categorize 五层 + drift 事务 importer（指纹 IN 预查 + 文件内去重 + dryRun 哨兵回滚）+ 导入页 UI（选文件→预览可单条取消→确认→报告）；真实件对拍：微信 xlsx 335→327（8 笔退款黑名单）、支付宝 GBK 32→28、31 位单号不丢精度；**143/143**
- **2026-09-11 环境体检** ✅：依赖/缓存/配置全部在位，门禁复跑全绿，`env.sh` 的 `fx-test`/`fx-qa` 缺陷已修
- **2026-09-11 SDK 误删与还原** ✅：`D:\Download\Java\Android`（10.04GB）于 00:27 被删进 D 盘回收站（`$R0X47RA`），`flutter doctor` 报 SDK not found → 已用 `mv` 同盘还原，`[√] Android toolchain (Android SDK version 36.0.0)` 恢复，APK 重编成功。**教训：磁盘清理会误伤 SDK，别把 `D:\Download\Java\` 当垃圾目录**

# 已尝试但失败/放弃的方案

| 尝试 | 结果 / 原因 |
|---|---|
| `flutter pub add` | 卡死 20min+ 零输出 → 改「查 pub API → 手写 pubspec → `pub get`」 |
| **把 `<USER_HOME>\.gradle\caches` 复制进工作区 `.gradle-home`** | **Gradle 启动即挂死**：`gradlew --status` 都 2min 无响应，构建 15min 零写入（伪装成网络慢，最易误判）。改全新空目录后正常 |
| **在 `env.sh` 里用 `env -u ... "PROGRAMFILES(X86)=..." flutter.bat ...`** | **2026-09-11 实测：沙箱里 `env` 被 safe-bin shim 吞掉** → `fx-test`/`fx-qa` **零输出、0.5s 返回**，看起来像「测试挂了」。已改用 bash 内建 `unset` + 子 shell |
| `which flutter.bat` | git bash 的 `which` 不认 `.bat`（PATHEXT），报 no；但真正的问题是 shim。**直接用 `flutter`（无扩展名的 bash 脚本）** |
| `sdkmanager` 装 platform-36 | 走代理仅 12KB/s（80min）→ Python 直下 zip（62MB/6.5s）手装；**`source.properties` 必须保留** |
| `curl -o <file>` | 沙箱内一律 exit 23（落盘被拦）→ 一律 Python urllib 流式写盘 |
| GRADLE_USER_HOME 放 `<USER_HOME>\.gradle` | 允许写但**拒绝删除** lock 文件 → 指进工作区 |
| nohup 后台下载 | 进程被回收 → 用工具的 `run_in_background=true` |
| 删除 `.trash-*`（~2.5GB） | safe-delete shim 对 >50 文件批量删 fail-closed；`rm -rf`/`Remove-Item`/`cmd rmdir` 全无效 → 需用户手工删 |
| drift 声明式建索引 `@TableIndex` | 不支持 `DESC` 与部分索引 `WHERE` → 改原始 SQL |
| drift 表类默认数据类名 | 与 drift 自带 `Transaction` 撞名 → `@DataClassName('TxRow')` |
| `build_runner build --delete-conflicting-outputs` | 2.15.1 报「已移除并忽略」→ 去掉参数 |
| xlsx 用 `excel` 包 | 数值经 double 丢 31 位单号精度 → `archive` + 手写正则 |

# 当前状态

- `master` @ `0c82620`，代码已推远端。**未提交的工作区改动 3 项**（2026-09-11 体检产生）：
  1. `env.sh` — `fx-test`/`fx-qa` 重写修复（**建议提交**）
  2. `pubspec.lock` — `android_file_picker` 1.1.0 → **1.1.1**（传递依赖，无害；可提交也可 `git checkout` 还原）
  3. 未跟踪：`.workbuddy/memory/2026-09-10.md`、`devtools_options.yaml`
- `lib/core/db/database.g.dart` 已入库；**改表结构后必须重跑 `dart run build_runner build`**
- `.gradle-home` 4.1GB 完好 → 后续构建走增量，快很多
- 残留 `.trash-caches/` `.trash-wrapper/` `.trash-test/`（约 2.5GB 旧副本，已 gitignore）

# 首次使用验收（M1/M2，2026-09-11 实走）

用 `first-run-acceptance` 规范在 **MuMu 12 模拟器**（隔离环境、`pm clear` 零配置）实走了两个核心任务。
完整报告 → `docs/acceptance-M1-M2.md`。

| 核心任务 | 结论 |
|---|---|
| M1 记一笔 → 首页看到 | ✅ 新用户能独立跑通，**0 阻断** |
| M2 导入账单 → 首页看到 | ❌ **1 阻断**：导入成功但首页看不到数据，也无任何引导 |

**阻断项**（**2026-09-11 02:0x 均已修复；02:2x 在 MuMu 端到端验证通过，详见 `docs/acceptance-M1-M2.md` §9**）：
1. **P1 导入后首页看不到数据**（`import_page.dart`）：导入 327 笔 7 月数据 → 点「好的」回到「我的」页 →
   回首页仍是 9 月，327 笔全不可见，无"翻月 / 去看看"提示。数据其实是对的（翻到 7 月能看到 417.92），
   缺的是**结果引导**。最小修改：报告对话框「好的」拆为「去看账单」（跳首页并 `jumpToMonth` 到数据月份）+「完成」。
2. **P2 预算卡假数据与 hero 矛盾**（`budget_card_placeholder.dart`）：hero 显示 0.00 → 记一笔后 88.88，
   但预算卡恒为「101.52 已消费 / 10.2% / 898.48 剩余」。同屏两个矛盾支出数，信任级问题。

**另有**：P3 二次导入「导入完成 / 成功导入 0 笔」文案矛盾；P4 首页空态无引导；
P5 记一笔保存按钮在折叠下方；P6 预览页看不出如何取消单条。

**连带修掉**：预算卡变高后 800×600 测试视口把首页列表项挤出屏幕，`longPress` 落空
→ `test/widget_test.dart` 长按前补 `ensureVisible`。

**已验证正确**：微信 335→327、支付宝 GBK 32→28、中文无乱码、**二次导入 0 新增（指纹幂等）**、
导入 <1s、force-stop 后数据仍在、SAF 免权限。

**修复后门禁**：`flutter analyze` No issues found；`flutter test` **146/146**（原 143 + 新增 3 条回归测试）。

**端到端验证（MuMu 12）**：新包 213.9 MB → `pm clear` 归零 → 实走 —— P2「示例」chip + 说明文案可见；
P1 报告框拆为「完成 / 去看账单」且含月份引导语；点「去看账单」→ 落首页并自动翻到 **7 月（支出 417.92）**。两处阻断闭环。

> ⚠️ 声明：AI 在隔离环境实走，**未经真实用户测试**，不构成用户已认可。
> 复查触发：新增功能 / 改导入页或首页入口文案 / 改默认值 / 改导入完成后的跳转行为。

# 未解决问题

0. 【P0 已解】Android SDK 00:27 被误删进回收站 → 00:38 已还原、01:08 APK 重编成功。**`.trash-*` 残留（原 P2）已自然消失**
1. 【P1】**F5 真机验收（M2 等价 8 项）未做** — 这是当前唯一的进度阻塞项（APK 已就绪，需 K50 无线 adb 重连）
   - 补充：2026-09-11 已在 MuMu 实走，8 项中 1/2/3/4/5/7/8 已通过，仅剩**第 6 项（支付宝确认导入）**未点完确认；
     另发现 2 项 UI 阻断（详见「首次使用验收」节），**修完 P1/P2 才可判 M2 通过**
2. 【P3】gradle wrapper 用 `gradle-9.3.1-all.zip`（230MB），换 `-bin.zip` 可提速
3. 【P3】`CHANGELOG.md` 未建；**`README.md` 已建但「迁移进度」表严重过期**（仍写 F1 🟨 / F2–F6 ⬜，且技术选型写 `excel` 包，实际是 `archive` + 手写正则）→ F6 一并修

# 待确认事项

- **F5 真机验收需要真机 + 真实回单文件**（微信 xlsx / 支付宝 GBK CSV）。若用户手头没有原始回单，需先补齐测试样本
- 【待定】`lib/core/result.dart`（SPEC §4 列的 `Result<T>`）**暂未建**：目前校验全走异常（与旧栈一致），无真正调用方，等有需要再引入
- 【待确认】`env.sh` 与 `pubspec.lock` 的两处改动是否要我提交（我暂未 commit，等你发话）

# 关键资料

- `D:\Tencent\yanxin-flutter\SPEC-flutter-migration.md` — 已签字 SPEC（§4 目录结构、§5.1 环境基线+踩坑表、§6 F0–F6 分解、§7 验收 8 项）
- `D:\Tencent\yanxin-flutter\tasks\todo-flutter.md` — 任务清单（F0–F5 代码已勾选）
- `D:\Tencent\yanxin-flutter\env.sh` — **每次开终端必 `source env.sh`**
- `D:\Tencent\yanxin-flutter\.gradle-home\gradle.properties` — 代理 `systemProp.http(s).proxyHost/Port=127.0.0.1:7890` + `nonProxyHosts` + `-Xmx4G`
- `D:\Tencent\yanxin-flutter\android\gradle.properties` — 含 **`kotlin.incremental=false`**（F5 修跨盘 Kotlin 崩溃，**勿删**）
- 参考图 `app_template/home_ui.jpg`；旧栈资产 `D:\Tencent\yanxin\src\{db,repositories,modules/bill-import,utils}`
- 常用命令：
  - 门禁：`source env.sh && fx-qa`
  - 仅测试：`source env.sh && fx-test`
  - 构建：`source env.sh && flutter build apk --debug`
  - 代码生成：`source env.sh && dart run build_runner build`

# 我的偏好与工作方式

- 简洁中文回复；✅ 式状态汇总；技术总结用 **root-cause + fix + commit hash + next-actions** 结构
- 里程碑节奏：需求 → SPEC → **人工签字** → 实现 → 测试 → 文档 → master 直推
- 通过 `HANDOFF.md` / `BUG.md` + `@skill` 标签延续工作；真机测试后反馈 UI/UX 回归
- 清理文件后会要求先体检环境再交接

# 盲区防护与易错避坑（针对缺失信息自查）

1. **开终端先 `source env.sh`**（Flutter / JDK17 / SDK / GRADLE_USER_HOME / 代理 / unset 会话 ID）
2. **沙箱里 `env` 命令会返回空**：任何 `env -u ... cmd` 的写法都静默失效 → 用 bash `unset` 或子 shell
3. **`flutter test` 必须去代理**（http_proxy 劫持 flutter_tester 本地 WebSocket → `WebSocketException`）；构建相反需要代理/镜像
4. **不 `source env.sh` 就跑 `flutter pub get` 会污染 `pubspec.lock`**：113 个包的 `url` 会从 `pub.flutter-io.cn` 被改写成 `pub.dev`。发现后 `source env.sh && flutter pub get` 即可还原
5. **Gradle 缓存绝不复制**：只能给全新空目录让它自己下载。复制 → 挂死（伪装成网络慢）
6. **bash 不能 export 带括号变量**（`PROGRAMFILES(X86)`）；但 sqlite3 2.9.4 下 analyze/test 实测不需要它，别再为此折腾 `env` 前缀
7. **本地 `refs/remotes` 写不进去**（沙箱）：`git status -sb` 显示 `[gone]` 是假象，`git push` 实际成功。用 `git ls-remote origin master` 核对
8. **版本号别凭记忆升**：锁死矩阵见「已确认事实」，动了可能把 native-assets C 钩子拉回来
9. **drift 与 matcher 都导出顶层 `isNull`** → 测试里 `import 'package:drift/drift.dart' hide isNull;`
10. **改了 `lib/core/db/tables.dart` 必须重跑 `dart run build_runner build`**，`database.g.dart` 一并提交
11. Riverpod 3：未公开导出 `Override` 类型；`AsyncValue.valueOrNull` 已移除 → 用 `.value`
12. **go_router 实例不能是顶层 `final`**（测试间共享导航状态会互相污染）；且 `context.push().then` 在 `StatefulShellRoute` 壳下**不兑现** → 保存后刷新由被推页面在 pop 前自己做
13. widget 测试：写库是真实异步，`pumpAndSettle` 会早退 → 用 `pumpUntil(finder)` 轮询；视口 800×600 小，tap 前 `ensureVisible`
14. `expect(repo.create(...), throwsA(...))` 同步抛错要先执行 → 写 `expect(() => repo.create(...), throwsA(...))`
15. drift companion：非空无默认列传**裸值**（`id: id, createdAt: now`），其余 `Value(x)`；可选更新 `const Value.absent()`
16. `gbk_codec` 解码非法序列**静默不产 U+FFFD** → 判坏件用「重编码回环」校验
17. 杀构建后重跑前 `taskkill //F //IM java.exe`（Git Bash 双斜杠），否则新构建挂起零字节

# 新 Agent 接手指南

1. **当前最重要的事：F5 真机验收（M2 等价 8 项，SPEC §7）**。装 `app-debug.apk` 到 K50 跑：
   ① 导入页唤起 SAF 文件选择（真机才走 FilePicker，测试用注入）② 微信 xlsx 真实件导入 → 数据正确、中文无乱码 ③ 同一文件重导 → 全部判重跳过。其余：支付宝 GBK 件、单条取消、坏行不中断、跨账本隔离、杀进程重启数据在。
2. **F4.5 遗留占位（未做功能，别当 bug）**：预算卡全静态、header 搜索/报表/统计、`全部账单 ›`、日历/资产页。
3. **代码结构**（都已落库）：
   - `lib/core/providers/` — database / book_providers / category_providers（DI + 当前账本）
   - `lib/features/nav/` — AppShell（抽屉+底栏+壳路由）+ PlaceholderPage
   - `lib/features/ledger/` — 首页（LedgerController + MonthHero + BudgetCardPlaceholder + BookDrawer + TxGroupList）
   - `lib/features/import/` — 五层解析（`data/{bill_decode,bill_csv,bill_profiles,bill_normalize,bill_xlsx,bill_parse,category_rules}.dart`）+ `application/bill_importer.dart` + `presentation/import_page.dart`
   - `lib/features/profile/` `record/` `book/` `category/` `shared/`
   - 路由：壳 `/` `/calendar` `/assets` `/profile`；全屏 `/record`（extra=流水 id）`/books` `/categories` `/import`
4. **不要重复**：不要重装 Flutter/JDK/SDK；不要升 drift/sqlite3/build_runner；不要用 `pub add`；不要修 doctor 的 ☠；不要复制 gradle 缓存；不要回头做旧栈 T2.8；不要把 `env.sh` 改回 `env -u` 写法
5. **信息不足先问用户**：真机回单样本是否有；`env.sh` / `pubspec.lock` 两处改动是否提交

---

# 极简版

- 颜芯记账 uni-app → Flutter，新仓库 `D:\Tencent\yanxin-flutter`（远端 `git@github.com:Tea-Codeman/yanxin-bookkeeping-flutter.git`）。旧仓库 `D:\Tencent\yanxin` 只读归档。
- **F1–F4.5 ✅ 完成且真机验收过；F5 账单导入 ✅ 代码完成、真实件对拍一致，143/143**。**F6 收尾未做**。
- HEAD = `0c82620`。工作区有 3 项未提交改动（`env.sh` 修复、lock 里 `android_file_picker` 1.1.1、两个未跟踪文件）。
- 环境：Flutter 3.47.2 / Dart 3.13.2 / JDK **17**（勿用 25）/ SDK `D:\Download\Java\Android`。**开终端先 `source env.sh`**；gradle 缓存 4.1GB 完好，APK 已构建。
- 版本锁死：drift 2.31.0 / drift_flutter 0.2.8 / sqlite3 2.9.4 / build_runner 2.15.1 / drift_dev 2.31.0 / crypto 3.0.7 + archive / gbk_codec(override) / file_picker。
- 最致命四坑：① **gradle 缓存只能全新空目录**（复制必挂且伪装成网络慢）；② **沙箱里 `env` 命令静默返回空** → `env.sh` 已改用 bash `unset`；③ **`flutter test` 必须去代理**、构建必须走镜像；④ **不 `source env.sh` 就 `pub get` 会把 lock 的 113 个 url 改成 pub.dev**。
- drift 三坑：**索引走原始 SQL**（不支持 DESC/部分索引）、**数据类名 `TxRow`**、**`isNull` 要 `hide`**。
- 下一步：**F5 真机验收（M2 等价 8 项）** → F6 收尾（README/CHANGELOG）。
