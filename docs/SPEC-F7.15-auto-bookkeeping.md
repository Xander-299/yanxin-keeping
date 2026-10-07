# SPEC — F7.15 自动记账（通知使用权为主 · 零权限兜底）

> **状态：✅ 已签字（2026-09-30）** —— 用户裁定 **设计乙 = 静默入账 + 通知栏回执（`撤销` / `查看`）**；
> §3.5 忽略规则默认值按本 SPEC 采用。四项基础裁定见 §7。
> **版本**：交付后打 tag **`v0.7.15`**（沿用递增；最新已占用 `v0.7.14`）。
> **前置**：F7.14 新手引导已交付（`v0.7.14`，400 全绿 + 走查 D1–D10 全过）。
> **不动 schema**（DB 保持 **schemaVersion = 3**）· **零新依赖**（Kotlin 原生 + 手写 JSON）。

---

## 1. 要解决的问题

现在记账只有两条路：**手动一笔笔敲**，或**事后导出账单文件再导入**。两条都要求用户「想起来去做」。

而真实支付场景里，微信 / 支付宝**付款后本来就会推一条通知**（金额明明白白写在里面）。这条件在
代码里其实早就被预留过：

| 已有资产 | 原文 |
|---|---|
| `transactions.source` 注释 | `manual\|wechat_csv\|alipay_csv\|`**`notification`**`\|`**`shortcut`** —— 枚举已含自动记账来源 |
| `core/utils/fingerprint.dart` 文件头 | 「入账指纹计算（**防自动记账重复入账**）」 |
| `transaction_repository.dart:5` | 「提供统一入账入口 `importTransaction` **供自动记账调用**」 |
| `importRows()` | 单事务 + 分批预查重 + 文件内去重 —— 完整的批量入账编排 |
| `categorizeRow()` | 39 条有序正则（喂 `商户名 + 商品名`）→ 可复用为自动分类 |

**唯一缺口**：`MainActivity.kt` 仍是 13 行脚手架空实现 —— 通知监听**必须由 Kotlin 原生服务承担**，
这是本项目**第一个平台通道**。

---

## 2. 目标（DoD）

| # | 可验收行为 |
|---|---|
| D1 | 「我的」页新增可点条目「自动记账」→ 全屏页 `/autobook`，显示**当前权限状态**（已开启 / 未开启） |
| D2 | 未开启时点「去开启」→ 跳到系统「通知使用权」设置页；**从设置返回后自动刷新状态**（无需手动刷新） |
| D3 | 已开启后，微信 / 支付宝的支付通知被捕获 → 解析出金额与收支方向 → **静默入账**（归到「微信」/「支付宝」账户） |
| D4 | 入账后首页顶部出现提示条「已自动记账 **N** 笔 · 查看」，**点「×」可一键撤销本批**（软删） |
| D4b | （设计乙）入账后同时发一条**回执通知**：正文「已自动记账 N 笔 · 合计 ¥X」，按钮 **`撤销`** / **`查看`**（均在展开态底部，非右侧）；点「撤销」→ 拉起 App 并软删本批 + 通知消失；点「查看」→ 打开 App |
| D5 | 同一笔通知被捕获两次（通知更新重发 / 队列重复 drain）→ **指纹去重，零重复入账** |
| D6 | App 进程被杀期间捕获的通知**不丢**：队列落盘，下次启动或从后台恢复时补记 |
| D7 | 未开启权限时**不产生任何后台行为**，页面文案明确「未开启」，不假装在工作 |
| D8 | 转账 / 退款 / 红包 / 优惠 / 充值 / 验证码等**非消费通知不误记**（§3.5 规则表） |
| D9 | 零权限兜底：从微信 / 支付宝「分享」一条文本到颜芯记账 → 走同一条解析与入账链路 |
| D10 | 视觉 100% 走 `Tok.*` 令牌 + 现成 `Toon*` 件，**无裸色值**；不新增主题令牌 |
| D11 | 既有 400 个用例行为不变；新代码不改变 `importRows` / `categorizeRow` / `fingerprint` 的既有语义 |

---

## 3. 交互与实现规格

### 3.1 架构：Kotlin 落盘队列 + Dart 消费（**关键决策**）

```
[微信/支付宝 App] 发通知
        ↓
NotificationListenerService（Kotlin，App 进程）
  · 包名白名单过滤 → 取 title/text/bigText/subText/postTime
  · 5 秒窗口粗筛去重（同 pkg+title+text）
  · append 到 filesDir/autobook_queue.jsonl          ← 落盘，不依赖 Dart
        ↓
Dart 在「App 首帧后」与「生命周期 resumed」时 drain
        ↓
autobook_rules.parseNotification() → ParsedRow
        ↓
按 source 分组 → 复用 importRows()（每组一次事务）
        ↓
指纹去重（ADR-7 唯一索引）→ dataEpochProvider.bump()
        ↓
首页提示条（会话内）+ 回执通知（channel 回调 Kotlin，§3.7 设计乙）
```

