/// 统计页聚合（纯函数，便于单测）。
///
/// 两块内容都只依赖「一批流水」，不碰数据库：
/// - 分类占比：某月支出/收入按分类汇总、降序、算占比（占比仅用于绘制圆环，不参与金额）
/// - 月度趋势：近 N 个月的收支对照，缺月补 0
library;

import 'package:yanxin/core/db/database.dart';

/// 趋势默认展示的月数（含当月）。
const int kTrendMonths = 6;

/// 分类占比的一块（饼图的一瓣 + 图例的一行）。
class CategorySlice {
  const CategorySlice({
    required this.id,
    required this.name,
    required this.cents,
    required this.ratio,
  });

  /// 分类 id；null 表示流水没有分类（未分类）。
  final String? id;

  /// 分类名（未分类时为空串，展示层再兜底）。
  final String name;

  /// 该分类合计（分，恒 >= 0）。
  final int cents;

  /// 占该方向总额的比例 0..1；总额为 0 时为 0。
  final double ratio;

  String get percentText => '${(ratio * 100).toStringAsFixed(1)}%';
}

/// 月度趋势的一个点。
class MonthPoint {
  const MonthPoint({
    required this.year,
    required this.month,
    required this.incomeCents,
    required this.expenseCents,
  });

  final int year;

  /// 1-12。
  final int month;

  /// 该月收入（分）。
  final int incomeCents;

  /// 该月支出（分）。
  final int expenseCents;

  /// 柱下方标签：同年只显示「9月」，跨年带年份「25年12月」。
  String labelOf(int anchorYear) =>
      year == anchorYear ? '$month月' : '${year % 100}年$month月';
}

String _fallbackName(String? id) => '未分类';

/// 按分类汇总某方向（expense / income）的流水，按金额降序。
///
/// transfer 不计收支（type 永远不等于 expense/income，天然被排除）。
/// 无分类的流水归到「未分类」；[nameOf] 由调用方注入分类名映射，
/// 查询不到名字时也归到「未分类」。
List<CategorySlice> categoryBreakdown(
  List<TxRow> items, {
  required String type,
  String Function(String? id) nameOf = _fallbackName,
}) {
  final totals = <String?, int>{};
  var sum = 0;
  for (final t in items) {
    if (t.type != type) continue;
    totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amountCents;
    sum += t.amountCents;
  }
  final entries = totals.entries.toList()
    ..sort((MapEntry<String?, int> a, MapEntry<String?, int> b) {
      final byAmount = b.value.compareTo(a.value);
      return byAmount != 0 ? byAmount : (a.key ?? '').compareTo(b.key ?? '');
    });
  return <CategorySlice>[
    for (final e in entries)
      CategorySlice(
        id: e.key,
        name: e.key == null ? '未分类' : nameOf(e.key),
        cents: e.value,
        ratio: sum == 0 ? 0 : e.value / sum,
      ),
  ];
}

/// 趋势区间的起止毫秒（左闭右开 [start, end)），含 [year]-[month] 当月、往前 [months] 个月。
///
/// 例：2026-02、months=6 → 2025-09-01 .. 2026-03-01。
({int start, int end}) trendRange(int year, int month, int months) {
  final end = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
  final startIndex = year * 12 + (month - 1) - (months - 1);
  final sy = startIndex ~/ 12;
  final sm = startIndex % 12 + 1;
  return (start: DateTime(sy, sm, 1).millisecondsSinceEpoch, end: end);
}

/// 由区间内流水生成按月趋势（时间升序，缺月补 0）。
///
/// [rows] 应覆盖 [trendRange] 给出的整个区间（统计页用 `listByRange` 一次取齐），
/// 区间外的流水会被忽略，保证柱子数量恒为 [months]。
List<MonthPoint> monthlyTrend({
  required int year,
  required int month,
  required int months,
  required List<TxRow> rows,
}) {
  final income = <int, int>{};
  final expense = <int, int>{};
  for (final t in rows) {
    final d = DateTime.fromMillisecondsSinceEpoch(t.occurredAt);
    final key = d.year * 12 + (d.month - 1);
    if (t.type == 'income') {
      income[key] = (income[key] ?? 0) + t.amountCents;
    } else if (t.type == 'expense') {
      expense[key] = (expense[key] ?? 0) + t.amountCents;
    }
  }
  final firstIndex = year * 12 + (month - 1) - (months - 1);
  return <MonthPoint>[
    for (var i = 0; i < months; i++)
      MonthPoint(
        year: (firstIndex + i) ~/ 12,
        month: (firstIndex + i) % 12 + 1,
        incomeCents: income[firstIndex + i] ?? 0,
        expenseCents: expense[firstIndex + i] ?? 0,
      ),
  ];
}
