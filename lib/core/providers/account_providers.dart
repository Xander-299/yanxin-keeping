/// 账户相关的应用状态：当前账本的账户列表。
///
/// 与 `categoriesProvider` 同构：切换账本时自动重查（watch 了 activeBookIdProvider）。
/// 新增 / 改名 / 软删账户后调用 `ref.invalidate(accountsProvider)` 刷新。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'book_providers.dart';
import 'database.dart';

/// 当前账本下全部未删除账户（按 sortOrder / createdAt 升序，与资产页一致）。
final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final bookId = await ref.watch(activeBookIdProvider.future);
  if (bookId == null) return <Account>[];
  return ref.watch(accountRepositoryProvider).listByBook(bookId);
});