**为什么不让 Kotlin 直接写库**：drift 是唯一 DB writer，第二个写入方会破坏「单写者 + 迁移版本一致」假设。
**为什么不启 headless FlutterEngine**：`FlutterEngineGroup` 后台实例成本高、崩溃面大、无法在本机门禁覆盖
（本项目本机跑不了 widget 测试），而「入账延迟到下次打开 App」在这个功能形态下**几乎无感** ——
用户本来就要打开 App 才看得到提示条。

**队列纪律**：JSONL 追加写；上限 **500 条 / 保留 7 天**（超出按时间裁撤）；drain 成功后**整文件清空**；
单条解析失败或入账失败 → **丢弃该条并计数**，不重试（防止坏数据卡住队列）。

### 3.2 权限（本批**首次**在 manifest 引入权限声明）

| 用途 | 声明方式 | 用户动作 |
|---|---|---|
| 通知监听 | `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`，写在 `<service>` 的 `android:permission` 属性上（**不是** `uses-permission`） | 设置 → 通知 → 通知使用权 → 打开 |
| 回执通知（设计乙） | `android.permission.POST_NOTIFICATIONS`（`uses-permission`，**Android 13+ 运行时权限**） | 首次进入 `/autobook` 页时弹窗，或系统设置里手动开 |
| 分享接收 | `<intent-filter>` 里加 `ACTION_SEND` + `text/plain` | 无需授权（通用分享能力） |

- **必须申请 `POST_NOTIFICATIONS`**：设计乙要发回执通知（Android 13+ 不发就静默丢弃，`IMPORTANCE_LOW` 也不例外）。
  权限被拒时**功能仍然工作**（入账照常，只是没有通知回执），走查要覆盖这一态。
- **不加** 前台服务：`NotificationListenerService` 由系统绑定，不需要 FGS（省掉 Android 14 的 FGS 类型申报）。
- 状态自检**不用 `NotificationManagerCompat`**（避免为此新增 androidx 依赖）：
  `Settings.Secure.getString(cr, "enabled_notification_listeners")` 字符串里包含本包 `ComponentName`
  → API 19+ 通用，无需版本分支。
- 通知权限状态自检：`NotificationManager.areNotificationsEnabled()`（API 24+）+ `checkSelfPermission`（API 33+）。
- 引导页文案必须**写清「为什么要这个权限」+「数据只落本地、不上传」**（本 App 无 `INTERNET` 权限，
  这是真实卖点，不是话术）。
- **降级策略**：本 App 若跑在非 Android 平台（含 widget 测试），MethodChannel 调用会抛
  `MissingPluginException` → 全部捕获后按「不支持」处理，**不阻断冷启动、不报错**。

### 3.3 账户归属（用户裁定：按来源自动建账户）

- `ensureSourceAccount(bookId, source)` —— 照抄既有 `ensureImportAccount` 的写法（先查同名、无则创建）：
  - `notify_wechat` → 账户名「微信」，`type = 'other'`
  - `notify_alipay` → 账户名「支付宝」，`type = 'other'`
  - `share` → 复用既有「导入账户」的语义，新建名为「分享记账」的账户
- **不新增列**：`source` 是 `TEXT`（无 CHECK 约束）→ 取值域从 `notification` 细化为
  `notify_wechat` / `notify_alipay` / `share`，**零迁移**。这是本批唯一「约定变更」，写回 PRD §2 术语表。

### 3.4 解析规则（`auto_book_rules.dart`，纯函数，全部可单测）

输入 `RawNotification { pkg, title, text, bigText, subText, postTimeMs }`，输出 `ParsedRow?`（null = 丢弃）。
三层顺序：**① 包名白名单 → ② 忽略规则 → ③ 模板规则（先命中先赢）**。

模板结构（**具体文案在实现时按真机抓取填充**，此处只锁结构）：

| 层 | 作用 | 说明 |
|---|---|---|
| 金额提取 | 多级降级：`(¥)?(\d+(?:\.\d{1,2})?)\s*元` → `¥\s*(\d+(?:\.\d{1,2})?)` → `(\d+\.\d{2})` | 全程 `yuanToCents` 字符串转分，**禁止浮点**（沿用导入链路铁律） |
| 方向判定 | 含「到账 / 收款 / 收款成功」→ `income`；含「支付成功 / 付款 / 扣款 / 消费」→ `expense` | 两个都不含 → 丢弃 |
| 商户提取 | 尝试取「向 X 付款」「收款方：X」等模式 | **多数通知不含商户名 → 允许为空**（§6 风险） |
| 时间 | 取通知 `postTime`（非解析文案） | 时区 = 本地 |
| externalId | `sha1(pkg + title + text + postTime/1000)` | 供指纹使用；不用系统通知 id（不稳定） |

