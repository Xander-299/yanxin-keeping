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

### 3.5 忽略规则（✅ 已签字 2026-09-30；**2026-10-08 按真机文案修订**）

> **历史**：签字稿是「单层忽略表 + 保留词」。2026-10-07 起拆成 **硬忽略 / 软忽略 / 强收支词** 三层
> （见 §8 走查补丁）；**2026-10-08 拿到真机原文后再度收窄硬忽略表**（见 §8「真机走查与修复」）——
> **实施以代码 + §8 为准**，下表为最新口径。

| 判定 | 关键词（包含匹配） |
|---|---|
| **硬忽略**（一票否决） | `转账` · `退款` · `已退款` · `充值成功` · `验证码` · `月账单` · `账单汇总` · `还款` |
| **软忽略**（命中且**无强收支词**才丢） | `优惠` · `立减` · `满减` · `活动` · `红包` · `提醒` · `领取` · `积分` · `即将` |
| **强收支词**（可救回软忽略命中） | `支付成功` · `付款成功` · `已支付` · `扣款` · `消费` · `支出` · `收入` · `已收款` · `成功收款` · `收款到账` · `到账` |
| 冲突时 | **硬忽略优先**；软忽略只在「正文无强收支词」时丢弃（宁可多记一笔可撤销，**不要静默漏记**） |

⚠️ **为什么营销词不能进硬忽略表**：支付宝付款通知**标题就叫「交易提醒」**、正文常带「红包」——
放进硬忽略会**静默**丢掉真实回执（= 2026-10-08 真机定位到的根因：「能抓取但识别不了」）。

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

### 真机走查与修复（2026-10-08 · Redmi K50 · 用户报「能抓取但无法识别」）

#### 真根因（真机文案钉死）

`adb shell dumpsys notification --noredact` + `run-as` 读 App 私有队列，拿到**真实**文案：

```json
{"pkg":"com.eg.android.AlipayGphone","title":"交易提醒",
 "text":"你有一笔0.01元的支出，领1元生活缴费红包。"}
```

**标题撞硬忽略 `提醒`、正文撞硬忽略 `红包`** → 两处一票否决 → 静默丢弃 → **支付宝付款一笔都记不上**。
（上一轮 §3.5 的忽略表是对着**推测**文案写的；本轮拿到真机文案例证 —— 这就是「能抓取、识别不了」的原文现场。）

#### 本轮修复

| # | 级别 | 缺陷 | 修法 |
|---|---|---|---|
| 1 | **P0** | 硬忽略表含营销词 / 回执常见词 → 真实付款被**静默**丢弃 | 硬忽略**收窄**为「必然非消费」（`转账 / 退款 / 已退款 / 充值成功 / 验证码 / 月账单 / 账单汇总 / **还款**`）；`提醒 / 红包 / 优惠 / 立减 / 满减 / 活动 / 领取 / 积分 / 即将` **降级为软忽略**（无强收支词才丢）；强收支词补 `支出 / 收入 / 已收款 / 成功收款` |
| 2 | **P1** | MIUI 组摘要 `[2条]微信支付: 已支付¥0.01` 与子通知文案不同 → 指纹不同 → **同一笔记两遍** | Kotlin 按 `FLAG_GROUP_SUMMARY` / `EXTRA_IS_GROUP_SUMMARY` 过滤（+计数 `skippedGroupSummary`）；Dart `^\[\d+条\]` 兜底（**标志非所有 ROM 都给，不能只靠 Kotlin**） |
| 3 | **P1** | 同条里营销语金额排在真实金额之前 → **取错数** | 新增「金额在动作词之前」优先级（`元 的? (支出\|消费\|收入\|付款\|支付\|收款)`），排在裸 `N 元` 之前 |
| 4 | **P1** | 诊断层「瞒报」：`capturedTotal` 11→0（persist 抹盘）/ 空 drain 把 `drainedTotal` 8→0（`noteDrained` 与它**共用 `== 0L` 守卫**被毒化）/ `skipped*` 从不落盘 / `listenerConnected` 回填→force-stop 后**谎报「已绑定」** | `AutoBookDiagnostics.kt` 重写为 **「盘上基线 + 本进程增量」** 合成（`recomputeTotals()` 幂等）；`listenerConnected` **故意不回填**；`snapshot()` 先 `load()` |
| 5 | **P2** | `last_run` 被空 drain 覆盖（真机实测入账 **7 秒后**变「没有新的支付通知」） | 空队列且无撤销时**不写** `last_run`；撤销是有效动作仍记 |

