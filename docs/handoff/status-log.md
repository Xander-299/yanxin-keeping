# 当前状态

- **✅ F7.16 自动记账三段修复 已交付（2026-10-20 转正 `v0.7.16`；代码基线 `84a35ed`）**：

  **C · 撤回通道 + 补抓守护层（代码基线 `84a35ed` · 2026-10-09 · 用户提案「悬浮窗」经查证否决）**

  - **用户主诉**：读通知采集，但「**返回微信/支付宝后通知会被丢弃，没来得及采集**」→ 提方案
    **用悬浮窗权限在支付成功页就采集**（附微信「支付成功 ¥0.01」页截图）。
  - **裁定：悬浮窗方案 ❌ 不可行（前提即错）** —— ① `SYSTEM_ALERT_WINDOW` **只授权「在别应用上层画窗口」**，
    **读不到别屏任何文字**（Play 把它与 screen capture / accessibility 明确分列）；② 要读屏只能换
    `AccessibilityService` → **Play 政策仅允许「服务身心障碍者」**，**Android 17.2 起 APM 模式下
    非无障碍工具被系统直接切断**；③ 用户截图那个页面**只有金额**，通知里本来就有 → **信息增量为零**。
  - **取证（新增 `tool/probe_notify_lifecycle.py`）**：支付通知**只活 26 秒**
    （`19:16:03` 出现 → `19:16:29` 最后可见，轮询 160 次 → `19:16:31` **被撤回**）；
    **对照组**支付宝「交易提醒」存活 **419 秒仍在** → **撤回不是通知自己消失，触发点是「用户点进去」**。
    撤回后 `getActiveNotifications()` 捞不到 → A 段补抓也有固有边界。
  - **⚠️ 更硬的根因（推翻了原「先做 requestRebind 自愈」的设计）**：同一笔 ¥0.01，
    **`onNotificationPosted` 一条都没收到** —— 进程健康（`foreground` cgroup、49 线程、未冻结、
    `oom_score_adj=250`）、绑定在（`Live notification listeners` 有）、补抓通道通；
    且 **`disallow`→`allow` 重绑也救不了**（恢复 `onListenerConnected` 与补抓，posted 仍 **0 条**）
    → 失效在「**NotificationManager → listener 的事件投递**」，**不可通过重绑自愈**。
  - **修 3 项**：① **`onNotificationRemoved` 第三层兜底**（撤回那一刻 extras 仍完整 —— AOSP 保证只丢
    `contentView`/`largeIcon`，而解析金额靠的 `EXTRA_TITLE`/`EXTRA_TEXT`/`EXTRA_BIG_TEXT` 全保留）；
    ② **`AutoBookGuard` 补抓守护层**（新文件：`AlarmManager` **60s 周期 + 每次醒来续期**
    —— 刻意不用 `setRepeating`，它在 doze 里被静默丢弃后会**永久停摆**；配 `BOOT_COMPLETED` /
    `SCREEN_ON` 两类唤醒源，Dart 侧 `ensureGuard` 在每次 drain 前补排期）；
    ③ **通道可用性自暴露**（8 个诊断字段 + `/autobook` 新增「采集通道」一行 + 按证据给可执行提示）。
  - ✅ **真机验证（Redmi K50 · 两笔真实 ¥0.01 均自动入账）**：`20:01:02` 由补抓捞到；
    **`20:05:31` 由 `removed → CAPTURED` 独立救回**（发生在通知已被撤回、补抓已捞不到之后）
    → `removedCaptureTotal` **0 → 1**，DB **163 → 164**、合计 **¥2363.42 → ¥2363.43**。
    守护层实测**每 ~53 秒准点触发**（19:57:09 → … → 20:06:01，共 12 轮）。
  - **门禁**：analyze 等效 **全项目 `No issues found!`** ✅；autobook 四文件 **99 passed / 0 failed**
    （`diagnostics` **17** / `flow` 17 / `real_samples` **18** / `rules` 47；
    ⚠️ **未跑全量 479**，但本批 Dart 改动仅 `lib/features/autobook/` 内 4 文件，已被这四个文件覆盖）。
    APK **BUILD SUCCESSFUL** + dex **13/13 探针命中** + **正式签名重签后覆盖安装（数据零丢失**，
    DB 196608 B / `integrity_check ok`）。
  - **两条踩坑（都差点误判成「环境坏了」）**：
    ⚠️ **`adb install -r` 会 force-stop 应用并清掉已排期的闹钟** → 装完立刻测会得到
    「守护层从不被触发」的**假结论**（本次先误判了一轮）；正确姿势 = 装完 → 重绑 → **等 ≥60 秒**。
    ⚠️ **「logcat 里 `posted pkg=` 为 0」不能证明回调没来** —— 代码只在 `decision != NOT_WATCHED` 时
    打日志，而探针是 `com.android.shell` 包名 → 走 NOT_WATCHED 分支 → **一行日志都不打**；
    **唯一可信判据是内存计数差分**（本次靠 `skippedNotWatched` 4730→4847 与 catchUp 扫描量比对才拿到真结论）。
  - ✅ **遗留已关闭（2026-10-20）**：用户同日提的「**扩展内置监听应用清单**」需求**经用户拍板不做**
    → 随 `[Unreleased] → [v0.7.16]` **一并转正并打 tag**。理由：**其它平台的支付最终都是银行卡支出**
    → 微信/支付宝通知已覆盖，扩白名单会**重复记账**；且现 `externalId` 含 `pkg`（跨来源必然不重）
    → 要支持扩展**必须先做跨应用去重**，收益为负。



  **A · 补抓（代码基线 `d44f8c6`）**

  - **触发**：用户报「通知栏里有支付宝、微信各一条支付消息，**均未被捕获**」（用户最初怀疑是关键词识别）。
  - **真根因**：`onNotificationPosted` 是**推送式回调** —— 通知在服务**未连接期间**发布时，系统**不会补发** → **永久丢失**。
    证据：支付宝付款通知 **22:29:37** 发布、服务 **22:49:40** 才连上；`lastCaptureAtMs` 停在 17:52:33、`capturedTotal` 恒为 2，
    而 `skippedNotWatched=226` 说明服务此前确实工作过（**「活着但没接上」**）。
  - **修 4 项**：① **补抓** `catchUp()` = `getActiveNotifications()`（24h 内 / 白名单 / 非组摘要 / 去重），
    在 `onListenerConnected` 时立即跑 + Dart 每次 `drainQueue()` **之前**经新通道方法触发；
    ② **`AutoBookSeen`（新文件）** 持久化指纹集 `pkg|title|text|postTimeMs`（cap 200）—— 否则反复补抓会**重复入队**并盖掉「上次检查」；
    ③ 抽出 `handle(sbn, fromCatchUp)` 让**实时与补抓共用同一条判定链** + `Decision` 逐层 `Log` +
    诊断补 5 个补抓字段（**必然落盘**，此前 `noteSkippedDedup` 不落盘 → 两种病因不可区分）；④ Dart 桥接 / 控制器插步骤 / `caughtUp`。
  - ✅ **真机验证（Redmi K50）通过**：重绑监听 → 补抓扫 **87** 条活动通知、补入队 **2** 条 → DB **165 → 166**，
    新增那笔 `cents=300 / expense / notify_alipay / occurred_at=22:29:37`（**真实支付时刻被完整保住**）；
    `catchUpTotal=6` 而 `catchUpAddedTotal` 恒为 **2** → **反复补抓零重复入队**。
  - ⚠️ **边界**：补抓只能捞「**此刻仍在通知栏里**」的通知（微信那条 `已支付¥1.00` 已被系统清掉 → **补不回**，
    用户需手动补记）；**补抓是兜底，主防线仍是服务保持连接时的实时捕获**。
    ⭐ 另修正一个既有认知：**重绑监听必须 `disallow_listener` → 2s → `allow_listener`**，单独 allow 不生效。
  - ✅ **未收口项已关闭（2026-10-20）**：「**扩展内置监听应用清单**」经用户拍板**不做** → 随本段一并转 `v0.7.16`。
  - **门禁**：analyze 等效 **`No issues found!`** ✅；`auto_book_flow_test` **17 passed / 0 failed**（15 → 17，+2）。

  **B · 微信支付「识别不到」= `[N条]` 折叠前缀误杀（代码基线 `85e416d`）**

  - **触发**：同一诉求的第二条 —— 微信那条**已被捕获入队**
    （`autobook_seen.json` 里有 `com.tencent.mm|微信支付|[3条]微信支付: 已支付¥0.03|1791473495452`），
    但 DB 的 `notify_wechat` 仍是 7 → 丢在**解析 / 入账**这一段（`lastCapturePkg=com.tencent.mm`、`lastDrainCount=1`）。
  - **真根因**：`auto_book_rules.dart` 的组摘要兜底 `^\[\d+条\]` 把正文 `[3条]微信支付: 已支付¥0.03`
    判成「组摘要」→ `parseNotification` 返回 null → **静默丢弃**。
  - **推翻旧判据（`dumpsys notification --noredact`）**：`Group summaries:` 段**无 `com.tencent.mm`**；
    `flags=0x11` 不含 `FLAG_GROUP_SUMMARY=0x200`；`groupKey == 自己的 key`（未进任何分组）；
    `tickerText` 无前缀 → `[N条]` 只是**显示层**加的前缀。当年那两个「反例」其实是**两笔不同交易**。
  - **修 3 项**：① Dart「丢弃」→「**归一化**」（剥 `^\s*\[\d+条\]\s*` 再解析，`combined`/`externalId`
    均用归一化文本 —— 折条数 `[2条]`→`[3条]` 不改变指纹，不会变成两笔）；② Kotlin 判定链**整体兜异常 + 打日志**
    （此前抛出去被系统吞掉，外部只看到「什么都没发生」，本次排查最痛的一点）；③ 测试 3 条**反转为回归守卫**。
  - ✅ **真机验证（Redmi K50）通过**：把真机原文注入落盘队列 → 回前台 drain → DB **167 → 168**、
    `notify_wechat` **7 → 8**，新增 `cents=3 / expense / occurred_at=`**`23:31:35`**（**真实发布时刻**）。
  - **门禁**：analyze 等效 **`No issues found!`** ✅；autobook 三文件 **82 passed / 0 failed**
    （`flow` 17 / `real_samples` **18** / `rules` 47 ⚠️ 未跑全量）。
  - ⚠️ **遗留**：Kotlin 侧在 23:31:35 **没收到实时回调**（只有补抓看到那条通知）仍未证死 ——
    现已补全链路日志 + 异常兜底，等**下一笔真实支付**时抓日志定位。