**分享入口（D9 兜底）复用同一套规则**：`parseSharedText(String text)` 用 `source = 'share'` 走
「② 忽略 → ③ 模板」两层（**跳过包名白名单**），`externalId = sha1('share' + text + 秒级时间)`。
分享来的文本没有 `postTime`，用「入队时刻」当发生时间 —— 语义是「你分享时刚看到这条账单」。

**5 秒窗口粗筛在 Kotlin 侧**（同 pkg + title + text 5 秒内只留首条），Dart 侧不重复做；
Dart 侧只靠指纹（ADR-7 唯一索引）兜底，两层互不依赖。

### 3.5 忽略规则（默认值，✅ 已签字 2026-09-30）

| 判定 | 关键词（包含匹配） |
|---|---|
| **忽略**（非消费，默认） | `转账`（微信转账给人，属转账非消费）· `红包` · `退款` · `已退款` · `优惠` · `立减` · `满减` · `充值成功` · `验证码` · `月账单` · `账单汇总` · `活动` · `领取` · `积分` · `即将` · `提醒` |
| **保留** | `支付成功` · `付款成功` · `已支付` · `扣款` · `消费` · `收款到账` · `到账` |
| 冲突时 | **忽略规则优先于模板规则**（先过忽略层，命中即丢） |

规则表结构照抄 `category_rules.dart` 的既有写法（有序 `List<Rule>` + 先命中先赢），**不另发明 DSL**。

### 3.6 提示条与撤销（用户裁定：静默直入 + 可撤销提示条）

- `autoBookNoticeProvider` 持有**本次会话**的入账批次（txIds + 笔数 + 合计分 + 时间戳），
  首页顶部提示条的显示/隐藏只看它 —— **不跨启动**。
- 位置：首页 `MonthHero` **上方**；无批次时**完全不占位**（不渲染占位高度）。
- 文案：`已自动记账 N 笔 · 查看` + 右侧 `×`（撤销）。
- 「查看」→ 跳到本批最早一笔所在月份（复用既有 `jumpToMonth`）；「×」→ 二次确认后**软删本批 txIds**。
- 撤销走 `TransactionRepository` 既有软删接口 + `dataEpochProvider.bump()`，**不新增删除路径**。

**批次持久化（设计乙新增，零迁移）**：通知栏「撤销」可能在**冷启动**后点击（进程已杀），
那时会话内 provider 是空的 → 把**最近 3 个批次**的 `{batchId, txIds, count, totalCents, atMs}` 写进
**既有 `schema_meta` KV 表**（键 `autobook_batches`，JSON 数组，整体覆盖写）。
- 复用 `AppMetaRepository`（与 `search_history` / `onboarding_done` 同表）→ **不动 schema（仍 v3）**。
- 该表只有 `key` / `value` 两列，**不能再加列**；批次数组上限 3（超出按时间裁撤最旧）。
- 提示条仍只看会话内 state；KV 只服务「通知按钮 → 冷启动撤销」这一条路径。
- 撤销成功后立刻把该批次从数组里摘掉（否则同一批能被撤两次 → 第二次静默失败）。

### 3.7 通知栏回执（设计乙 ✅ 已签字 2026-09-30）

**用户设想**（2026-09-30 追加）：捕获后发一条系统通知，正文提示「记录了几条账单」，点通知进 App 看详情，
通知上有两个按钮。**裁定 = 设计乙**：入账仍**静默直入**，通知是「**已记账**」回执，按钮 `撤销` / `查看`。

**能做到的** ✅：`Notification.Builder` + `setContentIntent`（点通知进 App）+ `addAction`（两个按钮）
+ `setStyle(InboxStyle)`（展开列明细）+ `setNumber`（合并计数）—— 全部标准 API，无需 hack。

**⚠️ 三处硬约束（「右侧两个按钮」的设想据此调整）**：

| # | 约束 | 依据 / 后果 |
|---|---|---|
| 1 | **按钮不能放「右侧」** —— 位置由系统模板决定 | 标准模板：折叠态**不显示**按钮，展开态按钮**固定在内容区底部成排**（见示意图）。Android 12+ 连「自绘整个通知布局」都被禁：`setCustomContentView` 不再占用完整通知区域，系统套标准模板，**折叠态自定义内容高度上限从 106dp 降到 48dp**，横向空间也变小 → 自绘放右侧这条路已封死 |
| 2 | **「撤销」按钮点下去必须拉起 App** | 落库只能由 Dart 侧做（drift 是唯一 writer，见 §3.1）。`PendingIntent` 必须**直接指向 Activity** —— Android 12 起**禁止通知 trampoline**（BroadcastReceiver / Service 里再 `startActivity` 会报 `Indirect notification activity start` 并被拦） |
| 3 | **必须新增 `POST_NOTIFICATIONS`（Android 13+ 运行时权限）** | 见 §3.2。被拒时降级为「只入账、无回执」，功能不残废（走查要覆盖这一态） |

**实现细节（已全部落进 §5 文件清单）**：

