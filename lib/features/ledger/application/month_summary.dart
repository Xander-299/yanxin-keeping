/// 月度收支汇总（纯函数，便于单测）。
///
/// 对应旧栈 `stores/transaction.js` 里的 summary computed：
/// 只统计当前已加载月份的流水（`listByMonth` 已限定月份），transfer 不计收支。
library;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/utils/money.dart';

class MonthSummary {
  const MonthSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.balanceCents,
  });

  /// 本月收入（分）。
  final int incomeCents;

  /// 本月支出（分）。
  final int expenseCents;

  /// 结余 = 收入 - 支出（分）。
  final int balanceCents;

  String get incomeYuan => centsToYuan(incomeCents);

  String get expenseYuan => centsToYuan(expenseCents);

  String get balanceYuan => centsToYuan(balanceCents);
}

/// 汇总一批流水。
MonthSummary summarize(List<TxRow> items) {
  var income = 0;
  var expense = 0;
  for (final t in items) {
    if (t.type == 'income') {
      income += t.amountCents;
    } else if (t.type == 'expense') {
      expense += t.amountCents;
    }
  }
  return MonthSummary(
    incomeCents: income,
    expenseCents: expense,
    balanceCents: income - expense,
  );
}
