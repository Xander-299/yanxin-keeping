/// 测试用分类种子：**优先取已有分类，没有才建**。
///
/// 背景：schema v4 起，同一账本 + 同一收支 + 同一父级下**不允许重名**（任务书 §4）。
/// 而 `BookRepository.create()` 会自动写入 11 个支出 + 7 个收入预置分类 —— 测试里再
/// `create(name: '餐饮')` 就会撞上预置的「餐饮」。所以统一走这里拿分类。
library;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

/// 取名为 [name] 的分类；不存在才创建（一级分类）。
Future<Category> ensureCategory(
  CategoryRepository repo,
  String bookId,
  String name, {
  String kind = 'expense',
  String icon = '',
  String color = '',
}) async {
  for (final Category c in await repo.listByBook(bookId, kind: kind)) {
    if (c.name == name && c.parentId == null) return c;
  }
  return repo.create(
    bookId: bookId,
    name: name,
    kind: kind,
    icon: icon,
    color: color,
  );
}
