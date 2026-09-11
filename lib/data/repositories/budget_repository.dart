/// 月度预算仓储（schema v2）。
///
/// 一个账本 + 一个月份最多一条有效记录（部分唯一索引 `idx_budget_book_period`）。
/// 设置走「先查后写」而不是 `INSERT OR REPLACE`：
/// - 语义上「重复设置」是**更新**，保留原始 `created_at`；
/// - 与 `importTransaction` 的既有做法一致（不依赖 sqlite 错误消息判重）。
/// 删除 = 软删除（deleted_at 非空），与其它业务表一致。
library;

import 'package:drift/drift.dart';

import '../../core/db/database.dart';
import '../../core/utils/id.dart';

class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  /// 月份 key：`'YYYY-MM'`（零填充，字典序即时序）。
  static String periodOf(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  /// 取某账本某月的预算；未设置返回 null。
  Future<BudgetRow?> getForMonth(String bookId, int year, int month) {
    return (_db.select(_db.budgets)..where(
          (b) =>
              b.bookId.equals(bookId) &
              b.period.equals(periodOf(year, month)) &
              b.deletedAt.isNull(),
        ))
        .getSingleOrNull();
  }

  /// 设置（新增或更新）某账本某月的预算。金额必须是正整数分。
  Future<BudgetRow> setForMonth({
    required String bookId,
    required int year,
    required int month,
    required int amountCents,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', '预算金额必须为正整数（分）');
    }
    if (bookId.isEmpty) {
      throw ArgumentError('bookId 为必填');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await getForMonth(bookId, year, month);
    if (existing != null) {
      await (_db.update(_db.budgets)
            ..where((b) => b.id.equals(existing.id) & b.deletedAt.isNull()))
          .write(
        BudgetsCompanion(
          amountCents: Value(amountCents),
          updatedAt: Value(now),
          dirty: const Value(1),
        ),
      );
      final fresh = await (_db.select(_db.budgets)
            ..where((b) => b.id.equals(existing.id)))
          .getSingle();
      return fresh;
    }
    return _db.into(_db.budgets).insertReturning(
          BudgetsCompanion.insert(
            id: uuidV4(),
            bookId: bookId,
            period: periodOf(year, month),
            amountCents: amountCents,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 清除某账本某月的预算（软删除）。返回受影响行数（0 表示本来就没设）。
  Future<int> clearForMonth(String bookId, int year, int month) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.budgets)
          ..where(
            (b) =>
                b.bookId.equals(bookId) &
                b.period.equals(periodOf(year, month)) &
                b.deletedAt.isNull(),
          ))
        .write(
      BudgetsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(1),
      ),
    );
  }
}
