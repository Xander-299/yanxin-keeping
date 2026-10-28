# SPEC（待签字）：颜芯记账 · 本地 AI 路线 —— 阶段零架构分析 + 阶段一文件级实施计划

> **状态**：阶段零交付物，**未签字、未写一行产品代码**。
> **依据 commit**：`58d59b8`（v0.7.17，schema v3，F1–F7.17 全部交付）
> **输入**：仓库根 `Prompt.md`（本地 AI 能力分阶段开发任务书）
> ⏸ **搁置声明（2026-10-28，用户裁定）**：本地 AI 路线（阶段二 M2「端上 llama.cpp 推理」
> 及后续阶段）**暂时搁置** —— 基准实测（`docs/dev/llm-benchmark.md`）表明 Qwen2.5-1.5B Q4_K_M
> 在目标机上首 token 3.5–5.1s、常驻 1.18GB，作为「措辞层」成本收益不成立。
> **不受影响、继续在线**：M1 关键词问答（已交付）、F8.1 截图记账（已交付）。
> 恢复时从 §4 / §10 续做；基准数据与复现工具保留在库。
>> **一句话结论**：现有项目里**已经有一条"文本 → 待确认账单 → 现有业务入账"的成熟管线**
> （自动记账 `parseNotification → ParsedRow → importRows`），阶段一的正确做法是
> **在这条管线前面加一层"图片 → 文本"**，而不是新造一条记账链路。
> 阶段一**不需要动数据库**（schema 保持 v3）、**不需要给 release 包加网络权限**。

---

## 0. 本文档与 Prompt 的对应关系

| Prompt §阶段零 要求 | 章节 |
|---|---|
| 1 当前项目架构说明 | §1.1 / §1.2 |
| 2 现有记账数据流和关键业务入口 | §1.5 / §1.6 |
| 3 可以直接复用的代码和服务 | §1.4 / §1.7 |
| 4 推荐新增的模块、文件及依赖 | §3.4 / §3.5 |
| 5 Android 本地 OCR 和本地 LLM 的集成方案 | §3.2 / §4 |
| 6 技术风险、设备兼容性、性能瓶颈 | §5 |
| 7 分阶段实施计划和验收标准 | §6 |
| 「判断如何以最小改动实现第一阶段」 | §3 |
| 「有问题先问我」 | §7（六个待拍板项 D1–D6） |

---

## 1. 现状盘点（全部来自真实代码，非推测）

### 1.1 技术栈与规模（实测）

| 项 | 值 |
|---|---|
| Flutter / Dart | **3.47.2 / 3.13.2**（`D:\Download\Flutter\flutter`，本机实测） |
| 状态管理 | `flutter_riverpod ^3.4.3`（`Notifier` / `AsyncNotifier`，无 codegen） |
| 路由 | `go_router ^18.0.1`（`StatefulShellRoute.indexedStack` + 全屏页，实例在 `App` 的 State 里） |
| 数据库 | `drift 2.31.0` + `sqlite3 2.9.4` + `drift_flutter 0.2.8`，**schemaVersion = 3** |
| 其他依赖 | `archive` / `crypto 3.0.7` / `gbk_codec` / `uuid ^4.6.0` / `file_picker ^12.2.0` / `path` |
| 网络依赖 | **无**（无 `http` / `dio` / `web_socket_channel`）；`lib/` 里网络代码 0 处 |
| Android | `compileSdk/targetSdk 36`（Flutter 默认）· `minSdk 24` · `ndk 28.2.13676358` · **AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0** · JDK 17 |
| 平台代码 | `MainActivity.kt` + `autobook/` 7 个 Kotlin 文件（通知监听 + JSONL 落盘 + MethodChannel `yanxin/autobook`） |
| 规模化 | `lib/` 128 个 `.dart` · `test/` 57 个 `.dart` · `docs/spec/` 14 份 SPEC · CI = analyze + test |
| release 权限 | **只有** `POST_NOTIFICATIONS` + `RECEIVE_BOOT_COMPLETED`；`INTERNET` 仅出现在 `src/debug` / `src/profile` |

> ✅ **本机门禁实测（2026-10-24，两条门禁都跑通了）**：
> `flutter analyze` → `No issues found!`（12.6s）；
> `flutter test`（全量，含 `testWidgets`）→ **`+525 ~6: All tests passed!`（30s）**。
> 交接文档里「本机跑不了 analyze / test（231 命名管道故障）」**本轮未复现** —— 本机现在能直接跑门禁，
> 不必再走 `tool/dart_*_fallback.py` 等效路线（那些脚本保留不动）。

### 1.2 分层与目录（实际组织方式）

```
lib/
├── main.dart          预热主题 → runApp(UncontrolledProviderScope)
├── app.dart           GoRouter（4 个壳 tab + 9 个全屏路由）
├── core/              基础设施：db（drift）/ providers（data_epoch）/ theme / utils / constants
├── data/
│   ├── providers/     DI：database + book / account / category
│   └── repositories/  6 个仓储（book / account / category / transaction / budget / app_meta）
└── features/          业务垂直切分：<name>/{data,application,presentation}
```

**没有 Service 层**。真实链路是：

```
UI (ConsumerWidget) → AsyncNotifier（features/<x>/application）→ Repository → SQLite(drift)
                     ↘ 纯函数口径（features/<x>/application/*_aggregate.dart）
```

纯计算全部是**无副作用纯函数**，`test()` 可直接覆盖 —— 这是本项目最值钱的可复用资产。

### 1.3 数据模型（schema v3，逐表）

业务表统一带「同步五件套」`owner_id / created_at / updated_at / deleted_at / dirty`；
**永不物理删除**（`deleted_at` 非空即已删）；**金额一律 `int` 分**；时间一律毫秒 epoch。

| 表 | 关键列 | 约束 / 索引 |
|---|---|---|
| `schema_meta` | `key` PK, `value` | 纯 KV（`active_book_id` / `theme_mode` / `onboarding_done` / `search_history` / `autobook_batches`） |
| `books` | `id` PK, `name`, `type`, `currency`, `icon`, `color`, `sort_order` | — |
| `accounts` | `id` PK, `book_id`, `name`, `type∈{cash,bank,credit,alipay,wechat,other}`, `initial_balance_cents`, `icon`, `color` | `idx_accounts_book` |
| `categories` | `id` PK, `book_id`, `name`, `kind∈{expense,income}`, `icon`, `color`, `is_preset` | `idx_categories_book_kind`；预置不可删 |
| `budgets` | `id` PK, `book_id`, `period='YYYY-MM'`, `amount_cents` | `CHECK(amount_cents>0)`；部分唯一 `idx_budget_book_period` |
| `transactions` | `id` PK, `book_id`, `account_id`, `category_id?`, `type∈{expense,income,transfer}`, `amount_cents`, `note`, `occurred_at`, `source`, `fingerprint?` | `CHECK(amount_cents>0)`；`idx_tx_book_occurred DESC`；**部分唯一 `idx_tx_fingerprint`** |

**五条会直接影响设计的语义**：

1. **金额是正整数分**，唯一换算入口 `yuanToCents` / `centsToYuan`（`core/utils/money.dart`），全程整数。
2. **`type` 决定方向**，`amount_cents` 恒为正；`transfer` 不计入任何收支 / 余额。
3. **分类是扁平的**，按 `kind` 分收支；**同一账本里有两个「其他」**（支出 / 收入各一个）→ 按名字解析必须带 `kind`。
4. **`source` 是自由 TEXT**（无 CHECK 约束）→ **加一种新来源不需要迁移**（自动记账已借此新增 `notify_wechat` / `notify_alipay` / `share`）。
5. **`fingerprint` 有部分唯一索引**（`WHERE fingerprint IS NOT NULL AND deleted_at IS NULL`）→ 指纹去重有数据库兜底。

### 1.4 可直接复用的"口径"与仓储（阶段一 / 二的主力）

**纯函数口径**（不改一行即可复用）：

| 函数 | 位置 | 用途 |
|---|---|---|
| `summarize(items) → MonthSummary` | `features/ledger/application/month_summary.dart` | 收入 / 支出 / 结余 |
| `aggregateByDay` / `dailyAverageExpenseCents` | `features/calendar/application/calendar_aggregate.dart` | 按天聚合 / 日均支出 |
| `categoryBreakdown` / `monthlyTrend` / `trendRange` | `features/stats/application/stats_aggregate.dart` | 分类占比 / 近 N 月趋势 |
| `groupByCategory` / `groupByAccount` | `features/reports/application/report_aggregate.dart` | 报表三档 |
| `buildAssetSummary` | `features/assets/application/asset_aggregate.dart` | 账户余额 / 净资产 |
| `buildBudgetView` | `features/ledger/application/budget_metrics.dart` | 预算进度 / 剩余 / 剩余每日可消费 |
| `parsePlan` / `filterTx` / `matchesQuery` | `features/search/application/search_query.dart` | 关键词 + 类型指令 + 时间区间 |
| `categorizeRow(row) → 分类名` | `features/import/data/category_rules.dart` | 商户 → 分类（33 条有序正则） |
| `computeFingerprint(...)` | `core/utils/fingerprint.dart` | `sha1('source|externalId|amountCents|秒级时间')` |