- **✅ F7.15 自动记账 已交付（tag `v0.7.15`，已推远端；代码基线 `e4e53b4`）**：
  - **需求**：用户要「自动记账」→ 选方案（**A 通知使用权为主 + D3 零权限兜底 + 强化已有导入**）→
    SPEC 签字时**设计乙**（静默入账 + 通知栏「已自动记账 N 笔」回执 + `撤销`/`查看` 两按钮）。
    SPEC = `docs/spec/SPEC-F7.15-auto-bookkeeping.md`（已签字；§3.7 三处 Android 硬约束、§3.5 忽略规则、§8 实施记录）。
  - **架构（唯一重决策）**：Kotlin **只做「包名过滤 + 落盘 JSONL 队列 + 发通知」，不解析、不碰库**
    （drift 是唯一 DB writer）；Dart 在 `AppShell` 首帧后 + 每次 `resumed` drain → 解析 → 按 source 分组 →
    **复用 `importRows()`** → 记批次 → 刷新 → 回执。**不启 headless FlutterEngine**（接受「入账延迟到下次打开 App」）。
  - **平台侧（本项目首次引入 manifest 权限 / service / intent-filter）**：`android/.../autobook/`
    （`AutoBookListenerService` / `AutoBookQueue` / `AutoBookNotifier` / `AutoBookChannel` / `AutoBookDiagnostics`）
    + `MainActivity` 接线 + `AndroidManifest`（`POST_NOTIFICATIONS`、`<service android:exported="false"
    android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">`、`ACTION_SEND` filter）
    + 矢量通知小图标 `res/drawable/ic_stat_autobook.xml`。**零 Gradle 新依赖**（权限自检走 `Settings.Secure`）。
  - **Dart 侧**：`lib/features/autobook/` **9 文件**（rules / bridge / batches / diagnostics / accounts /
    controller / notice / page / banner）+ `/autobook` 路由 + 「我的 → 自动记账」条目 +
    首页 `MonthHero` 上方提示条 `AutoBookBanner`；`ImportReport` 追加 `importedIds` / `importedAmountCents`
    （有默认值 → 既有调用方零改动）。`source` 取值域 `notification` → `notify_wechat` / `notify_alipay` / `share`
    （TEXT 无 CHECK → **零迁移，DB 仍 v3**；批次记录复用 `schema_meta` KV 键 `autobook_batches`）。
  - **本轮补丁（2026-10-07，用户反馈「自动记账不生效，只成功过一次」之后）**：
    **第一交付 = 可诊断性**（原四个断点每层都静默）→ 新增 `AutoBookDiagnostics.kt`（关键事件跨进程落盘）+
    channel `diagnostics` / `restoreQueue` + `/autobook` 页「**诊断**」区块（监听服务 / 最近捕获 / 待入账 /
    上次检查 / 抓取统计 + 按证据给一句可执行提示）+ 「上次检查」落 `schema_meta` KV（`autobook_last_run`，零迁移）。
    **修 3 个缺陷**：① 丢账路径（P0，`drain` 读出即清空 + Dart 三条 early return → 通知永久消失）→
    新增 `AutoBookQueue.restore()`：**临时性失败回写重试，解析不出的永久性失败仍丢弃**（否则无限重试）；
    ② 忽略规则误杀真实回执（P0）→ 拆 硬忽略 / 软忽略 / 强支付词 三张表，「软忽略命中且无强支付词」才丢；
    ③ 多金额取错（P1）→ 金额优先级 **实付类 > 支付动作紧邻 > 货币符号 > 裸金额**。
  - **门禁（全闭合）**：analyze 等效 **全项目 `No issues found!`** ✅；**用户终端 `flutter test` 479 passed / 0 skipped** ✅
    （2026-10-08；= `test()` 391 + `testWidgets` 88）；本机可跑部分：纯 `test()` **386 例全绿 / 0 失败**（分 4 批 49 文件），
    本批 autobook 三文件 `rules` **47** + `flow` **15** + `real_samples` **16**；**APK `BUILD SUCCESSFUL`** + `verify_apk_kernel` 通过 ✅。
  - **模拟器走查（MuMu · 用 `ACTION_SEND` 分享路径 —— 不受包名白名单限制）**：落盘 → drain →
    解析（「你已付款成功，优惠 0.50元，实付 12.00元」正确取**实付 ¥12.00**，旧版会丢弃）→ 入账 →
    自动建「分享记账」账户 → 首页提示条「已自动记账 1 笔 · 合计 ¥12.00」→ 撤销（软删 + 摘批次）→
    **回执通知**（`channel=autobook` / 标题「已自动记账 1 笔」/ 动作 `撤销`·`查看` / InboxStyle）→
    诊断区块五行全部与真实状态一致 ✅。截图在 `.workbuddy/qa-f715/`（**已按 `.gitignore` 的 `qa-*` 惯例命名，
    不进 `git status`**）。
  - **✅ 真机走查（2026-10-08 · Redmi K50 · 代码 `e4e53b4`）—— 监听路径已闭环，不再是「未验证」**：
    - **断点逐层**：① 系统绑定 `cmd notification allow_listener` + `dumpsys activity services` ✅ /
      ② 服务收通知（发**非白名单**探针通知 → `skippedNotWatched` **0→1**）✅ /
      ③ Dart 取队列（注入队列行 → `lastDrainCount / drainedTotal` 计数正确）✅ /
      ④ 解析入账（8 条真实文案注入 → `last_run = imported:6 dropped:2` **逐条吻合**）✅。
    - **真实支付端到端**：用户实付支付宝 **¥0.01** → 入库 `cents=1 / type=expense / src=notify_alipay`
      —— 这条通知**正是修复前的死案例**（标题撞 `提醒`、正文撞 `红包`），金额·方向·来源**全对**。
    - **真机文案已固化**：`test/features/autobook/auto_book_real_samples_test.dart`（16 例，逐字抄自真机）。
    - ⚠️ **判读口径**：`lastCaptureAtMs` 是**捕获时刻**，通知自身 `postTimeMs` 才是**交易时刻**
      （重投场景实测差 **1 分 37 秒**）—— 别拿两者互相校验。
    - 取证手法见 `.workbuddy/memory/2026-10-08.md`（`dumpsys notification --noredact` 抓文案、
      `run-as` 读 App 私有队列、`cmd notification post` **伪造不了包名**所以只能靠真实通知验第①层）。
  - ✅ **无遗留项**：真机监听路径 + 真实通知文案 + **用户终端全量 `flutter test`（479 passed / 0 skipped）** 三项均已验完。
    （「我的」页 `_BrandTip` 角标早在 `3ec2381` 实现提交里就已置 `v0.7.15` → 原收尾清单里「角标 → `v0.7.15`」这条已自然消解，无需再改。）
  - **收尾已执行**：`## [Unreleased]` → `## [v0.7.15]`（含 I 段）+ tag 表补行 → `git tag -a v0.7.15` →
    `git push && git push --tags`（**直推、不加管道**）→ `git ls-remote --tags` 核对
    → HANDOFF / SPEC §8 / `tasks/todo-flutter.md` / 当日 memory。
