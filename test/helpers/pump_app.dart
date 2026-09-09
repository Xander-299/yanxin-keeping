/// 测试基建：用内存 drift 库替换真实数据库，整条 provider 链路不变。
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/app.dart';
import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/database.dart';

/// 打开一个内存库（每用例独立，互不污染）。
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());

/// 用内存库启动完整 App（含 go_router）。
Future<void> pumpApp(WidgetTester tester, {AppDatabase? database}) async {
  final db = database ?? openTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 未公开导出 Override 类型，这里不写类型注解
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const YanxinApp(),
    ),
  );
  await tester.pumpAndSettle();
}