**仓储**（写库只允许走这一层）：

`TransactionRepository.create / getById / listByMonth / listByYear / listByRange / listByBook / update / softDelete / **importTransaction**`；
`BudgetRepository.getForMonth / setForMonth / clearForMonth`；
`AccountRepository.create / listByBook / update / softDelete`；
`CategoryRepository.listByBook(bookId, {kind})`；
`AppMetaRepository.get / set / remove`（KV，**写偏好不需要动 schema**）。

### 1.5 现有数据流与关键业务入口

```
① 手工记账   home「记一笔」→ /record → RecordPage._save()
                → TransactionRepository.create(source:'manual', fingerprint:null)
                → 手动 refresh(ledger/calendar/stats) + invalidate(yearDayIndex) + dataEpoch.bump()

② 账单文件   /import → ImportPage → parseBillFileAuto()（csv/xlsx 五层解析）
                → 预览（可单条取消）→ importRows()（单事务 + 指纹去重 + 未知分类落「其他」）
                → 账户 = ensureImportAccount()「导入账户」→ 刷新

③ 通知自动记账  Kotlin NotificationListener → 落盘 JSONL → Dart drain()
                → parseNotification() （纯函数：包名白名单 → 忽略规则 → 方向 → 金额 → 商户）
                → ParsedRow → importRows()（按 source 分组，每组一事务）
                → 记批次（可整批撤销）+ 回执通知 + refreshAfterAutoBookWrite()

④ 其它读路径  首页 / 日历 / 统计 / 报表 / 资产 / 搜索 —— 全部「仓储取数 + 纯函数聚合」
```

**关键入口文件**：`lib/app.dart`（路由表）、`lib/features/profile/presentation/profile_page.dart`（功能入口列表）、
`lib/features/record/presentation/record_page.dart`（手工入账）、`lib/features/import/application/bill_importer.dart`（统一入账）。

### 1.6 阶段一的最大资产：已有「文本 → 待确认账单」管线

`features/autobook/data/auto_book_rules.dart`（395 行）已经把**支付回执文本**解析成结构化行：

```
RawNotification.combined  →  _isIgnored()（硬忽略 8 词 / 软忽略 9 词 + 强支付词放行）
                          →  _directionOf()（收入词先判）
                          →  _amountCentsOf()（**6 级降级**：实付类 → 金额在动作词前 → 动作词后 → ¥ 符号 → 裸 N 元 → N.NN）
                          →  _counterpartyOf()（向…付款 / 收款方：/ 付款给 / 在…消费）
                          →  ParsedRow（import 链路共用的结构体）
```

这套规则**逐字对着真机通知校准过**（`test/features/autobook/auto_book_real_samples_test.dart`，47 + 16 条用例），
并且踩平了几个阶段一**必然会再遇到**的坑：

- 「订单 13.00 元，优惠 1.00 元，实付 12.00 元」→ 规则顺序决定记为 12.00 还是 1.00（**顺序即优先级**）。
- 「你有一笔 0.01 元的支出，领 2 元小荷包支付红包」→ 营销金额排在前面时的误抓。
- 「付款成功，优惠 0.50 元」→ 含营销词但**是真实消费**（软忽略词设计就是为这个）。
- 折叠前缀 `[N条]` → 归一化后再解析 + 指纹用归一化文本（否则同一条会算成两笔）。

> 结论：**OCR 之后的解析层不是从零写**，而是把这套规则**推广到"多行、有序、带坐标"的 OCR 文本**上。

### 1.7 「写后刷新」这条既有脆弱点

写操作后需要：`ledgerProvider.refresh()` + `calendarProvider.refresh()` + `statsProvider.refresh()` +
`ref.invalidate(yearDayIndexProvider)` + `dataEpochProvider.bump()`。
目前**已有两处重复实现**：`record_page.dart`（手工，内联）与
`auto_book_notice.dart` 的 `refreshAfterAutoBookWrite(Ref ref)`（带 `catchError` 的健壮版）。

→ 阶段一**只调用 `refreshAfterAutoBookWrite()`**，不复制第三份。（可选：把它改名/移到
`core/providers/after_write.dart`，那是 2 个既有文件、约 10 行的改动，**不在阶段一必需范围内**。）

### 1.8 隐私现状（阶段一是唯一能"保持原样"的阶段）

- 账本只在应用私有目录 `yanxin.sqlite`；**release 包无 `INTERNET` 权限**，README:263 把它写成卖点。
- 一旦接云端 LLM，这句话立刻不成立（这也是既有 `docs/spec/SPEC-agent-architecture.md` 里 D0 的核心矛盾）。
- **阶段一（本地 OCR + 规则）可以让这条承诺 100% 保持不变** —— 这是本地路线的最大优势，应在验收里明确守住。

---

## 2. Prompt 假设 vs 项目现实（逐条核对，冲突先说清）

| # | Prompt 的假设 / 建议 | 项目现实 | 处理 |
|---|---|---|---|
| 1 | 「优先本地，必要时才云端」 | 与仓库里已有的 `SPEC-agent-architecture.md`（**云端 LLM + 薄代理**，需 `INTERNET`）**正面冲突** | **以本 Prompt 为准**：本地优先。既有 agent SPEC 的 §6 工具契约 / §5 会话表 / §8 事件协议**仍然可复用**，仅 D0/D2/D3（联网与 Key）作废 |
| 2 | 「评估 Google ML Kit Text Recognition」 | `minSdk 24`（插件要 21 ✓）、`compileSdk 36`（插件要 35 ✓）；但本项目 **AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0** 是相当新的组合 | 可行，但**必须先做构建验证**（阶段一任务 0）；失败则退化为「自建 Kotlin 通道 + ML Kit AAR」，本项目已有 `yanxin/autobook` 通道先例 |
| 3 | 「不要把数 GB 模型打进 APK」+「支持模型下载」 | 下载 = 需要 `INTERNET` = 破坏「无网络权限」卖点 | **见 D3**：模型文件默认走「用户手动导入」（文件选择器 / adb push），App 内下载作为**需显式确认**的可选项 |
| 4 | 「识别结果要带可信度 / 待确认状态」 | 现有 `ParsedRow` **没有置信度字段**（它只服务"要么入账要么丢弃"的自动路径） | 阶段一新建 `ReceiptDraft`（带逐字段置信度 + 候选值），只在**确认后**转成 `ParsedRow` 语义入账 |
| 5 | 「复用现有 Transaction Service」 | **没有 Service 层**；等价业务入口是 `TransactionRepository.importTransaction()` + `importRows()` | 复用 `importTransaction(source: 'screenshot', externalId: …)`，天然幂等 |
| 6 | 「不要让 OCR/LLM 直接操作数据库」 | Kotlin 侧只落盘、drift 唯一 writer（不变量 #1） | 保持：OCR 只在 Kotlin 里跑识别，**结果回 Dart**，写库仍在 Dart |
| 7 | 「金额一律 int 分」 | 已是（ADR-2） | 完全一致 |
| 8 | 「按分类名」 | 同名「其他」有两个 | 一律 `(kind, name)` 解析；分类不命中落该方向的「其他」 |
| 9 | 「阶段二才做问答」 | 已有 `summarize / categoryBreakdown / buildBudgetView / buildAssetSummary` 全套口径 | 阶段二的「财务查询」层基本是**编排既有纯函数 + 新增少量区间查询**，不是新算法 |

---

## 3. 阶段一方案：最小改动的「截图 → 待确认账单」

### 3.1 分层（严格按 Prompt 的三层，不跳层）

```
选图(file_picker FileType.image，SAF/系统相册，无需运行时权限)
   │
   ▼  ① OCR（端上，离线）
OcrEngine（抽象）── MlKitOcrEngine（唯一原生依赖点，MethodChannel）
   │  输出 OcrResult{ lines:[{text, rect, lang}], elapsedMs }
   ▼  ② 规则解析（Dart 纯函数，可单测）
receipt_parse.dart：行归一化 → 平台判定 → 忽略/状态判定 → 方向 → 金额候选 → 时间 → 商户 → 订单号
   │  输出 ReceiptDraft（每字段带 confidence + candidates + issues）
   ▼  ③ 可选：本地模型辅助（阶段一默认关闭，仅留接口）
ReceiptAssist（接口，返回 null 时完全不影响流程）
   │
   ▼  ④ 交易字段校验（纯函数）
validateDraft()：金额缺失/多金额/原价实付/退款/失败/年份不明/商户不明/疑似重复
   │
   ▼  ⑤ 确认页（Toon 组件，与 /import 预览页同构）
用户逐字段确认/修正（低置信度高亮）
   │
   ▼  ⑥ 写库（唯一入口）
TransactionRepository.importTransaction(source:'screenshot', externalId: 文本指纹)
   → refreshAfterAutoBookWrite(ref)
```

