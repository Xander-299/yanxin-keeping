/// 新手引导（F7.14）：要不要在本次冷启动弹引导？
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/onboarding/onboarding_keys.dart';

/// `true` = 立刻弹出全屏引导。
///
/// **两个条件同时成立**才弹（SPEC-F7.14 §3.1）：
/// 1. `schema_meta` 里没有 `onboarding_done` → 从未看过引导；
/// 2. [ActiveBookIdController.isFreshInstall] → **本次启动前库里没有主账本记录** = 全新安装。
///
/// 条件 2 的判据是 `active_book_id`：该键自 F1 起每次冷启动都会落库，**老用户（含从旧包
/// 覆盖安装上来的）必然有值** → 老用户不弹（用户裁定），只能从「我的 → 新手引导」主动看。
///
/// ⚠️ 不要另找判据（如「表里有没有流水」「账本创建时间」）：全新安装首启也会立刻建
/// 账本 + 现金账户 + 15 预置分类，读完就分不清新老；也不能用「本次是否走了
/// `ensureDefaultBook` 分支」——「当前账本被软删」也会命中该分支，会误判成新装。
final onboardingPromptProvider = FutureProvider<bool>((ref) async {
  final meta = ref.watch(appMetaRepositoryProvider);
  if (await meta.get(kOnboardingDoneKey) != null) return false;
  // 等默认数据链路走完 —— isFreshInstall 就是在那次 build 里定的。
  await ref.watch(activeBookIdProvider.future);
  return ref.read(activeBookIdProvider.notifier).isFreshInstall;
});
