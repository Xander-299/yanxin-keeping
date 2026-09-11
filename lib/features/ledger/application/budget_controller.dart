/// 首页「本月预算」状态。
///
/// 预算按「账本 + 年月」存，但**不自己记月份**：直接 watch 首页的
/// [ledgerProvider]，首页翻月 / 换账本时自动跟着重查，永远与卡片上显示的月份一致
/// （避免首页和日历 / 统计那样各记一份月份、再靠人工同步刷新）。
///
/// 页面上的「已消费」「日均」都来自首页已加载的流水，不走本 provider，
/// 所以记一笔 / 删一笔后卡片数字会随首页刷新自动更新，无需额外接线。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database.dart';
import 'ledger_controller.dart';

/// 当前首页月份（账本 + 年月）的预算金额（分）；未设置为 null。
final monthBudgetProvider = AsyncNotifierProvider<MonthBudgetController, int?>(
  MonthBudgetController.new,
);

class MonthBudgetController extends AsyncNotifier<int?> {
  @override
  Future<int?> build() async {
    final ledger = await ref.watch(ledgerProvider.future);
    final row = await ref
        .read(budgetRepositoryProvider)
        .getForMonth(ledger.bookId, ledger.year, ledger.month);
    return row?.amountCents;
  }

  /// 设置（新增或更新）当前月份的预算。
  Future<void> setAmount(int amountCents) async {
    final ledger = _requireLedger();
    await ref.read(budgetRepositoryProvider).setForMonth(
          bookId: ledger.bookId,
          year: ledger.year,
          month: ledger.month,
          amountCents: amountCents,
        );
    state = AsyncData(amountCents);
  }

  /// 清除当前月份的预算（软删）。
  Future<void> clear() async {
    final ledger = _requireLedger();
    await ref
        .read(budgetRepositoryProvider)
        .clearForMonth(ledger.bookId, ledger.year, ledger.month);
    state = const AsyncData(null);
  }

  /// 写入前取当前首页月份。store 里的月份是唯一事实来源，不用缓存字段，
  /// 免得弹窗还开着时首页已经翻月，结果写到了别的月份。
  LedgerState _requireLedger() {
    final ledger = ref.read(ledgerProvider).value;
    if (ledger == null) {
      throw StateError('首页月份未就绪，无法设置预算');
    }
    return ledger;
  }
}