### 3.2 OCR 方案（选型与依据）

| 项 | 结论 | 依据 / 待验证 |
|---|---|---|
| 方案 | **Google ML Kit Text Recognition v2（中文 bundled）** | 端上、离线、免费、中文支持好、无 Play Services 依赖（bundled 变体） |
| Flutter 包 | `google_mlkit_text_recognition ^0.17.1`（MIT，verified publisher `flutter-ml.dev`） | pub.dev 页面：minSdk 21 / compileSdk 35；**中文需在 app 加 AAR** |
| 中文模型 | `implementation 'com.google.mlkit:text-recognition-chinese:16.0.1'`（bundled） | 插件 README 明确要求手动加；bundled = 模型随包，**不做运行时下载** |
| 为什么不用 unbundled | `text-recognition-chinese-play-services` 依赖设备上的 Google Play 服务，**国产 ROM / 无 GMS 设备不可靠** | 与「零配置、离线可用」的产品目标冲突 |
| 备选（若插件与 AGP 9.1 冲突） | **自建 Kotlin 通道** `yanxin/ocr` + 同一个 AAR（约 100 行，照 `yanxin/autobook` 的写法） | 本项目已有平台通道先例；无 pub 依赖 |
| 明确不做 | 云端 OCR API、Tesseract（中文精度/体积均不划算）、把模型塞进 APK 的"自研 OCR" | — |

### 3.3 数据契约（阶段一新增的唯一"新概念"）

```dart
/// 一个字段的值 + 它有多可信 + 其他候选（UI 可一键切换）。
class ReceiptField<T> {
  final T? value;
  final FieldConfidence confidence;   // high | medium | low | absent
  final List<T> candidates;           // 多金额 / 多时间时的备选
  final String? source;               // 'rule:实付' | 'rule:¥符号' | 'llm' | 'user'
}

class ReceiptDraft {
  final String? platform;             // 微信支付 / 支付宝 / 银行 / 未知
  final ReceiptField<String> direction;   // expense | income
  final ReceiptField<int> amountCents;    // 恒为正整数分
  final ReceiptField<int> occurredAtMs;   // 毫秒（本地时区）
  final ReceiptField<String> merchant;
  final ReceiptField<String> categoryName; // 由 categorizeRow 预填
  final ReceiptField<String> accountId;    // 由"支付方式 → 账户类型"预填
  final String? orderNo;                   // 订单号 / 交易号（有则拼进 externalId）
  final ReceiptStatus status;              // ok | refund | failed | cancelled | unclear
  final List<DraftIssue> issues;           // 需用户确认的原因（枚举，可本地化）
  final String rawText;                    // 归一化后的 OCR 文本（**只在内存与确认页展示，不落库**）
}
```

`confidence` 的阈值**必须由样本测试确定**（Prompt §4 明确要求），不得凭感觉设定。
初版规则（待 20+ 张真实样本校准）：

- 金额：命中「实付/实际支付/支付金额」类锚点 → `high`；仅命中 `¥` 或「N 元」→ `medium`；命中多个且分属不同锚点 → `low` + `candidates` 全给。
- 时间：完整 `YYYY-MM-DD HH:mm` → `high`；`MM-DD HH:mm`（需推断年份）→ `medium`；只有日期 → `medium`；只有 `HH:mm` → `low`。
- 商户：命中「向…付款 / 收款方 / 付款给 / 在…消费」→ `high`；平台名单独出现 → `low`；无 → `absent`。

### 3.4 写库与去重（复用既有链路，不新增表）

- 入账：`TransactionRepository.importTransaction(bookId, accountId, type, amountCents, occurredAt,
  categoryId, note: merchant, source: 'screenshot', externalId: <文本指纹>)`。
- `externalId` 组成：`sha1(归一化 OCR 文本)` [+ 订单号若存在] → `computeFingerprint` 再混入
  `amountCents + 秒级 occurredAt`。**同一张截图重复导入 → 同一指纹 → 部分唯一索引兜底 → `ImportDuplicate`**
  → UI 显示「这笔之前已经记过了」并给「查看那一笔」入口（不静默丢弃、也不重复写）。
- 「金额相同、时间相近、商户相同但指纹不同」→ 命中 `ImportOk`，但确认页给一条 **"疑似与 X 月 X 日那笔重复"** 的软提示（用户可继续）。
- **schema 不动（仍 v3）**：`source` 是自由 TEXT，`fingerprint` 已有索引。

### 3.5 文件级清单（阶段一）

> **实际交付见 §9**（本表是开工前的计划，§9 记录落地后的真实文件与偏差）。

**新增（10 个产品文件 + 4 个测试 + 1 份样本目录）**

| 文件 | 作用 | 备注 |
|---|---|---|
| `android/app/src/main/kotlin/com/teacodeman/yanxin/ocr/OcrChannel.kt` | MethodChannel `yanxin/ocr`：`recognize(path)` / `dispose()`；内部 `ChineseTextRecognizerOptions`，串行单例，后台线程执行，返回 `lines[{text,x,y,w,h}]` + `elapsedMs` | 只在**方案 B（自建通道）** 时需要 |
| `lib/features/receipt/data/ocr_engine.dart` | `abstract interface class OcrEngine { Future<OcrResult> recognize(String path); }` + `OcrResult` / `OcrLine` | 让 UI 与业务不依赖具体引擎（**可测性关键**） |
| `lib/features/receipt/data/mlkit_ocr_engine.dart` | 实现：调 `google_mlkit_text_recognition`（方案 A）或 `MethodChannel`（方案 B） | 唯一原生依赖点，出错全部翻译成 `OcrFailure` |
| `lib/features/receipt/data/receipt_rules.dart` | 关键词 / 正则表：平台、忽略、状态、方向、金额锚点、商户、订单号、支付方式 | 与 `autobook_rules.dart` 同写法（**先命中先赢，顺序即优先级**） |
| `lib/features/receipt/data/receipt_parse.dart` | `parseReceipt(List<String> lines) → ReceiptDraft`（纯函数，无 IO） | 阶段一测试的主战场 |
| `lib/features/receipt/application/receipt_draft.dart` | `ReceiptDraft` / `ReceiptField` / `DraftIssue` / `validateDraft()` / 年份推断 / 阈值常量 | 纯函数 |
| `lib/features/receipt/application/receipt_write.dart` | `writeReceipt(...)`：草稿 → 分类解析（`(kind,name)`）→ 账户预填 → `importTransaction` → 返回 `({ImportResult, TxRow?})` | 唯一写库点 |
| `lib/features/receipt/presentation/receipt_page.dart` | 三步页：选图 → 识别/确认（可编辑）→ 结果 | 与 `/import` 同构（步骤条 + 卡片 + 吸底按钮） |
| `lib/features/receipt/presentation/widgets/receipt_field_row.dart` | 单字段行（低置信度高亮 + 切换候选 + 行内编辑） | 复用 `ToonField` / `ToonCard` |
| `lib/features/receipt/presentation/widgets/receipt_candidates_sheet.dart` | 多金额 / 多时间候选选择弹层 | 复用 `show...Sheet` 的既有写法 |
| `test/features/receipt/receipt_parse_test.dart` | 金额（多金额 / 原价实付 / 优惠）/ 时间（缺年份）/ 退款 / 失败 / 订单号 / 商户 / 平台 | 纯 `test()` |
| `test/features/receipt/receipt_draft_test.dart` | 置信度阈值、必填缺失、年份推断边界 | 纯 `test()` |
| `test/features/receipt/receipt_write_test.dart` | 内存 drift 库：入账成功 / 同图二次导入 → Duplicate / 分类不存在 → 落「其他」/ 金额 0 → 拒绝 | `AppDatabase(NativeDatabase.memory())` |
| `test/features/receipt/receipt_page_test.dart` | `FakeOcrEngine` 注入 → 预览 → 改金额 → 确认 → 断言库里有一笔 & 刷新被调用 | `testWidgets` |
| `test/fixtures/receipts/*.txt` | 脱敏的真实 OCR 文本样本（**只存文本，不存原始截图**） | 隐私：不入库任何真实姓名 / 卡号 |

**修改（3 个文件，均为"接线"级）**