- **两态同一条通知**（固定 id 覆写，**不是每笔一条**，否则刷屏）：
  - ① 捕获时（Kotlin 侧）：`识别到 N 笔支付通知 · 打开即可记账` —— 让用户**在 App 外也知道在生效**。
  - ② 入账后（Dart 通过 channel 回调 Kotlin）：`已自动记账 N 笔 · 合计 ¥X` + action **`撤销`** / **`查看`**。
- **渠道重要性 = `IMPORTANCE_LOW`**：进通知栏但不发声、不弹 heads-up（弹屏会打断支付后的操作流）。
- **`PendingIntent` 必须带 `FLAG_IMMUTABLE`**（Android 12+ 不带任一 flag 直接抛 `IllegalArgumentException`）。
- **带 intent-filter 的组件必须显式声明 `android:exported`**（Android 12+ 否则**装不上**，logcat 明确报错）。
- **「撤销」的落点**：`PendingIntent.getActivity` → `MainActivity`，extra
  `autobook_action=undo` + `autobook_batch=<batchId>`。`MainActivity` 把它落成
  `filesDir/autobook_command.json`；Dart 下次 drain 时 `takeCommand()` 取走并清空
  → **冷启动也能撤销**（批次数据来自 §3.6 的 KV）。
- **「查看」的落点**：`PendingIntent.getActivity` → `MainActivity`（无 extra）= 打开 App。
- **用户划掉通知 = 只收起提示，不影响账**（账已入，撤销入口还有 `/autobook` 页的「最近一批」）。
- **App 内兜底**：`/autobook` 页常驻「最近一次自动记账 · N 笔 · 时间」+ 撤销按钮（**不依赖通知**）。
- 通知只在**真的有新增入账**时更新为 ② 态；drain 后 0 新增（全是重复）→ 不发回执、把 ① 态 `cancel()`。

---

## 4. 不做

- ❌ **不做无障碍服务**（`AccessibilityService`）：会触发系统「可查看并控制屏幕」红色警告，国内商店审核需额外材料。
- ❌ **不做短信读取**（`READ_SMS` / `RECEIVE_SMS`）：Play 仅限默认短信 App，且银行卡短信多无商户名。
- ❌ **不做保活 / 前台服务 / 白名单自动引导**：只发一条 `IMPORTANCE_LOW` 回执通知，不做常驻服务。
  国产 ROM 杀后台属已知边界（`NotificationListenerService` 由系统绑定，被系统重启后自恢复）。
- ❌ **不做待确认收件箱**（设计甲被否）：入账照静默直入，纠错靠「提示条 / 通知 / `/autobook` 页」的撤销。
- ❌ **不做通知栏「导入 / 取消」**：写库必然拉起 App（§3.7 约束 2），按钮改为 `撤销` / `查看`。
- ❌ **不做 headless FlutterEngine**（§3.1）：接受「入账延迟到下次打开 App」。
- ❌ **不做批量改分类**：本批只提供「查看 / 撤销」，改分类走既有编辑页逐笔改（进 backlog）。
- ❌ **不做弹窗预填确认**（用户已裁定静默直入，不打断支付后的操作流）。
- ❌ 不做微信 / 支付宝以外的平台（银行 / 云闪付 / 美团 / 京东 / 抖音）→ **进 backlog**，规则表可扩展但本批不加。
- ❌ 不改 `importRows` / `categorizeRow` / `fingerprint` 的语义（`ImportReport` 只**追加**一个
  `importedIds` 字段，既有字段与返回值语义不变）；不新增 pub 依赖；不动 schema；不新增主题令牌。

---

## 5. 文件清单