- **F7.14 新手引导 已交付 ✅（`v0.7.14` 已打 tag 并推远端）**：7 页全屏导览（底栏中央方块 / 首页三图标 /
  翻月 + 预算铅笔 / 三个隐藏手势 / 资产页与报表页）+ 「我的」重看入口 + **老用户不弹**。
  新增 `lib/features/onboarding/` 5 文件、`/onboarding` 路由、`AppShell` 首帧触发、
  `ActiveBookIdController.isFreshInstall`、`pumpApp` 默认预写标记。**零新依赖、不动 schema（仍 v3）**。
  门禁：`flutter test` **400 passed** ✅ / analyze 等效本批新增文件 **0 issue** ✅ /
  真机走查 **D1–D10 全部通过、0 崩溃** ✅（`docs/acceptance-F7.14-onboarding.md`）。
  收尾提交线 `02f9041`（代码）→ `c5ea1b5`（CHANGELOG 转正）；tag 对象 `b3c08c2` → 提交 `c5ea1b5`。
- **F7.9 记一笔「保存」入口改吸底常驻 + 启动图标 adaptive 已交付 ✅（`v0.7.12` 已打 tag 并推远端）**：
  **`flutter test` 372 passed / 0 skipped**（用户终端，2026-09-25；本批 +1）；收尾提交线
  `5ccb7c2`（角标）→ `1f3ec96`（CHANGELOG 转正 = tag 指向）；tag 对象 `dcab296` → 提交 `1f3ec96`。
  删掉 AppBar 右上角常驻「保存」，底部主按钮改**吸底常驻**（脱离 `SingleChildScrollView`，与滚动区并列在
  body 的 `Column` 里 —— **不能用 `Scaffold.bottomNavigationBar`**：它按 `screen height - h` 贴**屏幕**底、
  键盘弹起会被盖住）。接口提交 `d0ab794`；SPEC `docs/spec/SPEC-F7.9-record-sticky-save.md`（§3/§6 含上述前提修正）、
  走查 `docs/acceptance-F7.9-record-sticky-save.md`（D1–D3 / D5 / D6 / D8 通过；**D4 键盘项未取证** ——
  MuMu 有硬件键盘映射不弹软键盘，改矮视口做等价验证）。**零新依赖、不动 schema**。
  ⚠️ 测试口径：吸底按钮是滚动区的**兄弟节点、不在 `Scrollable` 内** → `tester.ensureVisible` 会
  `Scrollable.of` 返回 null 直接抛错（已删 3 处）。
  ⚠️ **回归首轮（用户终端）抓到 1 个漏改用例已修（`661ec6b`）**：`home_empty_state_test.dart` 里
  `expect(find.widgetWithText(AppBar, '保存'), findsOneWidget)` —— 顶部入口已删，断言必然失败。改判据为
  「AppBar 只有标题 `记一笔`」+「AppBar 无 `保存`」+「吸底 `ToonButton` 在位」。**教训**：改 UI 入口的
  测试口径时不要用 `head_limit` 截断 grep（当时 40 条上限吃掉了这个文件），关键词也别只搜 `AppBar`。