| 文件 | 改动 |
|---|---|
| `pubspec.yaml` | `+ google_mlkit_text_recognition: ^0.17.1`（方案 A）；方案 B 则**不加任何 pub 依赖** |
| `android/app/build.gradle.kts` | `+ dependencies { implementation("com.google.mlkit:text-recognition-chinese:16.0.1") }` |
| `lib/app.dart` | `+ GoRoute('/receipt')` |
| `lib/features/profile/presentation/profile_page.dart` | `+ 1 个 _Entry「截图记账」` |
| `android/.../MainActivity.kt` | 方案 B 才需要：`+ OcrChannel(...)` 一行接线 |

**明确不动**：`lib/core/db/**`（**schema 不升级**）、`TransactionRepository`、`bill_importer.dart`、
`category_rules.dart`、`autobook/**`、`android/AndroidManifest.xml`（**不加任何权限**）。

### 3.6 必须提前堵住的坑（每条都对应一条测试）

| 坑 | 真实成因 | 处理 |
|---|---|---|
| 多金额误取 | 「原价 13.00 / 优惠 1.00 / 实付 12.00」 | 6 级降级锚点（照抄 autobook 的顺序）+ 全部候选交给用户切 |
| 退款当支出 | 「已退款」「退款成功」 | `status=refund` → **默认不生成支出**，让用户选「记为收入」或「忽略」 |
| 支付失败/取消 | 「支付失败」「交易关闭」「已取消」 | `status=failed/cancelled` → 直接不生成草稿（明确提示，不写库） |
| 时间缺年份 | 「10-23 14:05」 | 推断：不晚于今天且距今 ≤ 180 天 → 今年，否则去年；`confidence=medium` + UI 明示「年份为推断」 |
| 商户不明 | 只有「微信支付」 | `merchant.confidence=absent` → 备注留空 + 提示用户补（**不编造**） |
| 同一张图二次导入 | 用户忘记已记过 | 文本指纹去重（索引兜底）+ 确认页「疑似重复」软提示 |
| 图片模糊 / 旋转 / 截断 | OCR 行数太少或无金额 | `issues` 明确「未识别到金额」→ 停在确认页让用户手输，**绝不写 0 元或猜值** |
| 同名分类「其他」 | 支出/收入各一个 | `(kind, name)` 二元组解析 |
| OCR 失败 / 模型未就绪 | AAR 未打包、识别器初始化失败 | 三步页停在第一步 + 可读错误 + 「手动记一笔」兜底入口 |
| 写后视图不刷新 | HANDOFF 不变量 #2 | 复用 `refreshAfterAutoBookWrite(ref)` |
| 中文字段进日志 | 财务隐私 | **不打印 OCR 原文 / 金额**；只记 `行数 / 耗时 / 失败码` |

### 3.7 阶段一验收（对齐 Prompt §6，逐条可执行）

| # | 验收项 | 判定方式 |
|---|---|---|
| 1 | 从本地相册选截图 | 真机：系统相册选图（SAF，无权限弹窗） |
| 2 | 端上完成 OCR | 飞行模式 → 仍能识别（证明离线） |
| 3 | 无网络时完成基础识别与规则解析 | 同上 + 断言 `AndroidManifest` 无 `INTERNET` |
| 4 | 常见消费截图 → 待确认账单 | 样本集：微信支付 / 支付宝 / 银行卡短信截图 / 电商订单，各 ≥ 3 张 |
| 5 | 不确定时可手动修正 | 确认页每个字段可编辑；低置信度高亮 |
| 6 | 确认后走现有业务逻辑写入 | `importTransaction(source:'screenshot')`，无第二条写库路径 |
| 7 | 失败不产生错误账单、不崩溃 | 失败用例：无金额 / 全模糊 / 退款 / 重复 / 无分类账本 |
| 8 | 测试覆盖金额、时间、退款、重复、模糊 | `test/features/receipt/**` 全绿 |
| 9 | 不上传任何内容 | 无网络依赖、无 `INTERNET` 权限、无 `http` 依赖 |
| 10 | analyse / test 门禁 | `flutter analyze` 无 issue；`flutter test` 全绿 |

---

## 4. 本地 LLM（阶段二的主力，阶段一只留接口）

### 4.1 候选方案矩阵（**不预设结论，先基准**）

| 方案 | 集成方式 | 中文能力 | 工作量 | 主要风险 |
|---|---|---|---|---|
| **A. llama.cpp（自建 JNI）** | NDK/CMake 把 llama.cpp 编进 `libllama.so`，Kotlin JNI 包装，Dart 走 MethodChannel | 取决于模型（Qwen 系强） | 中～大（vendor 源码 / 编 aarch64 / JNI 生命周期） | 体积、ABI、构建时间、内存 |
| **B. MediaPipe LLM Inference** (`tasks-genai`) | Gradle AAR + Kotlin API（`LlmInference`），模型 `.task` | 只支持 Gemma 系（中文偏弱） | **小**（约 100 行） | 模型可选面窄；许可需核对 |
| **C. `llama_cpp_dart` 包** | 仍需**自己编译** `libllama.so` → 本质是 A 的封装 | 同 A | 中 | 包为 `unverified uploader`、0.2.2 / 0.9.0-dev；不能解决编译那一关 |
| **D. `fllama`（llama.cpp Flutter 插件）** | 插件自带构建 | 同 A | 小～中 | 插件维护节奏与 AGP/NDK 版本兼容（本项目 AGP 9.1 / NDK 28） |

**推荐路线**：**先 A（自己掌控），把 B 作为"低端机降级/快速验证"备选**；C/D 只在 A 的构建成本被证明过高时启用。
理由：Stage 2/3 需要**流式、取消、工具调用（JSON 结构化输出）、上下文控制**，这些必须由我们自己的
`LlmProvider` 掌控；把 llama.cpp 的采样/停止/上下文交给第三方插件会限制阶段三。

**模型候选**（阶段二第一件事就是实测，不预选）：`Qwen3-1.7B` / `Qwen2.5-1.5B-Instruct`（Q4_K_M）、
`Gemma-3-1B`（MediaPipe 路线）。**必须实测**：加载时长、常驻内存（RSS）、首 token 延迟、tok/s、长上下文退化、发热。

### 4.2 基准测试协议（阶段二任务 1，产出一张设备×模型矩阵）

在**真机**（不是模拟器）记录：机型 / SoC / RAM / Android 版本 / 模型 / 量化 / 上下文长度 /
模型文件体积 / 峰值 RSS / 冷加载 ms / 首 token ms / 生成 tok/s / 10 轮问答后 RSS /
20 分钟连续推理的温升与降频。**没有这张表就不写"支持哪些设备"的文案**（Prompt §四要求）。

### 4.3 抽象接口（阶段一建好、阶段二填实现）

```dart
abstract interface class LlmProvider {
  Future<void> load(ModelHandle handle);      // 加载模型（可失败 → LlmUnavailable）
  Stream<LlmEvent> generate(LlmRequest req);  // 流式：Token / Done / Error / Cancelled
  Future<void> cancel();
  Future<void> release();                     // 释放（后台/切页必须调）
  LlmCapabilities get capabilities;           // 上下文长度、是否支持 JSON 约束
}
```

阶段一的 `ReceiptAssist` 就是它的一层薄封装：**没有模型时 `load()` 直接返回 `LlmUnavailable`，
解析流程完全不受影响**（Prompt §2「不要为了截图识别强行引入大模型」）。

### 4.4 模型分发与"无网络"承诺的冲突（见 D3）

| 选项 | 做法 | 代价 |
|---|---|---|
| **D3-a 手动导入（推荐先做）** | 用户自行把 `.gguf` 放进手机，App 里用文件选择器导入 → 校验 sha256 → 移到应用私有目录 | 无 `INTERNET`，卖点不变；门槛高（普通用户难） |
| D3-b App 内下载 | 需 `INTERNET`；断点续传 / 校验 / 取消 / 空间检测（Prompt §3 一整套） | **"无网络权限"卖点失效**，README/PRD/发布说明全部要改写 |
| D3-c 双包（offline / ai） | 两个 flavor | 发布工程翻倍；**换 applicationId = 丢账本**（HANDOFF 明确警告） |
| D3-d 不接模型 | 阶段二只做"结构化财务查询 + 本地模板化解释" | 无"AI 感"，但零风险、零体积 |

> 我的建议：**阶段一不问这个问题**（用不到模型）；**阶段二开工前**先按 D3-a 打通链路，
> 再单独评估要不要为"下载"付出卖点代价。

---