#### 真机验证结果

| 断点 | 手段 | 结果 |
|---|---|---|
| ① 系统绑定 | `cmd notification allow_listener` + `dumpsys activity services` | ✅ 已绑定 |
| ② 服务收通知 | 发**非白名单**探针通知 → `skippedNotWatched` | ✅ **0 → 1** |
| ③ Dart 取队列 | 注入队列行 → `lastDrainCount / drainedTotal` | ✅ 计数正确 |
| ④ 解析入账 | 8 条真实文案注入 → `last_run` | ✅ `imported:6 dropped:2` **逐条吻合** |
| ⑤ **真实支付端到端** | 用户实付支付宝 **¥0.01** | ✅ `cents=1 / type=expense / src=notify_alipay` |

**诊断修复的决定性验证**：同一个「空 drain → persist」组合（旧版必挂）下，`drainedTotal` 稳在 `1`（旧版会变 0）。

#### 现场发现（已写进页面提示口径）

**MIUI/HyperOS 在 `force-stop` 后会解绑 `NotificationListenerService`**，而 `settings get secure
enabled_notification_listeners` 与 `dumpsys` **都显示「已授权」** —— 即 §3.2 提过的「**系统开关 ≠ 服务活着**」。
**好消息**：重新绑定（设置里「通知使用权」关→开）会让系统把**仍在通知栏的活跃通知重投**一遍
（实测延迟 **1 分 37 秒**）→ `/autobook` 页那条「关掉再打开一次」的提示**真能救回数据**，不必重付一笔。
**代价**：`force-stop` / 覆盖安装后**必须重绑一次**（`adb shell cmd notification allow_listener <pkg>/<component>`）。

⚠️ **判读口径**：`lastCaptureAtMs` 是**捕获时刻**，通知自身 `postTimeMs` 才是**交易时刻**，重投场景两者可差几分钟
—— 别拿它们互相校验。

#### 门禁（✅ 2026-10-08 全闭合）

- analyze 等效 **全项目 `No issues found!`** ✅
- ✅ **用户终端全量 `flutter test` `479 passed / 0 skipped`**（2026-10-08；= `test()` **391** + `testWidgets` **88**；
  本批 **+79** 全落在 `test()`）
- 本机可跑部分：纯 `test()` **386 例全绿 / 0 失败**（分 4 批并行跑完 49 文件）；
  autobook 三文件 `rules` **47** + `flow` **15** + **新增** `real_samples` **16**（**文案逐字抄自真机**）
- 真机断点 **①–⑤** + **真实支付端到端** ✅

→ 已按「发布收尾四步」打 tag **`v0.7.15`** 并推远端（2026-10-08）。

### 待办（用户侧）

- [x] **✅ 真机装带诊断的新包 → 支付一笔 → 看 `/autobook` 页「诊断」区块**（2026-10-08 完成；
      诊断五行 + 断点定位表见 HANDOFF「未解决问题」第 7 条）
- [x] **✅ 真机抓真实通知文案**（`dumpsys notification --noredact`）→ 已回填规则表，
      并固化为 `test/features/autobook/auto_book_real_samples_test.dart`（16 例逐字抄自真机）
- [x] **✅ 模拟器可跑的部分**：用 `ACTION_SEND` 分享路径验完整链路（不受包名白名单限制）
- [x] **✅ 终端全量 `flutter test`**（2026-10-08 完成，**479 passed / 0 skipped**）
- [ ] 真机走查（尚未覆盖 · **非阻断项**）：权限引导三态（去开启 / 返回自检 / 通知权限被拒）、首页提示条、`/autobook` 页撤销
      —— 首页提示条与撤销已在模拟器 `ACTION_SEND` 通道验过，仅**权限引导三态**未在真机覆盖
