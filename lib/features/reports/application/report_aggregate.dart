/// 报表聚合（纯函数，便于单测）。
///
/// 三档口径（见 `docs/SPEC-F7.7-backlog.md` §A.3）：
/// - 明细：按**本地日**倒序分组（复用 `groupByDay`），组头带笔数与当日支出合计
/// - 分类：同一「方向」内按分类名聚合，金额降序；transfer 单列
/// - 账户：按 `account_id` 聚合，每行给出 支出 / 收入 / 转账 / 笔数
///
/// 金额一律整数分，不做浮点运算。
library;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/utils/date.dart';

/// 展开子列表时一次最多渲染的流水行数（与搜索浮层同一量级）。
const int kReportDetailLimit = 200;

/// 支出 / 收入 / 转账三个 type 值（与表定义一致）。
const String kReportExpense = 'expense';
const String kReportIncome = 'income';
const String kReportTransfer = 'transfer';

/// 已软删 / 查不到名字的账户统一归到这一组。
const String kOtherAccountKey = '__other__';

/// 该组的展示名。
const String kOtherAccountTitle = '其他账户';

/// 未分类行的展示名（与统计页口径一致）。
const String kUncategorized = '未分类';

/// 报表里的一组（分类 / 账户各一组；明细的「日」不走这里）。
class ReportGroup {
  const ReportGroup({
    required this.key,
    required this.title,
    required this.items,
    required this.expenseCents,
    required this.incomeCents,
    required this.transferCents,
  });

  /// 稳定标识：分类档 = 展示名，账户档 = accountId（其他账户为 [kOtherAccountKey]）。
  final String key;

  /// 展示名。
  final String title;

  /// 组内流水（保持入参顺序：发生时间倒序）。
  final List<TxRow> items;

  /// 组内支出合计（分）。
  final int expenseCents;

  /// 组内收入合计（分）。
  final int incomeCents;

  /// 组内转账合计（分）。
  final int transferCents;

  /// 组内笔数。
  int get txCount => items.length;

  /// 排序 / 占比用的合计（分）。分类档只有一个方向非 0；账户档为三者之和。
  int get totalCents => expenseCents + incomeCents + transferCents;
}

/// 一组流水的三向合计。
({int expense, int income, int transfer}) _sumsOf(List<TxRow> items) {
  var expense = 0;
  var income = 0;
  var transfer = 0;
  for (final TxRow t in items) {
    if (t.type == kReportExpense) {
      expense += t.amountCents;
    } else if (t.type == kReportIncome) {
      income += t.amountCents;
    } else if (t.type == kReportTransfer) {
      transfer += t.amountCents;
    }
  }
  return (expense: expense, income: income, transfer: transfer);
}

ReportGroup _build(String key, String title, List<TxRow> items) {
  final s = _sumsOf(items);
  return ReportGroup(
    key: key,
    title: title,
    items: items,
    expenseCents: s.expense,
    incomeCents: s.income,
    transferCents: s.transfer,
  );
}

/// 金额降序；金额相同按 key 升序（保证渲染顺序稳定，不依赖 Map 迭代顺序）。
void _sortByTotal(List<ReportGroup> groups) {
  groups.sort((ReportGroup a, ReportGroup b) {
    final int byAmount = b.totalCents.compareTo(a.totalCents);
    return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
  });
}

/// 按分类聚合某一方向（[type] = expense / income）的流水。
///
/// 与统计页 `categoryBreakdown` 同一口径：只取该方向的流水，
/// 分类名为空或查不到名字都归到「未分类」并**合并成一行**。
List<ReportGroup> groupByCategory(
  List<TxRow> items, {
  required String type,
  required String Function(String?) nameOf,
}) {
  final byTitle = <String, List<TxRow>>{};
  for (final TxRow t in items) {
    if (t.type != type) continue;
    final String raw = t.categoryId == null ? '' : nameOf(t.categoryId);
    final String title = raw.trim().isEmpty ? kUncategorized : raw;
    (byTitle[title] ??= <TxRow>[]).add(t);
  }
  final groups = <ReportGroup>[
    for (final MapEntry<String, List<TxRow>> e in byTitle.entries)
      _build(e.key, e.key, e.value),
  ];
  _sortByTotal(groups);
  return groups;
}

/// 按账户聚合该月全部流水（支出 / 收入 / 转账三向都算）。
///
/// [knownAccountIds] 传当前账本**未软删**的账户 id 集合；
/// 不在集合内（已软删 / 空串 / 脏数据）的流水归到「其他账户」。
List<ReportGroup> groupByAccount(
  List<TxRow> items, {
  required Set<String> knownAccountIds,
  required String Function(String) nameOf,
}) {
  final byKey = <String, List<TxRow>>{};
  for (final TxRow t in items) {
    final bool known = t.accountId.isNotEmpty && knownAccountIds.contains(t.accountId);
    final String key = known ? t.accountId : kOtherAccountKey;
    (byKey[key] ??= <TxRow>[]).add(t);
  }
  final groups = <ReportGroup>[
    for (final MapEntry<String, List<TxRow>> e in byKey.entries)
      _build(
        e.key,
        e.key == kOtherAccountKey ? kOtherAccountTitle : nameOf(e.key),
        e.value,
      ),
  ];
  _sortByTotal(groups);
  return groups;
}

/// 该月转账流水（分类档单列一段用）。
List<TxRow> transferRows(List<TxRow> items) => <TxRow>[
  for (final TxRow t in items)
    if (t.type == kReportTransfer) t,
];

/// 一段时间内某方向的合计（分）。明细档组头「支出 ¥x」用。
int sumCentsOf(List<TxRow> items, String type) {
  var sum = 0;
  for (final TxRow t in items) {
    if (t.type == type) sum += t.amountCents;
  }
  return sum;
}

/// 明细档组头标签：`今天 9月23日 周三` / `昨天 9月22日 周二` / `9月8日 周一`。
///
/// 与日历页选中日的表头格式化**逐字一致**（跨年带年份），便于用户两边对上。
/// [now] 仅供测试注入「今天」，默认取系统时间。
String reportDayLabel(int ms, {int? now}) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  final DateTime n = DateTime.fromMillisecondsSinceEpoch(
    now ?? DateTime.now().millisecondsSinceEpoch,
  );
  final String core = '${d.month}月${d.day}日 ${weekdayLabel(d)}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return '今天 $core';
  }
  final DateTime y = DateTime(n.year, n.month, n.day - 1);
  if (d.year == y.year && d.month == y.month && d.day == y.day) {
    return '昨天 $core';
  }
  return d.year == n.year ? core : '${d.year}年$core';
}