## 5. 风险 / 兼容性 / 性能（按影响排序）

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| 1 | **AGP 9.1.0 + Gradle 9.3.1 + Kotlin 2.4.0** 与 ML Kit 插件/AAR 的兼容性未验证 | 阶段一可能卡在构建 | 任务 0：先只加依赖跑一次 debug 构建；失败立即切"自建 Kotlin 通道"（本项目已有先例） |
| 2 | **中文路径**导致 AGP/`gen_snapshot` 拒绝构建 | 出不了包 | 已有既定做法（`android.overridePathCheck` / ASCII 副本 `D:\yanxin-build`），照 `docs/dev/release-v0.7.17.md` |
| 3 | **本机无真机**（`adb devices` 为空） | 阶段一验收做不了 | 见 D1：需要 MuMu 或真机 |
| 4 | APK 体积增加（中文模型 AAR + 多 ABI） | 安装包变大 | 实测增量后再决定是否 `abiFilters`；**先量化再优化** |
| 5 | 规则召回率不足（截图版式远比通知文本复杂） | 识别不出 / 认错字段 | 用真实样本驱动（≥20 张），先"宁缺勿错"：不确定一律交用户确认 |
| 6 | OCR 耗时 / 内存（大图、长截图） | 卡顿 | 先压到长边 ≤ 2000px 再识别；识别器单例复用；`dispose` 释放 |
| 7 | 低端机无法跑本地模型（4GB RAM） | 阶段二功能不可用 | 设备探测 + 明确降级文案；**不承诺速度**（Prompt §四） |
| 8 | 模型下载需联网 vs 隐私卖点 | 产品承诺冲突 | 见 D3 |
| 9 | 用户在备注/截图里写"指令"被模型当命令 | 提示注入 | 阶段三：工具参数校验 + 写操作强制确认（既有 SPEC §6.3 可复用） |

---

## 6. 分阶段计划与验收

| 阶段 | 交付 | 验收（硬条件） |
|---|---|---|
| 零（本轮） | 本文档 | 用户签字 + D1–D6 有结论 |
| **一 · 截图记账** | OCR + 规则 + 确认页 + 写库 | §3.7 十条；`analyze` 0 issue、`test` 全绿、真机走查通过（含飞行模式） |
| 二 · 本地问答 | `LlmProvider` + 财务查询编排 + 问答页 | 3 个模型 × 2 台设备的基准表；金额/统计**全部来自业务代码**；模型缺失有明确提示；关键查询单测 + 集成测试 |
| 三 · 本地 Agent | 6 个只读工具 + 3 个写工具 + 审批 | 工具参数由代码严格校验；写操作必须确认；取消/失败零意外写入；覆盖测试 |
| 四 · 模型管理 | 下载/校验/删除、性能与降级、隐私说明、回归 | Prompt §四 九项逐条 |

---

## 7. 决策项（D1–D6，**已于 2026-10-24 按建议拍板**）

| # | 问题 | 选项 | 我的建议 |
|---|---|---|---|
| **D1** | 真机/模拟器 | a) 启动 MuMu 12；b) 连 Android 手机；c) 先只做本机门禁 | **b > a**：OCR 与性能必须在真机看；本机只能跑 analyze/test |
| **D2** | OCR 依赖形态 | a) 用 `google_mlkit_text_recognition` 插件；b) 自建 Kotlin 通道（无 pub 依赖） | **先 a 试一天**，构建不通立刻 b（代码量差不多，b 更可控） |
| **D3** | 阶段一是否接本地模型 | a) 不接（只留接口，默认关）；b) 接上做"辅助解析" | **a**：Prompt 也写"不要为了截图识别强行引入大模型" |
| **D4** | 模型分发（阶段二） | a) 手动导入 `.gguf`；b) App 内下载（需 `INTERNET`）；c) 不接模型 | **a 起步**，b 单独立项评估 |
| **D5** | 版本/流程 | a) 新开 F8 线（`v0.8.1`…）+ 小 SPEC 签字；b) 沿用 F7 序号 | **a**：本地 AI 是新产品线，且 HANDOFF 有「F 阶段一版一 tag」约定 |
| **D6** | 样本语料 | a) 你提供 5–10 张真实截图（脱敏，只取 OCR 文本入库）；b) 我用合成/公开样例先做，真实样本后补 | **a**：规则必须对着真实版式校准（自动记账那套就是被真机样本逼出来的） |

---

## 8. 附：本轮已实际执行的验证

```powershell
# 环境（本机实测）
flutter --version                     # Flutter 3.47.2 / Dart 3.13.2
flutter analyze --no-pub              # No issues found! (12.6s)
flutter test --no-pub                 # +525 ~6: All tests passed! (30s，全量，含 testWidgets)
flutter test --no-pub test/features/import test/features/autobook/auto_book_rules_test.dart
                                      # +119 ~6: All tests passed!（子集，用于快速回归）
adb devices                           # 无设备连接
```

> 未执行：任何 Android 构建、任何真机走查。
> **本文档没有修改任何产品代码**；新增文件仅本 SPEC。

---

## 9. 阶段一实施记录（2026-10-24 交付）

> 决策已拍板：**D1–D6 全部按 §7 的建议执行**（用户 2026-10-24 原话「D1-D6都听你的」）。
> D1（真机）当前仍**无设备**（`adb devices` 为空）→ 真机走查待补，见 §9.5。

### 9.1 实际交付（14 个新增文件 / 6 个修改）

| 文件 | 作用 |
|---|---|
| `android/app/src/main/kotlin/com/teacodeman/yanxin/ocr/OcrChannel.kt` | 平台通道 `yanxin/ocr`：`recognize(path)` / `release` / `engineInfo`；`ChineseTextRecognizerOptions` 单例 + 单线程队列 + 25s 超时 + 主线程回包 |
| `android/app/src/release/AndroidManifest.xml` | **去掉**依赖链带进来的 `INTERNET` / `ACCESS_NETWORK_STATE`（只 release，debug 保留热重载必需） |
| `lib/features/receipt/data/ocr_engine.dart` | `OcrEngine` 接口 + `OcrResult` / `OcrLine`（`lineTexts` 稳定排序）+ `OcrFailure`（可读文案） |
| `lib/features/receipt/data/mlkit_ocr_engine.dart` | `MethodChannel` 实现 + `ocrEngineProvider`；平台异常统一翻译成 `OcrFailure` |
| `lib/features/receipt/data/receipt_rules.dart` | 平台 / 状态 / 方向 / 金额锚点（7 级）/ 优惠词 / 时间 4 档 / 商户 / 订单号 / 支付方式 规则表 |
| `lib/features/receipt/data/receipt_parse.dart` | `parseReceipt(lines, nowMs:)` 纯函数（平台 → 状态 → 方向 → 金额 → 时间 → 商户 → 订单号 → 分类预填 → 问题清单） |
| `lib/features/receipt/application/receipt_draft.dart` | `ReceiptDraft` / `ReceiptField<T>` / `FieldConfidence` / `ReceiptIssue`（阻断 vs 提醒） |
| `lib/features/receipt/application/receipt_write.dart` | `writeReceipt()`（→ `importTransaction(source:'screenshot')`）、`resolveReceiptCategoryId()`、`findSimilarReceipts()` |
| `lib/features/receipt/presentation/receipt_page.dart` | 三步页：选图 → 核对（可改字段 / 多金额切换 / 原文展开）→ 结果 |
| `lib/features/receipt/presentation/widgets/receipt_bits.dart` | 步骤条 / 提示条 / 状态胶囊 / 问题清单 / 候选 chip / 原文块 / 缩略图 |
| `lib/core/providers/after_write.dart` | **写后刷新收口**（`Ref` 与 `WidgetRef` 两个入口，口径一致） |
| `test/features/receipt/receipt_parse_test.dart`（24 例） | 微信 / 支付宝 / 银行短信 / 退款 / 失败 / 取消 / 三金额 / 订单 / 多金额 / 糊图 / 年份推断 / 非法日期 / 归一化 / 指纹 |
| `test/features/receipt/receipt_draft_test.dart`（8 例） | 可信度口径、阻断集合、`canWrite`、候选去重、问题文案非空 |
| `test/features/receipt/receipt_write_test.dart`（7 例） | 落库成功 / 同图二次确认去重 / 0 元与空分类被拒 / 分类回退 / 收入不串「其他」/ 疑似重复窗口 |
| `test/features/receipt/receipt_page_test.dart`（4 例） | 全流程（含二次确认不重复）/ 多金额切换 / 失败单按钮禁用且不写库 / 通道不可用的文案 |
| `test/features/receipt/ocr_result_test.dart`（6 例） | 行排序稳定性、同一行横向优先、无坐标兜底、`OcrFailure` 文案不泄露原生信息 |

**修改**：`android/app/build.gradle.kts`（+`com.google.mlkit:text-recognition-chinese:16.0.1`）、
`MainActivity.kt`（+通道接线）、`lib/app.dart`（+`/receipt`）、
`lib/features/profile/presentation/profile_page.dart`（+「截图记账」入口）、
`lib/features/autobook/application/auto_book_notice.dart`（刷新逻辑改为委托，去掉一处重复）。

