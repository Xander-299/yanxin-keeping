/// 资产聚合（纯函数，便于单测）。
///
/// 口径见 `docs/SPEC-F7.5-assets.md` §3.2：
/// 账户余额 = 初始余额 + Σ收入 − Σ支出，**transfer 不计**（方向语义未落库，硬算必错）。
/// 只依赖「一批账户 + 一批流水」，不碰数据库。
library;

import 'package:yanxin/core/db/database.dart';

/// 单个账户的资产视图。
class AssetItem {
  const AssetItem({
    required this.account,
    required this.incomeCents,
    required this.expenseCents,
    required this.txCount,
  });

  final Account account;

  /// 该账户累计收入（分，恒 >= 0）。
  final int incomeCents;

  /// 该账户累计支出（分，恒 >= 0）。
  final int expenseCents;

  /// 该账户下的流水笔数（用于「有流水不许删账户」的拦截）。
  final int txCount;

  /// 初始余额（分）。允许为负（由调用方保证数据合法）。
  int get initialCents => account.initialBalanceCents;

  /// 当前余额（分）：初始 + 收入 − 支出，可为负（透支 / 信用卡）。
  int get balanceCents => initialCents + incomeCents - expenseCents;

  /// 自洽校验用的恒等式：`初始 + 收入 − 支出 == 余额`。
  bool get isConsistent => initialCents + incomeCents - expenseCents == balanceCents;
}

/// 某账本的资产总览。
class AssetSummary {
  const AssetSummary(this.items);

  /// 按账户原有顺序（`sort_order` → `created_at`），**不按余额排序**，避免列表跳动。
  final List<AssetItem> items;

  /// 净资产（分）：各账户余额之和，可为负。
  int get netCents => items.fold(0, (int acc, AssetItem i) => acc + i.balanceCents);

  /// 账户数。
  int get count => items.length;

  /// 按 id 取一项；用于删除前核对流水笔数。
  AssetItem? itemOf(String accountId) {
    for (final AssetItem i in items) {
      if (i.account.id == accountId) return i;
    }
    return null;
  }
}

/// 由「账户 + 流水」生成资产总览。
///
/// [txs] 应只包含未删流水（仓储层已过滤）；transfer 类型被跳过；
/// `accountId` 匹配不上的流水（理论上不该出现）同样被忽略，不污染任何账户。
AssetSummary buildAssetSummary(List<Account> accounts, List<TxRow> txs) {
  final Map<String, int> income = <String, int>{};
  final Map<String, int> expense = <String, int>{};
  final Map<String, int> counts = <String, int>{};

  for (final TxRow t in txs) {
    switch (t.type) {
      case 'income':
        income[t.accountId] = (income[t.accountId] ?? 0) + t.amountCents;
      case 'expense':
        expense[t.accountId] = (expense[t.accountId] ?? 0) + t.amountCents;
      case 'transfer':
        // 不计入任何账户（见 SPEC §7）
        continue;
      default:
        continue;
    }
    counts[t.accountId] = (counts[t.accountId] ?? 0) + 1;
  }

  return AssetSummary(<AssetItem>[
    for (final Account a in accounts)
      AssetItem(
        account: a,
        incomeCents: income[a.id] ?? 0,
        expenseCents: expense[a.id] ?? 0,
        txCount: counts[a.id] ?? 0,
      ),
  ]);
}
