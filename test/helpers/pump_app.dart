/// 测试基建：用内存 drift 库替换真实数据库，整条 provider 链路不变。
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/app.dart';
import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/app_meta_repository.dart';
import 'package:yanxin/features/onboarding/onboarding_keys.dart';

/// 打开一个内存库（每用例独立，互不污染）。
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());

/// 用内存库启动完整 App（含 go_router）。
///
/// [onboardingDone] 默认 `true` = 预写「引导已看过」标记。
/// **这是必须的**：每个内存库对 App 而言都是「全新安装」，不预写就会在首帧后弹出
/// 新手引导并盖住首页，把既有 9 个测试文件全打断（F7.14）。
/// 首启专项用例显式传 `false`。
Future<void> pumpApp(
  WidgetTester tester, {
  AppDatabase? database,
  bool onboardingDone = true,
}) async {
  final db = database ?? openTestDatabase();
  addTearDown(db.close);
  if (onboardingDone) {
    await AppMetaRepository(db).set(kOnboardingDoneKey, kOnboardingDoneValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 未公开导出 Override 类型，这里不写类型注解
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const YanxinApp(),
    ),
  );
  await tester.pumpAndSettle();
}