| 文件 | 动作 |
|---|---|
| `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/AutoBookListenerService.kt` | **新增**：`NotificationListenerService` —— 包名白名单 → 取 title / text / bigText / subText / postTime → 5 秒粗筛 → 入队 → 更新「①捕获态」通知 |
| `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/AutoBookQueue.kt` | **新增**：JSONL 队列（追加 / 全量读 / 清空 / 500 条上限 / 7 天裁撤 / 5 秒窗口去重 / 分享文本入队）+ 命令文件（`autobook_command.json`） |
| `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/AutoBookNotifier.kt` | **新增**：渠道 `IMPORTANCE_LOW` + 两态通知（固定 id / `InboxStyle` / `setNumber` / `撤销`·`查看` action / `FLAG_IMMUTABLE`）+ `cancel()` |
| `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/AutoBookChannel.kt` | **新增**：`MethodChannel('yanxin/autobook')` —— `permissionStatus` / `notificationPermissionStatus` / `requestNotificationPermission` / `openNotificationSettings` / `drainQueue` / `takeCommand` / `showReceipt` / `cancelReceipt` |
| `android/app/src/main/kotlin/com/teacodeman/yanxin/MainActivity.kt` | **改**：注册 channel；`onCreate` / `onNewIntent` 处理 `ACTION_SEND` 文本（入队）与通知按钮 extra（落命令文件） |
| `android/app/src/main/AndroidManifest.xml` | **改**：`<uses-permission POST_NOTIFICATIONS>` + `<service>`（intent-filter + `android:exported` + `android:permission=BIND_NOTIFICATION_LISTENER_SERVICE`）+ `<activity>` 加 `ACTION_SEND` / `text/plain` filter。⚠️ **本批首次引入 manifest 权限 / 服务声明** |
| `lib/features/autobook/data/auto_book_rules.dart` | **新增**：包名白名单 + 忽略规则 + 模板规则 + `parseNotification()` / `parseSharedText()`（纯函数，全部可 `test()`） |
| `lib/features/autobook/data/auto_book_bridge.dart` | **新增**：MethodChannel 封装（drain / 权限状态 / 跳设置 / 回执通知 / 取命令），**方法可被子类覆写**（测试用假实现替换） |
| `lib/features/autobook/data/auto_book_batches.dart` | **新增**：批次记录读写（`schema_meta` KV `autobook_batches`，最近 3 批）+ JSON 编解码 |
| `lib/features/autobook/application/auto_book_accounts.dart` | **新增**：`ensureSourceAccount(bookId, source)` —— 照抄 `ensureImportAccount` 写法（**不改 `account_repository`**，保持仓储「无业务规则」定位） |
| `lib/features/autobook/application/auto_book_controller.dart` | **新增**：drain → 解析 → 按 source 分组 → `importRows()` → 记批次 → bump epoch → 回执通知 → 处理撤销命令 |
| `lib/features/autobook/application/auto_book_notice.dart` | **新增**：本批提示条状态（会话内）+ 撤销 |
| `lib/features/autobook/presentation/auto_book_page.dart` | **新增**：`/autobook` 页（权限状态 / 去开启 / 通知权限 / 最近一批撤销 / 平台与规则说明 / 隐私说明） |
| `lib/features/autobook/presentation/widgets/auto_book_banner.dart` | **新增**：首页顶部提示条 |
| `lib/features/import/application/bill_importer.dart` | **改**：`ImportReport` **追加** `importedIds`（默认 `const []`，既有字段语义不变） |
| `lib/app.dart` | **改**：新增 `GoRoute('/autobook')`（全屏） |
| `lib/features/nav/presentation/app_shell.dart` | **改**：首帧后 + `resumed` 触发 drain（**失败静默**，不得阻断冷启动） |
| `lib/features/ledger/presentation/home_page.dart` | **改**：`MonthHero` 上方插入 `AutoBookBanner` |
| `lib/features/profile/presentation/profile_page.dart` | **改**：新增条目「自动记账」 |
| `test/features/autobook/auto_book_rules_test.dart` | **新增**：纯 `test()` —— 白名单 / 忽略规则 / 金额多级降级 / 方向判定 / 空商户 / 微信·支付宝样本 / 分享文本 / 坏输入不抛异常 |
| `test/features/autobook/auto_book_flow_test.dart` | **新增**：`test()` —— 同批 drain 零重复 / 批次上限裁撤 / 撤销只软删本批 / 冷启动命令撤销 |

**不改**：DB schema（仍 v3）· `account_repository` · `categorizeRow` / `fingerprint` / `bill_*` 全部导入链路 ·
主题令牌 · `env.sh` · 既有 400 个用例。

---

## 6. 风险

