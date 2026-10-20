/// 外观模式的应用状态：读 `schema_meta` 的 `theme_mode`，点选即写。
///
/// 与 `onboarding_done`（F7.14）/ `search_history`（F7.7 D 批）同表 —— 一行键值，
/// **不值得为它动 schema**（DB 仍 schemaVersion 3）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/theme/theme_mode.dart';
import 'package:yanxin/data/providers/database.dart';

/// 当前外观模式。**默认 `system`**：键不存在 / 读库失败 / 脏数据都回落跟随系统。
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeController, ToonThemeMode>(
      ThemeModeController.new,
    );

class ThemeModeController extends AsyncNotifier<ToonThemeMode> {
  @override
  Future<ToonThemeMode> build() async {
    try {
      final String? raw = await ref
          .watch(appMetaRepositoryProvider)
          .get(kThemeModeKey);
      return ToonThemeMode.parse(raw);
    } catch (_) {
      // 读库失败不能阻断启动：按默认「跟随系统」走
      return ToonThemeMode.system;
    }
  }

  /// 切换并落库。
  ///
  /// 先切 UI 再写库：写失败时**本次会话仍然生效**（下次冷启动回落旧值），
  /// 不弹错误、不把界面回滚 —— 外观是低风险偏好，打断用户更糟。
  Future<void> select(ToonThemeMode mode) async {
    state = AsyncData<ToonThemeMode>(mode);
    try {
      await ref
          .read(appMetaRepositoryProvider)
          .set(kThemeModeKey, mode.storageValue);
    } catch (_) {
      // 静默：见方法注释
    }
  }
}