- **启动图标补齐 adaptive icon 已交付 ✅（`ec55229`）**：`flutter_launcher_icons` 只产 legacy
  `mipmap-*/ic_launcher.png`、**默认不产 adaptive** → Android 8.0+ 走 legacy 降级，系统给图标
  套白底 + 圆形遮罩（真机一圈白边）。补 `mipmap-anydpi-v26/ic_launcher.xml` +
  `values/ic_launcher_background.xml`（`#FFD81B`，源图主色）+ 5 个 density 前景层 +
  前景源图 `assets/icon/app_icon_foreground.png`（1024²，透明底，图形缩进 66% 安全区）；
  该包从 `dependencies` 移回 `dev_dependencies`（重复声明会让 lock 标 `direct main`）。
  新增工具（纯 Python 标准库 —— 本机 `dart run` 起不了管道子进程、沙箱无 Pillow）：
  `tool/png_util.py` / `gen_launcher_icons.py` / `inspect_icons.py` / `check_pubspec.py`。
  装机验证：MuMu 桌面 = 黄底圆角方 + 「记账」，**无白底白圈**。
- **构建阻塞已修 ✅（`b795541`）**：`android/app/build.gradle.kts` 里 `signingConfigs` 原本写在
  `buildTypes` **之后** → 配置阶段 `signingConfigs.getByName("release")` 求值失败 →
  `SigningConfig with name 'release' not found.`，**连 `assembleDebug` 都挂**（与 debug/release 无关）。
  已把 `signingConfigs` 上移到 `buildTypes` 之前；`key.properties` 不存在时回退 debug 签名
  （保证 clone 仓库的机器也能出包）。`.gitignore` 补 `key.properties` 兜底规则。
- **F7.8 流水左滑删除 已交付 ✅（`v0.7.11` 已打 tag 并推远端）**：删除入口由长按改为**左滑露出红色
  「删除」按钮 → 点按钮才删**（用户三项裁定，SPEC `docs/spec/SPEC-F7.8-swipe-delete.md`）；范围 = 首页 + 日历日账单 +
  搜索结果（报表页仍只读）；**零新依赖**（`SwipeActionRow` 手写：行程 ≥45% 或向左甩 ≥350px/s 吸附；单开协调；
  展开时点整行 = 收起）。**`flutter test` 371 passed / 0 skipped**（本批 **+10**，另改 2 例长按用例）。
  提交线 `8d8dc8e`（实现 + 测试）→ `29b5431`（SPEC + CHANGELOG）→ `0d5cf16`（白底修复 + 走查记录）→
  `5ecdcef`（`tool/verify_apk_kernel.py` + 走查技能补坑）→ `4248607`（HANDOFF 收尾）→ `8c56e9f`（角标）
  → `e984023`（CHANGELOG 转正 = tag 指向）= **`origin/master`**。
  ✅ 真机走查 D1–D7 全过、0 崩溃（`docs/acceptance-F7.8-swipe-delete.md`）；⚠️ 走查抓到 1 个**只真机能发现**的
  视觉 bug（`TxTile` 无自身底色 → 红色动作区透过行露出）**已修并复验**；走查删的 2 笔已还原。**不动 schema**（仍 v3）。
- **F7.7 D 批（搜索增强）+ E 批（日历增强）已交付：`v0.7.10` 已打 tag 推远端**（测试计数 **361** = `test()` 287 + `testWidgets` 74 +32；
  提交线 `bce6305`（D）→ `cfe17ff`（E）→ `04c2bfd`（快照修复）→ `27689a2`（构建工具 + skill）→ `de04841`（文档回写）
  → `16b6a00`（CHANGELOG 转正 = tag 指向））。
  ⚠️ **本批不动 schema**（SPEC §D.3 的「新建 `app_meta` 表 + schema 2→3」两处前提都不成立 → 复用既有
  `schema_meta` KV）；§E.1 的 `date` 参数实际约定是**毫秒**。
  ⚠️ 走查抓到并修了一个**老 bug**：搜索结果是过期快照（`searchProvider` 未接 `dataEpochProvider`）——
  详见 `docs/acceptance-F7.7-DE.md` 与 §G。
- **F7.7 C 批「账户图标 / 颜色」已交付：`v0.7.9` 已打 tag 推远端**（**329 全绿** + 覆盖安装验迁移走查通过，2026-09-24；
  提交线 `9dd2d9b`（实现）→ `6653988`/`6e192b7`（测试视口修复）→ `079dd09`（角标）→ `f782ec2`（CHANGELOG 转正，= tag 指向）。
  ⚠️ **SPEC §C.1 前提有误**：accounts 表本来没有 icon/color（在 books/categories 上）→ 实际做了 **schema v2→v3**
  （ALTER TABLE ADD COLUMN DEFAULT ''，onUpgrade 带 PRAGMA table_info 防御）。
- **F7.7 B 批「数据导出」已交付：`v0.7.8` 已打 tag 推远端**（315 全绿 + 走查无阻断，2026-09-23）。
- **F7.7 A 批已收尾：真机走查通过 → `v0.7.7` 已打 tag 并推远端**（F2 / F5 用户裁定**保持现状**）。
- ✅ **F7.7 backlog 五批（A→E）+ F7.8 左滑删除 + F7.9 吸底保存 + 启动图标 adaptive + 统计页图表绘制修复
  + F7.14 新手引导 全部落地**（`v0.7.7`–`v0.7.14` 已打 tag）→ **无待签字批次、无遗留项**；下一轮等用户排新需求。