- [x] **✅ 收尾四步**（2026-10-08 完成）：CHANGELOG `[Unreleased]` → `## [v0.7.15]`（含 I 段）+ tag 表补行
      → `git tag -a v0.7.15` → 直推核对（「我的」页角标早在 `3ec2381` 实现提交即置 `v0.7.15`，无需再改）

### F7.16 补抓（2026-10-08 深夜 · 用户报「通知栏里有支付消息，但均未被捕获」）

> ⚠️ 本轮**未打 tag**（`[Unreleased]`）—— F7.16 的「扩展监听应用清单」需求尚未落地，待其完成一并转 `v0.7.16`。
> 代码基线 **`d44f8c6`**。

**根因（暴露了 §3.1 未考虑的时序）**

`NotificationListenerService.onNotificationPosted` 是**推送式回调**：通知在服务**未连接期间**发布时，
系统**不会在服务连上后补发** → **永久丢失**。§3.1 只设计了「服务在工作时」的链路，
**没回答「服务不在时的事件去哪了」**。

真机现场（Redmi K50）：支付宝付款通知 `交易提醒 / 你有一笔3.00元的支出，点击领3元电费红包。`
发布于 **22:29:37**，而 `lastConnectedAtMs` = **22:49:40**（晚 20 分 3 秒）；旁证 `lastCaptureAtMs`
停在 **17:52:33**、`capturedTotal` 恒为 **2**，而 `skippedNotWatched=226` 说明服务此前确实工作过
—— 即「**服务活着，但那段时间没连上**」。

> ⚠️ 用户最初的判断是「能抓取但无法识别（关键词识别问题）」—— **本轮证明不是**：通知根本没到达服务，
> 解析规则无从谈起。（关键词问题见上一节「真机走查与修复」。）

**修复（5 项）**

1. **补抓（catch-up）** —— `AutoBookListenerService.catchUp(reason)`：`getActiveNotifications()` 扫通知栏
   **现存**通知，逐条走与实时回调**同一条**判定链（抽 `handle(sbn, fromCatchUp)`，两处各写一遍必然漂移）。
   过滤：**24h 内**（更早的多半是过期营销）/ 白名单 / 非组摘要 / 去重。触发点两个：
   ① `onListenerConnected()`（服务刚被系统绑上）；② Dart 每次 `drainQueue()` **之前**（新通道方法 `catchUp`）
   —— **顺序不可颠倒**，否则刚补入队的条目要等下一轮。
2. **`AutoBookSeen`（新文件）** —— 持久化「已入队指纹集」`pkg|title|text|postTimeMs`（cap 200，
   `filesDir/autobook_seen.json`）。**为什么必须**：补抓会反复看到同一条仍在栏里的通知，而队列是
   「取走即清空」→ 不做持久去重就会**每次回前台重复入队**，Dart 记「重复 N 条」→ 把「上次检查：
   新入账 N 笔」盖掉。**指纹必须带 `postTimeMs`** —— 只按文案去重会漏记「已支付¥1.00」这种同文案多笔。
3. **`AutoBookQueue.enqueueNotification` 加 `fromCatchUp`** —— 补抓走持久指纹、实时走既有 5 秒窗口，
   最后**共用同一份 `AutoBookSeen`** 兜底（同一条通知经两条路径到达也只入队一次）。
4. **可观测性** —— `Decision` 枚举（`NOT_WATCHED / EMPTY / GROUP_SUMMARY / DEDUP / CAPTURED`）逐层 `Log`
   （`TAG=AutoBookListener`；`NOT_WATCHED` 不打，否则日志被淹）；诊断新增
   `lastCatchUpAtMs / lastCatchUpActive / lastCatchUpAdded / catchUpTotal / catchUpAddedTotal`
   且**必然落盘**（此前 `noteSkippedDedup` 刻意不落盘 → 「回调没来」与「来了被去重丢掉」在文件上
   **完全不可区分**，无法判因）。
