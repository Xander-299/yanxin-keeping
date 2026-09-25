/// 新手引导（F7.14）的持久化键 —— 落在**既有** `schema_meta` KV 表上。
///
/// 与 `active_book_id`（`book_repository.dart`）/ `search_history`（`search_history.dart`）
/// 同表：一行键值即可，**不值得为它动 schema**（DB 仍 schemaVersion 3）。
library;

/// 「引导已看过」标记。**不存在** = 从未看过。
///
/// 写入时机：引导页被关闭时（跳过 / 完成 / 系统返回三条路径都走 `dispose` → 一处收口）。
/// 只有**全新安装**且未看过时才自动弹（判定见 `onboardingPromptProvider`）。
const String kOnboardingDoneKey = 'onboarding_done';

/// 标记值。用非空字符串而不是 `''`，这样判「看过」只需 `get(key) != null`。
const String kOnboardingDoneValue = '1';