**没动的**：`pubspec.yaml`（**零新增 pub 依赖**、`pubspec.lock` 一字未改）、`lib/core/db/**`（**schema 仍 v3**）、
`TransactionRepository`、`bill_importer.dart`、`category_rules.dart`、`src/main/AndroidManifest.xml`。

### 9.2 与开工计划的四处偏差（都有实测理由）

| # | 计划 | 实际 | 理由 |
|---|---|---|---|
| 1 | D2：先试 `google_mlkit_text_recognition` 插件 | **直接自建 Kotlin 通道** | 中文**必须**再加 `text-recognition-chinese` 这个 AAR，插件只是薄封装；自建后 `pubspec.lock` 不动、少一个第三方 Gradle 插件（本项目 AGP 9.1 / Gradle 9.3 / Kotlin 2.4 是相当新的组合） |
| 2 | 计划表里 `receipt_field_row.dart` + `receipt_candidates_sheet.dart` | 合成一个 `widgets/receipt_bits.dart` | 几个都是 20–40 行的小件，拆三个文件反而更难读（简单优先） |
| 3 | 计划「优惠词命中整行即判非实付」 | 改为「优惠词必须在金额**前** 8 字内」 | 测试抓到：支付宝真实文案「你有一笔12.00元的支出，领2元小荷包支付红包」整行含「红包」→ 真金额被标成优惠 → **主金额消失** |
| 4 | 计划「时间缺年份按 180 天推」 | 改为「不晚于今天一天，否则算去年」+ **非法日期直接留空** | 180 天会把 12-31 推到明年；而 `2026-02-30` 这类 OCR 错读若退回「只有时分」，会写出**错日期 + 今天时间**的账单（比留空更糟） |

补充：**D3 落地为 a（不接模型）**，但**没有**建 `ReceiptAssist` 空接口 ——
Prompt 明确「不要机械地新增大量空壳类」，模型接口应与阶段二的 `LlmProvider` 一起定义（§4.3 已写好契约草案）。

### 9.3 门禁（本机实测）

```powershell
flutter analyze --no-pub     # No issues found! (8.2s)
flutter test --no-pub --concurrency=1
                             # +574 ~6: All tests passed!（阶段一新增 49 例；基线 525）
flutter build apk --debug --no-pub
                             # √ Built build\app\outputs\flutter-apk\app-debug.apk（442s）
```

**构建产物核验**：

```powershell
# 1) ML Kit 中文模型与 native 库确实进包（离线可用的前提）
APK: build\app\outputs\flutter-apk\app-debug.apk（debug，201.7 MB，含 3 个 ABI）
  lib/{arm64-v8a,armeabi-v7a,x86_64}/libmlkit_google_ocr_pipeline.so  → 28.1 MB
  assets/mlkit-google-ocr-models/**（Hani 中文 + Latn 拉丁 + 版面分析）→ 2.4 MB

# 2) 我们的 Kotlin 代码真的编进去了
classes7.dex / classes9.dex 里含 `OcrChannel` 与通道名 `yanxin/ocr`
classes.dex 里含 `ChineseTextRecognizerOptions` / `TextRecognition`

# 3) 正式包仍然没有网络权限（这条是产品承诺，必须守住）
.\gradlew.bat :app:processReleaseMainManifest
   → build\app\intermediates\merged_manifest\release\processReleaseMainManifest\AndroidManifest.xml
   只剩 POST_NOTIFICATIONS / RECEIVE_BOOT_COMPLETED (+ AndroidX 自动生成的 DYNAMIC_RECEIVER_...)
   INTERNET / ACCESS_NETWORK_STATE → **不存在**
```

> ⚠️ **本机内存不足的处理**：构建时 Gradle 守护进程两次因 native OOM 崩掉
>（系统 commit 只剩 ~0.9 GB，`hs_err_pid*.log` 里是 `Chunk::new` malloc 失败）。
> 临时把 `android/gradle.properties` 的 `-Xmx8G -XX:MaxMetaspaceSize=4G` 降成 `-Xmx3G` 后构建成功，
> **构建完已按字节还原**（`git diff android/gradle.properties` 为空）。仓库里的值没有改动。

### 9.4 三条新增的工程约束（写进 HANDOFF）

1. **ML Kit 的依赖链自带 `INTERNET`**（`com.google.android.datatransport:transport-backend-cct`）——
   以后任何"加个 ML/Google 库"的改动，**必须重新核 `processReleaseMainManifest`**，
   否则「正式包无网络权限」会**静默失效**（这条是本次实测抓到的，不是推测）。
2. **debug 包必须有 `INTERNET`**（Flutter 热重载的 VM service 走 TCP）→ 权限删除只能放 `src/release/`。
3. **APK 体积**：ML Kit 每 ABI 约 +13 MB（arm64：so 10.6 + 模型 2.4）。若将来要瘦身，
   正解是 `abiFilters` 或 ABI split（**本轮不动打包配置**，属产品决策）。

### 9.5 已知限制 / 未验证项（如实记录）

| # | 项 | 状态 | 补做方式 |
|---|---|---|---|
| 1 | **真机 OCR 实跑** | ❌ 未做（`adb devices` 为空） | 连设备后 `adb install -r -t build\app\outputs\flutter-apk\app-debug.apk` → 相册选 6 类截图各 1 张 |
| 2 | **飞行模式离线验证** | ❌ 未做（同上） | 关网后重复第 1 步，应完全一致 |
| 3 | **规则召回率 / 阈值** | ⚠️ 只用了合成 + 脱敏句式（D6 真实样本尚未提供） | 拿到真实截图后：先跑 `parseReceipt` 看字段，再决定要不要调锚点顺序 |
| 4 | **OCR 耗时 / 内存** | ⚠️ 只有合成数据下的 `elapsedMs` 占位 | 真机记录：单张 1080p 截图耗时、连续 10 张后的 RSS |
| 5 | 批量 / 长截图（滚动截图） | ❌ 未做（单张） | 阶段四再评估；结构上 `parseReceipt` 已接受任意行数 |
| 6 | 本地模型辅助解析 | ❌ 未接（D3=a） | 阶段二与 `LlmProvider` 一起做 |
| 7 | 版本 / tag | ⏳ 未发（D5=a：F8 线，`v0.8.1`） | **真机走查通过后**再写 CHANGELOG 段落 + 打 tag + 更新 README 版本表 |

### 9.6 真实样本校准（2026-10-24，用户提供的 8 张微信账单 OCR 文本）

样本：`[OCR]_true picture_20261024_0428.txt`（8 张，均为微信「账单详情」）。
已固化成回归测试 `test/features/receipt/receipt_real_samples_test.dart`（10 例），
**改规则前先跑它**。真实版式带来 5 处规则修正：

| # | 真实版式暴露的问题 | 修法 |
|---|---|---|
| 1 | 金额**独占一行且带负号**（`-3.00`），没有任何「实付」标记 | 新增「金额上一行就是收款方」启发式 + 带符号的独立金额判 **high** 可信 + 符号兼作方向兜底 |
| 2 | `独立行` 锚点的正则**漏了捕获组** → 解析直接抛 `RangeError` | 补 `([+-]?\d{1,7}\.\d{2})`，并在解析层加 `groupCount < 1` 防御 |
| 3 | 二维码付款的凭证写 **「转账单号」**，原表里没有 → 拿不到单号 | `kOrderNoLabels` 增加「转账单号」；`kMerchantPatterns` 增加 `付款-给X`（破折号写法） |
| 4 | 「收款方备注 二维码收款」里的裸 **「收款」** 把支出判成了**收入** | 收入词只留动作短语（`收款到账`/`已收款`/`收款成功`/`收到转账`），删掉裸「收款」 |
| 5 | 「零食有鸣」这类零食集合店落「其他」 | `category_rules` 增加 `零食|生鲜|菜市场|水果店 → 购物` |

**仍存的已知粗糙点**（如实记录，未过拟合单一样本）：
- 「美团」规则恒判**餐饮**，但样本里有一笔是**民宿**（走美团 App 下单）→ 需用户在确认页改分类。
- 二维码付款的商户可能只是**收款方昵称**（样本里是「静」），店铺名在标题行（`扫二维码付款-给沙县小吃`）→ 当前取昵称，用户可改备注。
- 「福伴生活(西环店)」这类区域小店没有关键词可命中 → 落「其他」（**这是正确行为**：不确定就交用户）。

### 9.7 ABI 瘦身（本轮一并落地）

`android/app/build.gradle.kts`：

- `defaultConfig.ndk.abiFilters` = `arm64-v8a` + `armeabi-v7a`（**正式包只打 ARM**）；
- `buildTypes.debug.ndk.abiFilters.add("x86_64")`：模拟器（MuMu 是 x86_64）仍能跑。
- ⚠️ **实测结论：AGP 的 `abiFilters` 在 buildType 层是「并集」**，不是覆盖 ——
  用 `debug = arm64 only` 做探针，打出来的包仍是 `arm64-v8a + armeabi-v7a`。
  所以 debug 里只追加 x86_64；release 不追加 → 正好只剩 defaultConfig 这两项。