| 风险 | 处置 |
|---|---|
| **通知多数不含商户名** → 自动分类大概率落「其他」 | **诚实暴露**：SPEC 写明这是已知局限；提示条是主要纠错入口；批量改分类进 backlog（§4） |
| 用户关掉微信/支付宝通知 → 完全收不到 | 页面文案说明依赖系统通知；兜底靠分享路径（D9）与账单导入（已有功能） |
| 通知文案随 App 版本变化 → 解析失配 | 规则表三层降级 + 全部纯函数单测；新样式只需加一条规则；失配时**丢弃而不误记** |
| **模拟器验不了真实通知格式**（MuMu 无真实微信/支付宝支付） | 走查用 `adb shell cmd notification post` 造合成通知，只验「解析 → 去重 → 入账 → 撤销」链路；**真实格式必须由用户在自己手机上实测回填**，走查报告须明确标注此边界 |
| 进程被杀 → 担心丢账 | 队列落盘（不依赖 Dart）；drain 在首帧后与 `resumed` 两处；指纹兜底重复入账 |
| 通知更新重发 → 重复入账 | 原生 5 秒窗口粗筛 + Dart 指纹（ADR-7 唯一索引）双层 |
| 队列无限膨胀 | 上限 500 条 / 保留 7 天 / drain 后清空 |
| **首次在 manifest 引入权限与服务声明** → 可能影响既有走查项 | 运行时权限只在用户主动点「开启通知」时申请；走查需回归确认冷启动、首启引导、分享面板不受影响 |
| `resumed` 触发 drain 拖慢前台切换 | drain 失败静默 + 全流程 try/catch；空队列时是一次文件存在性判断（<1ms） |
| Kotlin 侧代码**本机无法被门禁覆盖**（analyze/test 只覆盖 Dart） | Kotlin 逻辑**压到最薄**（只做过滤 + 落盘 + 通知，不做解析）；解析全在 Dart 侧可单测；Kotlin 用 APK 构建 + 真机走查覆盖 |
| 分享接收出现在所有 App 的分享面板 → 干扰 | `ACTION_SEND` + `text/plain` 是通用能力，同类 App 普遍如此；走查确认微信/支付宝分享面板行为 |
| **通知栏按钮位置与设想不一致** | 折叠态无按钮、展开态在底部（§3.7 图）；文案已按此调整。走查只能验「回执能发出 + 两个 action 能拉起 App」 |
| **「撤销」会拉起 App** | 写库必须回到 Dart（drift 单写者）；`PendingIntent.getActivity` 直达 Activity 才合规（Android 12 禁 trampoline）。通知文案需让用户预期到 |
| **通知权限被拒 / 通知被系统屏蔽 → 回执失效** | 入账不受影响；`/autobook` 页与首页提示条是**不依赖通知**的两条入口 |
| **回执通知刷屏** | 固定 id 覆写 + `setNumber` + `InboxStyle` 合并成一条；渠道 `IMPORTANCE_LOW` 不发声不弹屏 |
| **撤销重复点击 / 冷启动撤销找不到批次** | 批次写 `schema_meta` KV（最近 3 批，含 txIds）；撤销成功后立刻摘除；找不到 → 明确提示「这批已撤销或不复存在」 |
| **命令文件与队列文件的并发读写** | 写（Kotlin）与读（Dart）都在同一 App 进程 → 无跨进程竞争；drain 后整文件清空，不做部分重写 |

---

## 7. 签字

**2026-09-30 用户裁定（四项，全部确认）**：

1. **方案组合 = A 通知使用权（主）+ D3 分享接收（零权限兜底）+ 强化已有账单导入（校验补漏）**。
   不做无障碍（B）、不做短信（C）。
2. **入账方式 = 静默直入 + 首页顶部可撤销提示条**（不做待确认收件箱、不做无提示直入）。
3. **账户归属 = 按来源自动建账户**（「微信」/「支付宝」）。
4. **MVP 覆盖平台 = 仅微信 + 支付宝**（银行 / 云闪付 / 美团 / 京东 / 抖音 进 backlog）。

**同批确认的技术载体**：

- 通知监听用 **Kotlin 原生 `NotificationListenerService` + 落盘队列**，Dart 在首帧后 / `resumed` 消费
  （**不启 headless FlutterEngine**，接受「延迟到下次打开 App」）—— 见 §3.1。
- 入账链路**完全复用** `importRows()`（按 source 分组，每组一次事务），不新写入库逻辑。

**✅ 定稿（2026-09-30 用户签字）**：

- **§3.5 忽略规则默认值**：按本 SPEC 采用（转账 / 红包 / 退款 / 优惠 / 充值 / 验证码 / 账单 / 活动 / 积分
  全部忽略；「收款到账」「支付成功」保留；**忽略优先**）。签字时用户未提出要改的项。
- **§3.7 入账方式**：**设计乙 = 静默入账 + 通知栏回执**（正文「已自动记账 N 笔 · 合计 ¥X」+
  按钮 `撤销` / `查看`）→ 保持上面第 2 项「静默直入」。设计甲（通知栏「导入 / 取消」待确认收件箱）**否**。
- **约束确认**：按钮只能在展开态底部（非右侧）；`撤销` 必然会拉起 App；采用通知即**必须**申请
  `POST_NOTIFICATIONS`（§3.2）。

---

## 8. 实施记录

**2026-09-30 · 实现完成（🔵 待用户终端门禁 + 真机走查）**

### 落地清单（与 §5 的差异都注明了）

- **Android**：`autobook/AutoBookListenerService.kt`、`AutoBookQueue.kt`、`AutoBookNotifier.kt`、
  `AutoBookChannel.kt`、`MainActivity.kt`（改）、`AndroidManifest.xml`（改）、
  `res/drawable/ic_stat_autobook.xml`（**新增**：矢量单色通知小图标）。
- **Dart**：`autobook/` 8 个文件（rules / bridge / batches / accounts / controller / notice / page / banner）；
  `bill_importer.dart`（`ImportReport` 追加两个字段）；`app.dart`、`app_shell.dart`、`home_page.dart`、
  `profile_page.dart` 各一处接线。
- **与 §5 的两处差异**（都是实现时判定的，SPEC 正文已同步）：
  1. `ensureSourceAccount` **没进 `account_repository`**，改为独立文件
     `application/auto_book_accounts.dart` —— 仓储定位是「只做数据读写与字段校验，不含业务规则」，
     与既有 `ensureImportAccount` 放在 `bill_importer.dart` 的先例一致。
  2. `AutoBookActionReceiver.kt` **不需要**（设计乙的 `撤销` 也走 `PendingIntent.getActivity` 直达 Activity）
     → 用 `AutoBookQueue` 里的命令文件替代。