- **门禁**：`flutter analyze` ✅ **0 issue**（等效手段 `python tool/dart_analyze_fallback.py` —— 本批新增文件
  `No issues found!`；⚠️ 全项目残留 5 条 `盘符大小写不一致的 双身份**既有环境假阳性**，见「盲区防护」第 48 条）；
  `flutter test` ✅ **400 passed / 0 skipped**（**2026-09-25 用户终端全量**，本批 +17
  = `test()` **312** + `testWidgets` **88**）。
- **本机（A 机）代码基线 = `c5ea1b5`**（`v0.7.14` tag 指向；文档收尾提交 `fa024db` 在其后）（F7.6 P1/P2/P3 + 走查修复 + 版本记录 + F7.7 SPEC
  + **F7.7 A/B/C/D/E 五批** + **F7.8 左滑删除** + **F7.9 吸底保存** + **启动图标 adaptive**
  + **统计页图表绘制修复** + **F7.14 新手引导** + **F1 修复**
  + 构建阻塞修复 + 九个等效 / 核验 / 生成工具 已入库；**tag = `v0.7.14`**）。
- 已含 **F1–F7.6 P3**：日历 / 统计 / 预算（schema v2）/ 搜索 / 搜索浮层 / 资产页 / **全站卡通浅色视觉**；
  **F7.7 A 批**（报表明细 + A.0 记一笔选账户）已入库。**工作区现干净**（原本长期未提交的桌面名
  `android:label="颜芯记账"` **已随 F7.15 实现 `3ec2381` 入库**）。
- **本机门禁历史**：F7.6 P3 后曾复跑 `flutter analyze` No issues found + `flutter test` **269 passed / 0 skipped**；
  ⚠️ 2026-09-23 起本机 Dart 起不了「需要管道 stdio」的子进程 → 这两条命令在本机**直连跑不了**（见「未解决问题」第 1 条），
  已由三个等效工具接管（analyze / test / 数据层实跑）；**用户自己的终端不受影响**。
- `lib/core/db/database.g.dart` 已入库；**改表结构必须重跑 `dart run build_runner build`**。
- ⚠️ **深色主题已被 F7.6 彻底移除**（用户确认）：全站只有一套卡通浅色主题，`docs/design/*.jpg` 旧参考图作废。
- APK：本地 `build/app/outputs/flutter-apk/app-debug.apk` = **F7.15 代码（含活性诊断）**（2026-10-07 用「kernel 兜底」路径构建，
  已核验 APK 内 `kernel_blob.bin` sha256 与盘上一致 + 新文案可 grep，`aapt2 dump xmltree` 确认 service / 权限 / filter 都进了包）；
  release 仍是 F7.1 时期产物。
  ⚠️ **本机直连 `flutter build` / `gradlew assembleDebug` 会撞 231** → 走「未解决问题」第 1 条的 kernel 兜底路径。
- 模拟器：MuMu 12 在本机可用（`<EMULATOR_HOME>`，adb 16384）；**走查前先确认 MuMu 已启动**（`adb devices` 空会导致 `adb wait-for-device` 永久挂住）。
  ⚠️ **MuMu 上装的 App 曾长期是 2026-09-25 的旧包**（`files/` 里无任何 autobook 文件）—— 装机后先
  `adb shell run-as com.teacodeman.yanxin ls files/` 确认有 `autobook_queue.jsonl` / `autobook_diag.json` 才算装到了新包。
  ✅ 2026-09-23 走查留下的临时账本 **`QA-Temp` 已软删**（`run-as` + 设备自带 `sqlite3` 改 `books.deleted_at`；
  改前已备份到 `app_flutter/yanxin.sqlite.bak-20260923`）。抽屉现在只剩「默认账本」，走查造的流水（88.88 那笔）与预算数据完好。
- **本机 = 远端（F7.15 已收尾推送）** —— **2026-10-08 复核** `git ls-remote origin refs/heads/master` = **收尾提交**
  （= **`v0.7.15`** tag 指向）；**最新 tag = `v0.7.16`**，代码基线 = **`84a35ed`**。
  （上一版 `v0.7.14` tag 指向 `c5ea1b5`，含 F7.7 A/B/C/D/E 五批 + F7.8 左滑删除 + F7.9 吸底保存 + 启动图标 adaptive
  + 统计页图表绘制修复 + F7.14 新手引导 + 构建阻塞修复 + 全部门禁 / 构建 / 核验 / 生成等效工具。）
  F7.15 线 7 个提交（`3ec2381` → `d51ffe8` → `a545687` → `76a5e31` → `bdcbf76` → `e4e53b4` → 收尾提交）
  **均已推远端**；工作区干净；
  `.qa-probe/` 等临时产物已归档到 `.workbuddy/trash/20260923-*`（**该目录需用户手工删，>50 文件会被 safe-delete 拦**）；
  工作区已有九个**已入库**的工具：`tool/dart_analyze_fallback.py`（等效 analyze）+
  `tool/dart_test_fallback.py`（等效 test）+ `tool/data_layer_probe.py`（数据层实跑）+
  **`tool/build_kernel_fallback.py`（等效 `flutter assemble` 的 kernel 步骤，配合
  `./gradlew assembleDebug -x compileFlutterBuildDebug` 出 APK）** + `tool/verify_apk_kernel.py`（装机前核验）
  + 图标链 `tool/png_util.py` / `gen_launcher_icons.py` / `inspect_icons.py` + `tool/check_pubspec.py`。
  tag `v0.7.1`…`v0.7.15` 已推远端（**`v0.7.15` = 当前最新**，指向收尾提交；`refs/tags/v0.7.14^{}` = `c5ea1b5`）。

# 待确认事项

- 【**已全部裁定 / 已签字**】**F7.7 SPEC 的默认处理**：① **A.0 做** —— 记一笔加第 4 个字段「账户」
  （默认仍是列表首个账户，老行为不变，老用例不受影响）**已实现**；② **D.5 拼音 / 首字母匹配：不做**（已执行）；
  ③ **E.5 农历 / 节假日：不做**（已执行）。另裁定：**报表页流水行只读、不可点**（按 §A.4）。
  B 批「全部按 B.4 默认」、C 批、D/E 批均已签字并交付 → **五批全部落地，无待签字项**。
- 【**已推翻 · 别再按 SPEC 原文做**】**D 批原计划「新建 `app_meta` 表 + schema v2→v3」不成立** ——
  `schema_meta`（`key` + `value`）本来就是 PRD 登记的 KV 表 → **复用，本批零迁移**。
  当前 DB **schemaVersion = 3**（v3 是 **C 批**加的 `accounts.icon` / `accounts.color` 两列，不是 D 批）。
  搜索历史落 `schema_meta` 键 `search_history`（JSON 容错解析，最近 10 条）。
  ⚠️ 通用规矩：**动 schema 必须走「真机覆盖安装验迁移」**，内存库单测只能证明 `onUpgrade` 逻辑本身。
- 【**F7.14 已知取舍 · 非缺陷，用户尚未要求改**】① 引导页内容整体**偏上、下方留白较大** —— 这是为换取
  「矮视口（逻辑 450×500）不溢出」而做的取舍（内容可滚 + 底部按钮固定）；② **页面原型
  `D:
ew file\modao\yanxin\` 没有引导屏** → 视觉并排对拍**不适用于引导页**，只按 SPEC §3.2 文案与
  `Tok.*` 令牌约束实现；③ 真机走查跑在 **MuMu 12 模拟器**上，**物理真机未验**。
- 【**✅ 已解决（2026-10-07）**】**桌面应用名**：`AndroidManifest.xml` 的 `android:label` 原为脚手架默认
  `"yanxin"`（桌面显示「yanxin」）→ 用户 2026-09-25 自行改成 `"颜芯记账"`，**已随 F7.15 实现提交 `3ec2381` 入库**
  （现工作区干净）。另 `<service>` 声明里也带了一条 `android:label="颜芯记账 · 自动记账"`（通知设置页展示用）。
- 【**✅ 已解决（2026-10-08）**】**F7.15 §3.5 忽略规则 —— 已按真机文案定稿**：硬忽略（`转账 / 退款 / 已退款 /
  充值成功 / 验证码 / 月账单 / 账单汇总 / 还款`）+ 软忽略（`优惠 / 立减 / 满减 / 活动 / 红包 / 提醒 / 领取 /
  积分 / 即将`）+ 强收支词（含 `支出 / 收入 / 已收款 / 成功收款`）三层（**软忽略命中且无强收支词才丢**）。
  真根因：支付宝付款通知**标题就叫「交易提醒」**、正文含「红包」→ 旧版两处硬忽略一票否决 → **静默丢弃**。
  规则已对着**真机原文**写并固化为 `test/features/autobook/auto_book_real_samples_test.dart`（16 例）。
- 【**✅ 已解决（2026-10-08）**】**三处「推测实现」已用真机文案校正**：① 忽略表（上条）；
  ② **金额优先级** —— 新增「金额在动作词之前」规则压过营销语金额（真机实测「你有一笔0.01元的支出，领1元生活缴费红包。」
  旧版会取到 `1元`）；③ **商户提取** —— 通知**确实通常不含商户名**，自动分类落「其他」是**预期行为**（备注退化为
  「微信支付 / 支付宝支付」），纠错入口 = 提示条 + 撤销，**不再是待修缺陷**。
- 【待确认】`android/gradle.properties` 里 `org.gradle.jvmargs=-Xmx8G` 是 B 机调大的；**A 机内存未知**，若构建 OOM 可改回 `-Xmx4G`
- 【待确认】`lib/core/result.dart`（SPEC §4 的 `Result<T>`）**暂未建**：校验全走异常，无调用方，等有需要再引入
- 【待确认】日历页是否要加农历 / 节假日（原型参考图上有，当前无农历依赖）→ **已并入 F7.7 SPEC 的 E.5**，默认不做
- 【**发布签名已就绪**（2026-09-25 用户配置，AI 只修了阻塞）】`android/key.properties`
  四键齐全（`storePassword` / `keyPassword` / `keyAlias` / `storeFile`），keystore 在仓库**外**
  （`<USER_HOME>\upload-keystore.jks`，10:27）；`android/.gitignore` 已有 `key.properties` +
  `**/*.jks` + `**/*.keystore` → `git check-ignore` 通过、**未被追踪** ✅（`.gitignore` 根目录另加了兜底规则）。
  `build.gradle.kts`：有 `key.properties` 时用正式签名，**缺失时回退 debug 签名**（保证 clone 的机器也能出包）；
  ⚠️ `signingConfigs` 必须声明在 `buildTypes` **之前**（否则连 debug 构建都在配置阶段挂 —— `b795541` 已修）。
  ⚠️ **release 出包未在本机验证**：release 走 AOT（`gen_snapshot` → `libapp.so`），本机那套 kernel 兜底只覆盖
  debug 的 `kernel_blob.bin` → 需在**用户终端**跑 `flutter build apk --release` 确认。

# 极简版

- 颜芯记账 uni-app → Flutter。**两台机器共用一个远端**（**SSH** `git@github.com:Xander-299/yanxin-bookkeeping-flutter.git`，`git push` 免凭据）：
  **A 机（本机）** = 用户 `panda`、`D:` 盘、仓库 `<REPO>`、MuMu 12；**B 机** = `Administrator`、`C:/M:` 盘、MuMu 15。
  `env.sh` **自动识别机器**，开终端先 `source env.sh`。
- **F1–F7.6 全部 ✅**（日历 / 统计 / 预算 schema v2 / 搜索 / 搜索浮层 / 资产页 / 全站卡通浅色 `v0.7.6`）。
- **F7.7 五批（A 报表明细 → B 数据导出 → C 账户图标·颜色 → D 搜索增强 → E 日历增强）全部已签字 + 已实现 + 已走查**：
  `v0.7.7`–`v0.7.10` 已打 tag（D + E 合并为 `v0.7.10`，**361 全绿**）。
  **DB schema = v3**（v2 加 budgets、v3 加 `accounts.icon` / `accounts.color`）；**D 批零迁移**（复用既有 `schema_meta` KV）。
- **F7.8 流水左滑删除 已交付 ✅（`v0.7.11` 已打 tag 并推远端：371 全绿 + 走查 0 崩溃）**：
  长按删除 → **左滑露出红色「删除」按钮，点按钮才删**
  （首页 / 日历日账单 / 搜索 3 处；报表页仍只读；零新依赖；**不动 schema**）。
- **统计页图表两处绘制修复 已交付 ✅（`v0.7.13` 已打 tag 并推远端：383 全绿 + 走查 0 崩溃）**：
  ① 分类圆环 `drawArc(useCenter: true)` 笔误 → 每瓣从圆心辐射实心楔形（风车）并盖住圆心文字，已改 `false`
  两处（含空态底槽），接缝改两端各让一半；② 趋势图零值月仍画 2px 基座胶囊 → 用户裁定**不画**，
  抽纯函数 `trendBarHeight(cents, max) → double?`（null = 不画），`_Bar` 早退留同宽占位防漂移。
  报告 `docs/acceptance-F7.13-stats-charts-fix.md`。**别重写**（代码已在 `0773333`）。
- **F7.9 记一笔「保存」入口改吸底常驻 + 启动图标 adaptive 已交付 ✅（`v0.7.12` 已打 tag 并推远端）**：
  删掉 AppBar 右上角「保存」，底部主按钮**吸底常驻**（body 内 `Column`，**不能用
  `Scaffold.bottomNavigationBar`** —— 它不随键盘上移、会被键盘盖住）；零新依赖、不动 schema。
  SPEC `docs/spec/SPEC-F7.9-record-sticky-save.md`、走查 `docs/acceptance-F7.9-record-sticky-save.md`
  （D4 键盘项受 MuMu 无软键盘限制，改矮视口做等价验证）。回归首轮抓到 1 例漏改
  （`home_empty_state_test` 仍断言 AppBar 有「保存」）**已修 `661ec6b`**。
  启动图标：Android 8+ 不再套白底白圈（`ec55229`）；`flutter_launcher_icons` **只留在 `dev_dependencies`**
  （**别再往 `dependencies` 加一份**）。
- **F7.16 自动记账三段修复已交付 ✅（`v0.7.16`，2026-10-20 收口）**：
  **A · 补抓**（`d44f8c6`）：`onNotificationPosted` 是**推送式回调** → **服务未连接期间发布的通知系统不补发**
  （真机：支付宝付款 22:29:37 发布、服务 22:49:40 才连上）→ 新增**补抓** `catchUp()`（扫 `getActiveNotifications()`：
  24h 内 / 白名单 / 非组摘要 / 去重）+ **`AutoBookSeen`（新）** 持久指纹集（防反复补抓重复入队）。
  ✅ 真机验证：DB **165 → 166**，补记那笔 `cents=300 / occurred_at=22:29:37`（**真实支付时刻**）。
  ⚠️ 边界：只能捞「**此刻仍在通知栏里**」的通知；⭐ **重绑监听必须 disallow→allow**（单独 allow 不生效）。
  **B · 微信支付「识别不到」**（`85e416d`）：正文 `[3条]微信支付: 已支付¥0.03` 被 Dart 的 `^\[\d+条\]`
  **误判成组摘要丢弃** → 改成**剥前缀再解析**（`combined` / `externalId` 均用归一化文本）。
  取证：`Group summaries:` 段**无 `com.tencent.mm`** + `flags=0x11` 不含 `FLAG_GROUP_SUMMARY` +
  `groupKey == 自己的 key` + `tickerText` 无前缀 → `[N条]` 只是**显示层**前缀。
  ✅ 真机验证：真机原文注入队列 → DB **167→168**、`notify_wechat` **7→8**（`cents=3 / occurred_at=23:31:35`）。
  **C · 撤回通道 + 补抓守护层**（`84a35ed`，2026-10-09）：用户提「**用悬浮窗在支付成功页采集**」→ **否决**
  （该权限只授权「盖在上面」读不到别屏文字；读屏要换无障碍 → Play 政策仅允许助残、Android 17.2 起 APM 切断；
  且那页面只有金额，通知里本来就有）。实测真因：**支付通知只活 26 秒**（`19:16:03` 出现 → `19:16:29` 最后可见 →
  `19:16:31` 被撤回，**触发点是用户点进支付成功页**；对照组支付宝通知存活 419 秒仍在）；
  且 **`posted` 推送在该机型一条都不投递**（进程健康 / 绑定在 / 补抓通，**重绑也救不了**）。
  → 新增 **`onNotificationRemoved` 兜底**（撤回时 extras 仍完整，AOSP 保证只丢 `contentView`/`largeIcon`）
  + **`AutoBookGuard` 守护层**（`AlarmManager` 60s 周期 + **醒来续期**）+ 通道可用性诊断（`/autobook` 加「采集通道」行）。
  ✅ 真机验证：两笔真实 ¥0.01 均自动入账（DB **163→164**、¥2363.42→**¥2363.43**），
  **其中一笔由 `removed → CAPTURED` 独立救回**（`removedCaptureTotal` 0→1）；守护层每 **~53 秒**准点触发（12 轮）。
  ⚠️ **本轮踩坑**：① `adb install -r` 会 force-stop 应用**并清掉已排期闹钟** → 装完立刻测会得到
  「守护层从不被触发」的**假结论**（先误判了一轮）；② 「logcat 里 `posted pkg=` 为 0」**不能**证明回调没来
  （代码对非白名单不打日志）→ **用内存计数差分**判别。
- **功能代码基线** = **`84a35ed`**（= F7.16 C 收口段，11 files / +974 −1；A 段 = `d44f8c6`，B 段 = `85e416d`）；
  **最新 tag = `v0.7.16`**（2026-10-20 收口；再往前 `v0.7.15` → `5321d4e`，`v0.7.14` → `c5ea1b5`，
  tag 对象 `b3c08c2`）（F7 阶段一版一 tag，表在 `CHANGELOG.md` 顶部）。
- ⚠️ **本机环境阻塞（仅限本机）**：Dart 起不了「需要管道 stdio」的子进程（`CreateFile failed 231` / `process_win.cc:744`）
  → `flutter analyze / test / pub / build_runner` / **构建** 在本机直连全废。**别怀疑代码、别换 Dart 版本、别开 `dangerouslyDisableSandbox`**。
  九个工具 / 替代链路（已入库）：`python tool/dart_analyze_fallback.py`（≡ analyze，**已跑 → `No issues found!`**）、
  `python tool/dart_test_fallback.py`（≡ test，纯 `test()` **312** 例，⚠️ `testWidgets` 跑不了）、
  `python tool/data_layer_probe.py`（数据层实跑）、
  `python tool/build_kernel_fallback.py` + `./gradlew assembleDebug -x compileFlutterBuildDebug`（出 APK）、
  `python tool/verify_apk_kernel.py`（装机前核验 kernel 新鲜度）、
  `python tool/inspect_icons.py` / `tool/check_pubspec.py`（图标与 pubspec 体检；生成用 `tool/gen_launcher_icons.py`）。
  **用户自己的 Git Bash 终端不受影响**。协议三坑见 SPEC §G（行分隔 JSON / OS 路径无尾斜杠 / `isAnalyzing` 完成信号）。
- **门禁状态**：**截至 `v0.7.15` 全部闭合 ✅** —— analyze **0 issue**（等效手段；全项目残留 5 条
  为 `盘符大小写不一致的 双身份既有假阳性）；`flutter test` **479 passed / 0 skipped**（**2026-10-08 用户终端全量**，
  = `test()` **391** + `testWidgets` **88**）；真机走查 ✅（F7.14 D1–D10 全过 0 崩溃 + **F7.15 断点 ①–⑤ 全过**）。
  ✅ **F7.15（自动记账）已交付 `v0.7.15`** —— analyze 等效 `No issues found!` + 终端 `flutter test` **479 passed**
  + 本机纯 `test()` **386 例全绿**（分 4 批）+ APK 构建/核验通过 + **真机断点 ①–⑤（含用户实付支付宝 ¥0.01 端到端入账）**。
  ✅ **F7.16（三段修复，已转正 `v0.7.16`）** —— A·补抓（代码基线 `d44f8c6`）+ B·微信支付 `[N条]` 误杀（代码基线 `85e416d`）
  均 analyze `No issues found!` ✅ + autobook 三文件 **82 passed / 0 failed**（`flow` 17 / `real_samples` **18** / `rules` 47）
  + 真机端到端通过（A：DB 165→166 补记支付宝 ¥3.00；B：DB 167→168 补记微信 ¥0.03）。⚠️ **未跑全量 479**；⚠️ **未收口**：
  ① 扩展监听应用清单（跨应用去重前置）待做；② 微信 23:31:35 实时回调未收到仍未证死。
  ⚠️ **本轮踩到**：`android/local.properties` 被 flutter 工具改写成 `release / versionCode=1` →
  直接 `assembleDebug` 出的包 versionCode=1，而设备上是 2001 → `install -r` 撞降级。**构建前先看这个文件。**
- 完整功能需求清单：`docs/PRD-yanxin-flutter.md`。版本锁死：drift 2.31.0 / drift_flutter 0.2.8 / sqlite3 2.9.4 / build_runner 2.15.1 / drift_dev 2.31.0 / crypto 3.0.7 + archive / gbk_codec(override) / file_picker。
- 最致命五坑：① **gradle 缓存只能全新空目录**（复制必挂、伪装成网络慢）；② **Bash 的 PATH 要先补 `/usr/bin:/bin`**（否则 grep/flutter 各种怪报）；③ **`flutter test` 必须去代理**、构建走镜像；④ **不 `source env.sh` 就 `pub get` 会把 lock 的 url 改成 pub.dev**；⑤ **flutter 残留 `bin/cache/lockfile` → 命令卡死**（用 `mv` 挪走，别 `rm`）。
- drift 四坑：**索引走原始 SQL**、**数据类名 `TxRow`**、**`isNull` 要 `hide`**、**改表必重跑 `build_runner` + 迁移只能真机覆盖安装验**。
- 搜索：入口是**覆盖首页的浮层**（`showSearchOverlay`，不是路由）；口径 = 当前账本全量 + 内存过滤；
  命中 = 分类名 / **账户名** / 备注 / 金额子串 + 类型指令「仅支出 / 仅收入 / 转账」+ **时间区间（全部 / 本月 / 近3月）**；
  命中处高亮（`core/utils/highlight.dart`）；历史 10 条落 `schema_meta` KV。
  ⚠️ `searchProvider` **必须 watch `dataEpochProvider`**，否则「刚记一笔 / 刚加账户后再搜搜不到」（老 bug，已修）。
- 视觉：**全站卡通浅色一套主题**（原型 `<PROTOTYPE_DIR>`；令牌 `Tok` 在 `lib/core/theme/tokens.dart`，
  通用件在 `toon.dart`；**禁止裸色值**）。**F7.6 已全部交付（`v0.7.6`）。**
- 版本：`v0.7.<N>` ↔ `F7.<N>`，一版一 tag；表在 `CHANGELOG.md` 顶部，回滚 `git checkout v0.7.13`。
- **✅ F7.15 自动记账 已交付（tag `v0.7.15`，已推远端；代码基线 = `e4e53b4`）**：
  Kotlin 只做「包名过滤 + 落盘 JSONL 队列 + 发通知」，**Dart 才落库**（drift 单写者）；Dart 在 `AppShell`
  首帧后 + 每次 `resumed` drain → 解析 → 复用 `importRows()` → 记批次 → 回执通知。**零迁移（DB 仍 v3）**、
  **零新依赖**。新增 `lib/features/autobook/`（Dart 9 文件）+ `android/.../autobook/`（Kotlin 5 文件）+ `/autobook` 路由
  + 首页提示条 + 「我的 → 自动记账」；SPEC `docs/spec/SPEC-F7.15-auto-bookkeeping.md`。
  **已含 2026-10-07 走查补丁**：新增**活性诊断**（`/autobook` 页「诊断」区块，跨进程落盘）+ 修 3 缺陷
  （① `drain` 取出即清空 → 加 `restore()` 回写重试；② 忽略规则误杀真实回执 → 拆 硬/软/强支付词三层；
  ③ 多金额取错 → 金额优先级重排）。
  **已含 2026-10-08 真机走查修复（Redmi K50）**：① 硬忽略收窄（支付宝付款标题「**交易提醒**」的 `提醒`
  与正文 `红包` 双双误杀 = 「能抓取但识别不了」的真根因）+ 软忽略扩容 + 强收支词补 `支出/收入/已收款/成功收款`；
  ② 组摘要去重（Kotlin `FLAG_GROUP_SUMMARY` + Dart `^\[\d+条\]` 兜底）；③ 金额「动作词之前」优先级；
  ④ 诊断层「瞒报」族（`capturedTotal` 11→0 / 空 drain 把 `drainedTotal` 8→0 / `skipped*` 不落盘 /
  `listenerConnected` 回填谎报「已绑定」）→ 改「盘上基线 + 本进程增量」合成；⑤ `last_run` 空 drain 覆盖（入账 7 秒后被抹）。
  ✅ **门禁已闭合（2026-10-08）**：用户终端全量 `flutter test` **479 passed / 0 skipped** → CHANGELOG 已转正
  `v0.7.15`（含 I 段）+ tag 已打并推远端（我的页角标在 `3ec2381` 就已置 `v0.7.15`，无需再改）。
  ✅ **真机已验**：断点① 系统绑定 / ② 服务收通知（非白名单探针 → `skippedNotWatched` 0→1）/ ③ Dart 取队列 /
  ④ 解析入账（`imported:6 dropped:2` 逐条吻合）+ **用户实付支付宝 ¥0.01 → `cents=1 / expense / notify_alipay`**；
  真实文案已固化为 `test/features/autobook/auto_book_real_samples_test.dart`（16 例）。
  ⚠️ **现场教训**：MIUI/HyperOS 在 `force-stop` 后**解绑**监听服务，而设置与 `dumpsys` 都显示「已授权」；
  **重绑会把仍在通知栏的活跃通知重投**（实测延迟 1 分 37 秒）→ `/autobook` 页那条「关掉再打开一次」的提示**真能救回数据**。
- **F7.14 新手引导 已交付 ✅（`v0.7.14`）**：7 页全屏导览（底栏中央方块 / 首页三图标 / 翻月 +
  预算铅笔 / 三个隐藏手势 / 资产页与报表页）；「我的 → 新手引导」可随时重看；**老用户不弹**
  （判定 = 无标记 **且** `ActiveBookIdController.isFreshInstall`）。新增 `lib/features/onboarding/` 5 文件。
- **下一步**：**F7 阶段 16 个版本全部交付并已打 tag，无未收口批次**；等用户排新需求。
- 📦 **release 已可下载**：`https://github.com/Xander-299/yanxin-bookkeeping-flutter/releases/tag/v0.7.16`
  （通用包 64 MB / arm64 包 22 MB，正式签名）；发布工具 `tool/publish_release.py`。
  ⚠️ 若将来要做「绕过微信/支付宝的支付渠道」单独记账，**必须先做跨应用去重**（见 CHANGELOG `v0.7.16` D 段）。
  F7.9 + 启动图标 + F7.14 新手引导 + F7.15 自动记账 + F7.16 三段**均已落地，别重写**。
- 📌 **2026-10-17（今天）只做了文档，功能代码 8 天零改动**：
  README 三连更（均只改 `README.md`，已推 GitHub）：`4480fc0` 补 F7.7–F7.16 进度/目录结构/
  Dart 工具链兜底/自动记账章节 · `5e8ab51` 版本号三来源 + 状态核对日期 ·
  **`82767d9` 「项目简介（简历可用）」章节**（用户要拿本项目写简历）。
  ⚠️ **简历章节的数字要与事实同步**：Dart 98 文件/25,361 行 · Kotlin 8 文件/1,507 行 ·
  52 测试文件 · 485 用例（**静态计数**，另有 18 处数据驱动循环展开，全量实跑更高）·
  135 提交 · 15 tag · 2026-09-09→10-17 约 6 周。
- ⚠️ **网络坑（2026-10-17 实测）**：`git fetch` 报 *"Please make sure you have the correct access rights,
  and the repository exists."* **是瞬时故障，不是凭证问题** —— 判据：`ssh -T git@github.com` 返回
  `Hi Xander-299!` 即凭证与 22 端口都通，**重试即好**。
  远端是 **SSH**（`git@github.com:`）→ **不吃 `http_proxy`**；`curl https://github.com` 会 15s 超时
  （沙箱出口限制）但 **SSH 通** → **别用 curl 判 git 可达性**。