5. **Dart 侧** —— `AutoBookBridge.catchUp()` + `AutoBookController._drain()` 在取队列**之前**插入补抓步骤
   + `AutoBookDrainResult.caughtUp`。

**真机验证（Redmi K50 · 通过 ✅）**

| 步骤 | 观测 |
|---|---|
| 重绑监听（见下方「⭐ 修正」） | `Live notification listeners` 出现本服务（live=1 / services 命中 8） |
| `onListenerConnected` → `catchUp("connect")` | `lastCatchUpActive=87`（扫到 87 条活动通知）、`lastCatchUpAdded=2` |
| 队列 | 补入 2 条：**支付宝 `交易提醒` / `你有一笔3.00元的支出…`** ✅ + 支付宝营销广告 1 条 |
| App 回前台 drain | 队列清空、`drainedTotal` 3 → **5**、`skippedDedup` 0 → **10** |
| 数据库 | **165 → 166**，`notify_alipay` 5 → **6**；新增 `cents=300 / expense / notify_alipay /` **`occurred_at=22:29:37`** |
| 去重 | `catchUpTotal=6` 而 `catchUpAddedTotal` 恒为 **2** → **反复补抓零重复入队** ✅ |

解析顺带复核：支付宝那条同时命中软忽略 `红包`/`提醒`，但含强支付词 `支出` → 正确放行；
金额取规则② `3.00元的支出` = **300 分**（**没被营销尾巴「领3元电费红包」的 3 元抢走**）；
同批捞进的营销广告按 `direction == null` 被 Dart 侧丢弃 → **只 +1 不 +2** ✅。

**⚠️ 补抓的固有边界（走查时必须知道）**

- 只能捞「**此刻仍在通知栏里**」的通知 —— 已被系统 / 用户清掉的**补不回来**。真机：微信那条
  `已支付¥1.00` 验证时 `dumpsys notification | grep -c 已支付` 已为 **0** → 没补到（用户需手动补记）。
  **所以补抓是兜底，主防线仍是服务保持连接时的实时捕获。**
- `AutoBookNotifier.showPending`（「识别到 N 笔支付通知」）按**队列条数**弹，而 Kotlin 侧只做包名过滤
  → 补抓一次可能捞进多条非支付通知 → 数字偏高。属**既有行为**（实时路径同样如此），最终被 Dart 侧
  `showReceipt`（「已自动记账 N 笔」）覆盖为准确值。若要收紧，归入 F7.16「扩展清单」时一并设计预筛。

**⭐ 修正一个既有认知：重绑监听必须「先摘再挂」**

单独 `cmd notification allow_listener <pkg>/<component>` **不生效** —— 实测：setting 里有了、App 进程也在，
但 `dumpsys notification` 的 `Live notification listeners` 里**没有**本服务、`dumpsys activity services`
仍是 `(nothing)`。**系统不会因「新增一条授权」而绑定。**

正确序列：`disallow_listener` → `sleep 2` → `allow_listener` → 之后 live 计数 1、services 命中 8。

判定「到底绑上没」**只看 `Live notification listeners`**（`dumpsys notification` 的
`Allowed notification listeners` 段只反映 setting，不反映是否真连上）。

**构建链备忘**

`android/local.properties` 会被 flutter 工具改写（用户跑过 `flutter build apk --release` 后变成
`buildMode=release / versionCode=1`）→ 直接 `assembleDebug` 出的包 **versionCode=1**，而设备上是 **2001**
→ `install -r` 必撞 `INSTALL_FAILED_VERSION_DOWNGRADE`。**构建前先看这个文件**（不入版本控制）。

另：`aapt` 与 kernel 校验只覆盖 Dart 侧；**Kotlin 改动是否真进包，用 dex 二进制 grep 验**
（读 zip 里全部 `classes*.dex` 拼起来搜新类名/新方法名/新字符串常量）。

**门禁**：analyze 等效 **全项目 `No issues found!`** ✅；`auto_book_flow_test` **17 passed / 0 failed**
（15 → 17，+2：补抓入账回归守卫 + 补抓空转不覆盖「上次检查」）。
⚠️ **未跑全量 479** —— 本批 Dart 改动仅 autobook 内 3 个文件（`bridge` / `controller` / 其测试）。

