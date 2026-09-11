/// 测试用数据库：内存库，每个用例一个实例。
library;

import 'package:drift/native.dart';

import 'package:yanxin/core/db/database.dart';

AppDatabase openTestDatabase() {
  final db = AppDatabase(NativeDatabase.memory());
  return db;
}