- **额外补的两处「不做就漏」**：
  - 通知权限状态自检 / 申请（Android 13+）—— 设计乙要发通知，这个必须有。
  - `/autobook` 页右上「检查一次」：手动 drain（**走查必需** —— 造完合成通知不用重启 App 也能看结果）。

### 实测（本机 A 机）

- **analyze 等效**（`tool/dart_analyze_fallback.py`）：**全项目 `No issues found!`** ✅
- **纯 `test()`**：本批新增 **47 例**（`auto_book_rules_test` 38 + `auto_book_flow_test` 9）**全绿** ✅
- **回归**：core 39 / data 25 / import 74 / assets 19 全绿 ✅
  - ⚠️ `test/data/repositories/transaction_repository_test.dart` 在本机 fallback runner 里
    **编译阶段就挂住（>150s 无输出）**，属环境问题（同款结构文件均正常），**未验证**，需终端复核。
- **APK**（`tool/build_kernel_fallback.py` + `gradlew assembleDebug -x compileFlutterBuildDebug`）：
  **BUILD SUCCESSFUL in 1m58s** ✅ —— `MainActivity` / 4 个 Kotlin 文件 / vector 资源**首次编译通过**。
- **APK 内核核验**（`tool/verify_apk_kernel.py notify_wechat 自动记账 yanxin/autobook`）：新鲜度一致 ✅ +
  三个新文案都命中 ✅。
- **合并清单核验**（`aapt2 dump xmltree`）：`POST_NOTIFICATIONS` ✅ · `ACTION_SEND` filter ✅ ·
  `com.teacodeman.yanxin.autobook.AutoBookListenerService` 带
  `BIND_NOTIFICATION_LISTENER_SERVICE` + `exported=false` + 正确 action ✅ —— 四条硬要求全部落进包里。

### ⚠️ 走查前必须知道的三件事（否则会误判）

1. **模拟器没有真实微信 / 支付宝支付** → 只能 `adb shell cmd notification post` 造合成通知。
   注意：`cmd notification post` **伪造不了 `packageName`**（发出来的是 `android`/shell 的包名），
   而包名白名单是第一层过滤 → 该方式**只能验通知本身能弹出**，验不了「被本 App 捕获」。
   要在模拟器上真正验链路，做法是**把白名单临时加上 `com.android.shell`**（本地实验，不入库）或用
   真机的真实支付通知。**结论：本机走查的覆盖上限是「Dart 侧链路（解析/去重/入账/撤销/回执）」，
   由 `auto_book_flow_test` 已覆盖；「监听是否生效」只能在用户手机上验。**
2. **debug 包会看到 `android.permission.INTERNET`** —— 那是 Flutter 模板在 `src/debug` + `src/profile`
   源集里的声明（热重载需要），**release 包没有**。所以 `/autobook` 页「本 App 没有申请网络权限」这句
   对交付版成立；走查若在 debug 包里核对权限列表，别把它当成矛盾。
3. **~~忽略规则里 `优惠` / `立减` / `满减` 有误杀风险~~ → ✅ 已修复（2026-10-07 走查补丁）**：
   原实现会丢弃「付款成功，优惠 0.5 元」这类**真实回执**（忽略优先于模板）。
   现已拆成硬忽略 + 软忽略，详见下方「走查补丁」。
   ⚠️ **这条后来被证实是用户反馈「后续通知都没被记录」的高度嫌疑点** —— 预警写对了，但没有可观测性去发现它。

### 走查补丁（2026-10-07 · 用户反馈「自动记账不生效，只成功过一次」）

用户实测现象：**只成功过一次，后续支付通知都没有被记录。**

#### 为什么这次反馈无法直接定位 —— 这个功能原来是「静默失败」的

四个断点，每一层都不给用户任何反馈，用户只能看到「没记上」，无从区分：

| 层 | 断点 | 原可见性 |
|---|---|---|
| ① 系统 → 服务 | 监听服务是否被系统绑定（国产 ROM 会解绑 / 限流） | **无**。页面上「通知使用权：已开启」查的是**系统开关**，不代表服务活着 |
| ② 服务 → 队列 | 包名白名单 / 空文案 / 5 秒粗筛去重 | **无** |
| ③ Dart 触发 | `AppShell` 首帧 + 每次 `resumed` 各 drain 一次 | **无** |
| ④ Dart 入账 | 解析 / 账本 / 写库 / 指纹判重 | **无** |

**所以本轮的第一交付不是修某个 bug，而是先把这条链路变成可诊断的。**

#### 本轮修复的四个缺陷