**收益（按 AAR/APK 实测）**：`libmlkit_google_ocr_pipeline.so` 去掉 x86_64 那份即 **−11.1 MB / 包**
（arm64 10.6 MB + v7a 6.5 MB + 模型 2.4 MB 保留）。

**验证边界**：release APK 本机**没构建**（AOT + 中文路径 + 内存余量不足），
所以「release 最终 ABI 列表」是由「探针证明过滤在打包层生效」+「buildType 并集语义」推出来的；
有内存的机器上 `flutter build apk --release` 后可用
`unzip -l app-release.apk | grep lib/` 复核（应为 arm64-v8a / armeabi-v7a 两项）。

### 9.8 真机走查（2026-10-24 · Redmi K50 / Android 14 / HyperOS）

设备：`22041211AC`（rubens），1080×2400，arm64。走查途中撞到**两个与 F8.1 无关的工程阻塞**，
都已定位/处理，如实记录：

#### 阻塞 ①（**严重，已修**）：新装的包**一启动就 SIGSEGV**

| 项 | 内容 |
|---|---|
| 现象 | `libc: Fatal signal 11`，`Abort message: 'JNI is not initialized. Are you trying to invoke a Java API from Dart code too early, before main() (such as during Dart plugin class registration)?'`，进程秒退 |
| 复现范围 | debug **和** release **都崩**；**未改动的 HEAD（`58d59b8` / v0.7.17）在真机上同样崩** → 与 F8.1 无关，是**依赖层**问题 |
| 根因 | `path_provider_android 2.3.1` 已改用 **jni/jnigen** 实现（`androidApplicationContext.as(Context.type)`），它带进来的 `jni 1.0.3` + `jni_flutter 1.0.3` 在本机 Flutter 3.47.2 / Android 14 上初始化时序不对 → `FindClass` 踩空 |
| 修法 | `pubspec.yaml` 增加 `dependency_overrides: jni: 1.0.0 / jni_flutter: 1.0.1`（缓存里已有的可用组合），`flutter pub get --offline`；**lock 只动 3 条**（jni / jni_flutter / 移除 jni_util） |
| 验证 | 同一台机器、同一结构 APK，pin 之后**启动正常**（pid 存活、首页渲染）✅ |
| 说明 | 已装机的 v0.7.16 能跑，但**今天从仓库现打的包必崩** —— 以后出包必须带这个 pin |

#### 阻塞 ②（**功能级，已修**）：`file_picker` 的选图在 release 包里"点了没反应"

| 项 | 内容 |
|---|---|
| 现象 | 点「从相册选一张」/「导入账单 → 选择文件」**什么都不发生**：没有系统选择器、没有 SnackBar、logcat 里连 `ActivityTaskManager: START` 都没有 |
| 范围 | 同一个 APK 里**两个页面都失效** → 不是新功能的 bug，是插件的 |
| 定位 | `file_picker 12` 的选图走 `android_file_picker` 的 `MethodChannel('miguelruivo.flutter.plugins.filepicker')`，`pickFile()` 直接返回 null（异常被吞），系统 Activity 根本没被拉起 |
| 修法 | **把选图收进自己的通道**：`yanxin/ocr` 增加 `pickImage` → Android 13+ 用系统 **Photo Picker**（`MediaStore.ACTION_PICK_IMAGES`），老系统退 `ACTION_OPEN_DOCUMENT`；选中的 `content://` 复制到 `cacheDir/receipt/` 再交给 ML Kit。**零权限、完全离线** |
| 验证 | 真机点「从相册选一张」→ 系统 Photo Picker 正常弹出（截图）→ 选中后返回路径 → OCR 链路跑起来 ✅ |

> 附带收益：截图记账这条链路现在**完全不依赖 `file_picker`**（导入账单页仍用它，属遗留问题，记录在案）。

#### 已在真机确认的事实

| 项 | 实测值 |
|---|---|
| release 包体积 | **61.6 MB**（debug 201.7 MB） |
| ABI | **`arm64-v8a` + `armeabi-v7a`**（x86_64 已按 §9.7 裁掉）✅ |
| 权限 | 只有 `POST_NOTIFICATIONS` + `RECEIVE_BOOT_COMPLETED`（+AndroidX 自动项）→ **无 `INTERNET`** ✅ |
| ML Kit 资产 | `libmlkit_google_ocr_pipeline.so` arm64 10.5 MB / v7a 6.5 MB；模型 2.4 MB ✅ |
| 启动 | 修掉阻塞 ① 后**正常启动**，首页（深色主题）渲染正常 ✅ |
| 「我的 → 截图记账」入口 | 出现且可点，三步页第 1 步渲染正常 ✅ |
| 选图（自建通道） | 系统 Photo Picker 弹出并返回路径 ✅ |
| 选图失败的 UX | 选中一张已被删除的图 → 页面显示「图片读不到了，换一张试试」，**不崩、不写库** ✅ |
| 装机方式 | 用 `qaAppId` 出**并列的第二个 App**（`com.teacodeman.yanxin.qa`）→ **不覆盖用户正式包、账本零风险** |

> ⚠️ 用户手机上那份 v0.7.16 带**真实账本**（versionCode 4001 > 2001，签名也不同），
> 本轮**没有**对它 `adb install -r`（不是降级失败就是卸载丢数据）。
> `android/app/build.gradle.kts` 因此留了一个口子：
> `ORG_GRADLE_PROJECT_qaAppId=…` 或 `android/gradle.properties` 里写 `qaAppId=…` 即可换包名出 QA 包。

#### 阻塞 ③（**真正的"识别不了"根因，已修**）：release 包的 R8 把 ML Kit 裁坏

| 项 | 内容 |
|---|---|
| 现象 | 选图成功、OCR 立刻抛 `NullPointerException: … Object.getClass() on a null object reference`（栈里是 `r51.<init>` / `b61.a` / `rg0.b` 这些 ML Kit 内部混淆类）→ 页面报「识别失败了，换一张或者手动记一笔」 |
| 关键对比 | **同一张图、同一个 APK 结构**：`--debug` 包识别正常（30 行 / 375 ms），`--release` 包必崩 → 与 OCR 代码无关 |
| 根因 | Flutter 的 release 构建**默认开 R8**（`build/app/outputs/mapping/release/mapping.txt` 存在即证明跑过），R8 把 ML Kit 内部依赖的组件/泛型签名裁掉 → `MlKitContext` 一类的空引用 |
| 修法 | `android/app/build.gradle.kts` 的 `release { isMinifyEnabled = false; isShrinkResources = false }`（与 debug 行为一致） |
| 代价 | release APK 61.6 MB → **64.6 MB**（+3 MB）。要将来的瘦身，正确做法是加 ML Kit 的 keep 规则再测，**别直接开回来** |
| 验证 | 关掉 R8 后 release 包真机识别正常：**30 行 / 191 ms**，字段全对 |

> 这次是"**同一张截图 debug 能识别、release 不能**"，排查顺序值得记：
> ① 先用「探针入口」（`tool/ocr_probe_main.dart`，启动即跑 OCR 并打日志）绕开 UI，确认 OCR/解析本身没问题；
> ② 再用同一个探针出 **release 版**，复现 NPE → 锁定构建配置。

#### 真机走查结果（Redmi K50 / Android 14 · 2026-10-24 20:30–20:40）

用户提供的截图：微信「交易详情」`-22.98 / 美团 / 支付成功 / 2026年10月24日 16:28:57`。

| # | 用例 | 结果 |
|---|---|---|
| 1 | 我的 → 截图记账 → 从相册选一张 → 选图 | ✅ 系统 Photo Picker 弹出并返回（卡片缩略图正常） |
| 2 | 核对页字段 | ✅ 微信支付 · 交易成功 · **¥22.98** · 分类**餐饮** · 日期 **2026-10-24 16:28** · 账户 现金（账本里没有 wechat 类型账户时的默认值）· 识别依据「独立行」· **121–191 ms** |
| 3 | 确认记账 → 结果页 | ✅ 「已记账 · 支出 ¥22.98 · 2026-10-24 16:28」 |
| 4 | 回首页 | ✅ 本月支出 ¥22.98；账单列表出现「餐饮 美团 −22.98」 |
| 5 | 同一张图再走一遍 | ✅ 「这笔之前已经记过了 · ¥22.98，没有重复入账」，账本仍只有 1 笔 |
| 6 | 离线性 | ✅ 全程 **Wi-Fi 关闭**（`Wi-Fi is disabled`）完成识别与入账；release 包无 `INTERNET` 权限 |
| 7 | 选到已删除的图 | ✅ 「图片读不到了，换一张试试」，不崩不写库 |

