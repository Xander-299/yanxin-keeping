/// 分类相关的应用状态：当前账本的分类列表。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'book_providers.dart';
import 'database.dart';

/// 当前账本下全部未删除分类。
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final bookId = await ref.watch(activeBookIdProvider.future);
  if (bookId == null) return <Category>[];
  return ref.watch(categoryRepositoryProvider).listByBook(bookId);
});

/// 按 kind 过滤后的分类（供记一笔页切换支出/收入）。
final categoriesByKindProvider =
    FutureProvider.family<List<Category>, String>((ref, kind) async {
  final all = await ref.watch(categoriesProvider.future);
  return all.where((c) => c.kind == kind).toList();
});
