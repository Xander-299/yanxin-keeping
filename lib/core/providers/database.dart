/// 数据层 DI：数据库与 5 个仓储。
///
/// 测试里用 `appDatabaseProvider.overrideWithValue(内存库)` 即可替换整条链路。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../db/database.dart';

/// 应用数据库（进程内单例，App 退出时关闭）。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = openAppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 账本仓储。
final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(ref.watch(appDatabaseProvider)),
);

/// 账户仓储。
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(appDatabaseProvider)),
);

/// 分类仓储。
final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(appDatabaseProvider)),
);

/// 流水仓储。
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(appDatabaseProvider)),
);

/// 月度预算仓储（schema v2）。
final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(appDatabaseProvider)),
);
