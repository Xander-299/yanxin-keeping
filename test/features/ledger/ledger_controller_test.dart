/// LedgerController 单测：jumpToMonth（导入账单后跳到数据所在月用）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';

import '../../helpers/test_database.dart';

void main() {
  // 回归：首次使用验收 P1 —— 导入的历史账单所在月早于当前月，首页必须能
  // 直接跳过去，否则用户看不到导入结果。
  test('jumpToMonth 切到指定年月，且不受当前月限制', () async {
    final db = openTestDatabase();
    final book = await BookRepository(db).ensureDefaultBook();
    addTearDown(db.close);

    // Riverpod 3 未公开导出 Override 类型 → 不能写 <Override>[...] 注解
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final initial = await container.read(ledgerProvider.future);
    expect(initial.bookId, book.id);
    final now = DateTime.now();
    expect(initial.year, now.year);
    expect(initial.month, now.month);

    await container.read(ledgerProvider.notifier).jumpToMonth(2026, 8);
    final jumped = container.read(ledgerProvider).value;
    expect(jumped, isNotNull);
    expect(jumped!.year, 2026);
    expect(jumped.month, 8);
    expect(jumped.bookId, book.id);

    // jump 之后仍可继续用 shiftMonth 翻月
    await container.read(ledgerProvider.notifier).shiftMonth(-1);
    final shifted = container.read(ledgerProvider).value;
    expect(shifted!.year, 2026);
    expect(shifted.month, 7);
  });
}
