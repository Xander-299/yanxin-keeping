/// 分类相关的应用状态：当前账本的分类树（含归档）。
///
/// 两个口径要分清：
/// - [categoriesProvider]：**含归档** —— 历史账单、统计、报表、搜索都要靠它把
///   `category_id` 解析成名字/图标，归档的分类绝不能在这里消失；
/// - [categoriesByKindProvider] / 记账页选择器：**排除归档** —— 归档分类不能再用于新账单。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'book_providers.dart';
import 'database.dart';

/// 当前账本下全部未删除分类（**含归档**）。
///
/// 读之前先 `ensurePresets`：老账本升级到 schema v4 后，缺的预置分类在这里幂等补上。
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final bookId = await ref.watch(activeBookIdProvider.future);
  if (bookId == null) return <Category>[];
  final repo = ref.watch(categoryRepositoryProvider);
  await repo.ensurePresets(bookId);
  return repo.listByBook(bookId);
});

/// 按 kind 过滤、**排除归档**的分类（供记一笔页切换支出/收入、导入映射用）。
final categoriesByKindProvider = FutureProvider.family<List<Category>, String>((
  ref,
  String kind,
) async {
  final all = await ref.watch(categoriesProvider.future);
  return all
      .where((Category c) => c.kind == kind && c.isArchived == 0)
      .toList();
});

/// 分类的展示名：二级分类显示成「父 · 子」，一级/找不到显示原名。
///
/// 统计、报表、搜索结果都用它 —— 这样二级分类不会和别的同名分类混在一起。
String categoryDisplayName(
  Category category,
  Map<String, Category> byId, {
  String separator = ' · ',
}) {
  final String? parentId = category.parentId;
  if (parentId == null) return category.name;
  final Category? parent = byId[parentId];
  return parent == null
      ? category.name
      : '${parent.name}$separator${category.name}';
}

/// `{id: 展示名}` 映射（二级分类带父级前缀）。
///
/// **只给「展示」用**：统计切片、报表行的标签。搜索/问答仍用 `category.name`，
/// 因为那边是拿名字做匹配逻辑，加前缀会改变语义。
Map<String, String> categoryNameMap(Iterable<Category> categories) {
  final Map<String, Category> byId = <String, Category>{
    for (final Category c in categories) c.id: c,
  };
  return <String, String>{
    for (final Category c in categories) c.id: categoryDisplayName(c, byId),
  };
}