---

## §9 · 第二起事故：「识别不到微信支付」= `[N条]` 折叠前缀被误判成组摘要（2026-10-08）

**症状**：通知栏里有支付宝 + 微信各一条支付消息，**一条都没被捕获**（用户报「识别不到微信支付」）。

**排查（先取证 → 再复现 → 再改，不先动代码）**

- 诊断快照给出**反直觉**的第一手事实：`lastCapturePkg=com.tencent.mm`、`capturedTotal` 在涨，
  且 `autobook_seen.json` 里**赫然有**
  `com.tencent.mm|微信支付|[3条]微信支付: 已支付¥0.03|1791473495452`
  → 微信那条**已经被捕获入队了**，问题在**捕获之后**。
- 队列已清空、`lastDrainCount=1`、DB 里 `notify_wechat` **仍是 7** → 丢在**解析 / 入账**这一段。
- Kotlin 日志 `catchUp(channel) 活动通知=87 补入队=1` @23:31:40 与 `lastCaptureAtMs` 完全吻合
  → 这条是靠**补抓**进来的（§8 的修复已生效），实时回调当时**没到**。

**根因**：`auto_book_rules.dart` 的组摘要兜底 `^\[\d+条\]` 把正文
`[3条]微信支付: 已支付¥0.03` 判成「组摘要」→ `parseNotification` 返回 null → **静默丢弃**。

**推翻旧判据的取证**（`dumpsys notification --noredact`）：

| 证据 | 值 | 含义 |
|---|---|---|
| `Group summaries:` 段 | **无 `com.tencent.mm`** | NMS 没登记它是组摘要 |
| `flags` | `0x11`（无 `FLAG_GROUP_SUMMARY=0x200`） | 系统标志否定 |
| `groupKey` | `0\|com.tencent.mm\|-656511598\|…`（**= 自己的 key**） | 未进任何分组 |
| `tickerText` | `微信支付: 已支付¥0.03`（**无前缀**） | 前缀是**显示层**加的，不是原文 |

**修法**：Dart 侧把「丢弃」改成「**归一化**」—— 剥掉 `^\s*\[\d+条\]\s*` 再解析，
`combined` / `externalId` 都用归一化后的正文；组摘要判定**只保留 Kotlin 的系统标志这一处**。
Kotlin 侧另补：判定链整体**兜异常 + 打日志**（此前抛出去被系统吞掉，外部只看到「什么都没发生」）。

**验证**（真机 Redmi K50 · 端到端）：把真机原文注入落盘队列 → 回前台 drain →
DB **167 → 168**、`notify_wechat` **7 → 8**，新增记录
`cents=3 / expense / occurred_at=2026-10-08 23:31:35`（= 通知真实发布时刻）。

**门禁**：analyze 等效 `No issues found!` ✅；autobook 三个测试文件 **82 passed / 0 failed**
（`flow` 17 / `real_samples` **18** / `rules` 47）。⚠️ 未跑全量 —— 但 `real_samples` 本次被**反转**
（原「`[N条]` 必须丢弃」3 条 → 「必须入账」回归守卫），它正是这次判断错误的载体。

**教训（写给下一次）**

- **判据要有唯一权威来源**：同一件事（「这是不是组摘要」）在两个层各写一套判据、且**宽的那套在下游**，
  就必然出现「上游放行 → 下游丢弃」的**静默漏记**。本次即是 Kotlin 用系统标志判对、Dart 用文本正则判错。
- **`skippedGroupSummary` 涨了 ≠ 丢得对**：计数只说明「丢了」，不说明「该丢」。
  这次靠**逐条比对真实通知与系统登记表（`Group summaries:`）**才推翻它 ——
  诊断计数只能定位「哪一层丢的」，**不能替你做价值判断**。
- **兜底规则的注释必须写清「它想防的具体场景」**，否则后人无从判断它是否仍成立
  （`e4e53b4` 把两笔不同交易记成了「摘要 + 子通知」）。