> 走查期间发现的小坑（对后续自动化有影响）：`adb shell input tap` 在这一页上**按 uiautomator 给的语义中心点会打偏**
> （语义节点是整个卡片，不是那颗胶囊按钮），必须在 y≈640–780 之间扫一遍才命中；
> 另外手机同时被用户使用时，事件会落到前台别的 App 上。

### 9.9 顺手迁移：「导入账单」页也不再依赖 `file_picker`

同一个根因（`file_picker` 在 release 包里点不出系统选择器）也影响「我的 → 导入账单 → 选择文件」。
本轮把它一并换成本地通道：

- 原生 `yanxin/ocr` 增加 **`pickDocument`**：`ACTION_OPEN_DOCUMENT`（SAF），MIME 给全
  （`text/csv` / `xlsx` / `zip` / `octet-stream` —— 微信导出是 xlsx（zip）、支付宝 CSV 常被报成
  `octet-stream`，只写 `text/csv` 会让文件在部分 ROM 上置灰）。
- Dart 抽出 `lib/core/platform/media_picker.dart`（`MediaPicker.pickImage / pickDocument` + `mediaPickerProvider`），
  截图记账与导入页共用；选中的文件由原生复制进 `cacheDir/{receipt,import}/`，**按 MIME / 原文件名保留后缀**。
- 真机验证：SAF 正常弹出 → 选一个真实 xlsx → 字节读入 → 解析器给出可读的「缺少必需列…」提示
  （该文件是第三方记账 App 的导出，不是微信/支付宝账单，**拒收是正确行为**）。
- 遗留：**没有**回归「真实微信/支付宝账单文件」的完整导入（解析与预览由 135 例导入测试覆盖）。

### 9.10 下一步（等确认）

1. 走查已完成（§9.8），**剩下一个未覆盖项**：支付失败截图的真机用例（单元测试已覆盖，但没有真实"失败"截图样本）。
2. 已回写：CHANGELOG（`v0.8.1`）+ tag + HANDOFF / README / RESUME 版本。
3. 然后进阶段二（本地问答）：先做 §4.2 的「设备 × 模型」基准表，再定模型。→ **已做，见 §10**。

---

## 10. 阶段二任务 1 实施记录（2026-10-25 交付）：设备 × 模型基准

> 完整报告：[`docs/dev/llm-benchmark.md`](../dev/llm-benchmark.md)。
> 本节只记「做了什么 / 实测结论 / 对架构的决定性影响 / 没做什么」。

### 10.1 交付物（3 个脚本 + 1 份报告，**零产品代码、零 pub 依赖、schema 仍 v3**）

| 文件 | 作用 |
|---|---|
| `tool/llm_bench/bench_android.cpp` | 端上探针：调 llama.cpp C API，逐轮打印 `冷加载 / prompt·gen 耗时 / ttft / pp·tg tok/s / VmRSS / VmHWM / 频率`（`KEY=value` 行） |
| `tool/llm_bench/build_android.ps1` | NDK 28.2 交叉编译 llama.cpp（`b7050`）为 arm64 库 + 编探针；支持 `-ArmArch`（dotprod）与 `-OutDir` |
| `tool/llm_bench/run_bench.ps1` | 推探针/模型（按字节数跳过）→ 跑 → 主机侧每 15 s 采电池温度与大小核频率 → 直接输出 markdown 行 |
| `tool/llm_bench/prompts_finance.txt` | 8 段中文财报问答（173–177 token），逐轮轮换，测的是「真实上下文长度」下的表现 |

源码与产物都在**库外** `D:\yanxin-llm-bench`（llama.cpp 克隆、3 个 gguf、两个 build 目录）——
仓库在中文路径下（NDK/ninja 风险），且这些有 1–2 GB，不该进版本库。

### 10.2 实测结论（Redmi K50 / MT6895 / Android 14）

| 模型 | 文件 | 冷加载 | 首 token | pp tok/s | tg tok/s | 峰值 RSS | 10 轮后 RSS |
|---|---|---|---|---|---|---|---|
| **Qwen2.5-1.5B-Instruct Q4_K_M** | 1066 MB | 1.70 s | 5.07 s | 36.4 | **7.4** | 1185 MB | 1184 MB |
| Qwen3-1.7B Q4_K_M | 1056 MB | 1.63 s | 5.66 s | 32.2 | 6.6 | 1350 MB | 1348 MB |
| Gemma-3-1B-it Q4_K_M | 769 MB | 1.19 s | 3.51 s | 50.4 | 8.8 | 885 MB | 883 MB |

三条从数字里直接读出来的事实：

1. **首 token ≈ 28 ms / token 上下文**：177 token 要 5 s，60 token 只要 1.7 s
   → 产品上「上下文 ≤80 token」是能不能叫「秒回」的分水岭；
2. **生成 ≈ 7.4 tok/s ≈ 2 个汉字/秒**：够写一段解释，**不够聊天**；
3. **RSS 10 轮完全平**（1184 MB ×10）：没有逐轮泄漏，但 1.2 GB 常驻对 4 GB 机型直接出局。

**20 分钟连续推理**（Qwen2.5-1.5B / dotprod / 4 线程绑大核，共 68 轮）：tg **7.4 → 7.0**（抖动内，**不掉速**）、
大核频率 2.85 → **2.15 GHz（−24%）**、电池温度 37.2 → **38.6 ℃（+1.4 ℃）**、RSS 1183 → 1038 MB。
⇒ 降频存在但**吞吐不变**，因为生成受**内存带宽**约束（这也解释了 §10.3 里 dotprod 只提速预填）。
产品上不必为「跑久了变慢」做降级，要防的是**内存**与**上下文长度**。

### 10.3 两条工程开关（影响远超模型选择本身）

| 开关 | 实测差 | 结论 |
|---|---|---|
| 编译 `-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod` | pp **24.8 → 36.4（+47%）**，tg 不变 | 必须开；但 ≤A72 老机会 SIGILL → 阶段四要么多变体运行时挑选，要么按机型分档 |
| worker 线程**绑大核**（`taskset f0`） | tg **5.9 → 7.5（+27%）**；开 8 线程 → **3.7（−50%）** | App 里 JNI 必须 `sched_setaffinity` 绑大核，线程数 = 大核数 |

### 10.4 质量抽查（1 条 prompt × 3 模型，人工看）

- **Qwen2.5-1.5B**：超支额 **算对**（520.36），但「剩余每天最多花 141.21」是**编的**（真实口径应为 0）；
- **Qwen3-1.7B**：默认 `<think>` 把 120 token 预算全吃掉，**没有输出答案**（接它必须先关思考）；
- **Gemma-3-1B**：把「已花 4520.36」说成「超支 4520.36」，还给了「每天最多花 4000」——**中文算数不可靠**。

⇒ 这三条共同证明 SPEC §3.1 的分层是必需的：**数字必须来自 Dart 纯函数，模型只做措辞**，
并且回答里的数字要能对上「事实清单」（阶段二实现时的校验点）。

### 10.5 选型建议（待用户拍板）

1. **引擎**：llama.cpp 自建 JNI（掌控流式 / 取消 / 停止 / 线程亲和 / dotprod 编译开关）；
   MediaPipe `tasks-genai` 只支持 Gemma 系，而 Gemma-3-1B 在本机的中文算数抽查里最差 → 不作为首选。
2. **模型**：**Qwen2.5-1.5B-Instruct Q4_K_M** 为首选（速度/内存/中文三者最均衡）；
   Gemma-3-1B 只作「低端机 / 只求快」的降级候选；Qwen3-1.7B 需先关 thinking 重测才有可比性。
3. **分发（D4）**：仍未拍板（2026-10-25 用户选择「等基准表出来再定」）。
   基准表已出，**现在可以决策**：手动导入 `.gguf`（不加 `INTERNET`，卖点不变）vs App 内下载（改卖点）。

### 10.6 没做什么（如实记录）

| # | 项 | 说明 |
|---|---|---|
| 1 | 只测了 **1 台设备** | SPEC §6 要求「3 模型 × 2 台设备」，第二台（低端机）未测 |
| 2 | 温度是**电池温度代理** | HyperOS 屏蔽 thermal_zone；20 分钟长跑的温升数字偏保守 |
| 3 | 质量抽查只有 **1 条 prompt** | 只够证明「会算错」，不足以排出「谁最准」；正式选型要 20+ 条真实问题集 |
| 4 | 未测 **JSON 约束 / 工具调用** | 阶段三要用 grammar，届时 tok/s 会再变 |
| 5 | 未接进 App | 本轮**零产品代码**：`LlmProvider` 抽象与 JNI 引擎都还没开始 |