| # | 级别 | 缺陷 | 修法 |
|---|---|---|---|
| 1 | **P0** | **「取走即清空」丢账路径**：`AutoBookQueue.drain()` 是「读出 + 清空」，而 Dart 侧 `_drain()` 有三条 early return（账本未就绪 / 写库异常 / 处理中断）会让这批通知**永久消失** | 新增 `AutoBookQueue.restore()` + channel `restoreQueue`：Dart 在**临时性失败**时把原始行回写队列等下次重试；**解析不出的（永久性失败）仍丢弃**，否则会无限重试 |
| 2 | **P0** | **忽略规则误杀真实回执**（命中上方旧第 3 条的预警）：`优惠 / 立减 / 满减` 原在硬忽略表 → 「付款成功，优惠 0.50元」这类**真实消费被静默丢弃** | 拆表：硬忽略只留「必然非消费」词；新增 `kAutoBookSoftIgnoreKeywords`（营销词）+ `kAutoBookStrongPaymentKeywords`（支付回执词）。**软忽略词命中且无强支付词才丢** |
| 3 | **P1** | **多金额取错**（修 2 之后立刻暴露的新风险）：「订单金额 13.00元，优惠 1.00元，实付 12.00元」原实现取**第一个**数字 = 优惠金额 → **记错数比不记更糟** | 金额优先级重排：实付类 > 支付动作紧邻 > 货币符号 > 裸金额 |
| 4 | **P0** | **无任何可观测性** | 新增 `AutoBookDiagnostics`（Kotlin，关键事件跨进程落盘）+ channel `diagnostics`；`/autobook` 页新增「诊断」区块；「上次检查」结果落 `schema_meta` KV（`autobook_last_run`） |

#### 新增的「诊断」区块（用户能自己看出断在哪）

`/autobook` 页 → **诊断**：

| 行 | 含义 | 能判定的问题 |
|---|---|---|
| 监听服务 | 系统当前是否绑定着服务 | 「设置里开着但服务没绑定」= ROM 后台限制 |
| 最近捕获 | 最后一次抓到支付通知的时间 + 来源 | 「从未收到过」→ 抓取层或权限问题 |
| 待入账 | 原生队列里还没被消费的条数 | `> 0` → 抓到了但没触发入账 |
| 上次检查 | 上次 drain 的结果（入账 / 重复 / 丢弃 / 回写 / 错误） | 「全被丢弃」→ 解析规则不匹配 |
| 抓取统计 | 抓到 · 取走 · 非白名单 · 空文案 · 去重 | 各层过滤量 |
| 底部提示 | **按当前证据给一句可执行的话** | 直接告诉用户下一步做什么 |

#### 门禁（本机）

- **analyze 等效**：**全项目 `No issues found!`** ✅
- **纯 `test()`**：`auto_book_rules_test` **42 passed**（+4：软忽略 5 例、金额优先级 3 例，
  另有原有用例口径不变）· `auto_book_flow_test` **13 passed**（+4：回写不丢账 / 永久失败不回写 /
  lastRun 落 KV / 软忽略回归守卫）✅
- **APK**：见下方本轮构建结果（Kotlin 新增 `AutoBookDiagnostics`，必须真编一次）。

#### ⚠️ 仍未验证（不写清楚会导致二次误判）

- **真实微信 / 支付宝通知文案仍未采集**：模拟器没装这两个 App，`cmd notification post` 又伪造不了包名。
  **三处规则（忽略表 / 金额优先级 / 商户提取）目前仍是对着推测的真实文案写的。**
- 因此 `com.android.shell` 造的通知仅能验证「诊断能看见被白名单过滤」这一层；
  **完整链路（落盘 → drain → 解析 → 入账 → 撤销 → 回执）用 `ACTION_SEND` 分享路径验证**
  （分享路径**不受包名白名单限制**，是零权限兜底通道，可在模拟器上真跑）。

### 待办（用户侧）

- [ ] **🔴 最高优先：真机装带诊断的新包 → 做一笔支付 → 打开 App → 看 `/autobook` 页「诊断」区块**
      （监听服务 / 最近捕获 / 待入账 / 上次检查 / 抓取统计 + 底部提示），据此确认断在哪一层。
      若「监听服务：未绑定」→ ROM 后台限制；「最近捕获：从未」→ 抓取层；
      「待入账 > 0」→ 触发层；「上次检查：N 条不符合记账条件」→ 解析规则层。
- [ ] 终端全量 `flutter test`（本机跑不了 14 个 `testWidgets` 文件）
- [ ] 真机走查：权限引导（去开启 / 返回自检 / 通知权限被拒态）、首页提示条、`/autobook` 页撤销
- [ ] **真机抓真实通知文案**（`adb shell dumpsys notification --noredact`）→ 回填规则表：
      忽略表 / 金额优先级 / 商户提取三处目前仍是对着推测文案写的
- [ ] 模拟器可跑的部分：用 `ACTION_SEND` 分享路径验完整链路（不受包名白名单限制）
