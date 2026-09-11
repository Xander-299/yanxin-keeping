/// 统计页状态：当前账本 + 当前月份 + 收支方向 + 分类占比 + 近 N 月趋势。
///
/// 与首页 `ledgerProvider`、日历 `calendarProvider` 一样**独立记月份**：
/// 统计页翻月不该带走首页/日历的月份。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';

import 'stats_aggregate.dart';

/// 统计页状态快照。
class StatsState {
  const StatsState({
    required this.bookId,
    required this.year,
    required this.month,
    required this.kind,
    required this.items,
    required this.trendRows,
    required this.categoryNames,
  });

  final String bookId;

  final int year;

  /// 1-12。
  final int month;

  /// 当前统计方向：`expense`（支出）/ `income`（收入）。
  final String kind;

  /// 当月流水（发生时间倒序）。
  final List<TxRow> items;

  /// 趋势区间内的全部流水（近 [kTrendMonths] 个月，可能跨年）。
  final List<TxRow> trendRows;

  /// 分类 id → 名称（当月流水里的分类才用得上）。
  final Map<String, String> categoryNames;

  /// 当月收支汇总。
  MonthSummary get summary => summarize(items);

  /// 当前方向的分类占比（降序）。
  List<CategorySlice> get slices => categoryBreakdown(
    items,
    type: kind,
    nameOf: (String? id) => (id == null ? null : categoryNames[id]) ?? '未分类',
  );

  /// 近 [kTrendMonths] 个月的收支趋势（时间升序）。
  List<MonthPoint> get trend => monthlyTrend(
    year: year,
    month: month,
    months: kTrendMonths,
    rows: trendRows,
  );

  /// 当前方向该月的合计（分）。
  int get kindTotalCents =>
      kind == 'income' ? summary.incomeCents : summary.expenseCents;

  StatsState copyWith({String? kind}) => StatsState(
    bookId: bookId,
    year: year,
    month: month,
    kind: kind ?? this.kind,
    items: items,
    trendRows: trendRows,
    categoryNames: categoryNames,
  );
}

/// 统计页 controller。
final statsProvider = AsyncNotifierProvider<StatsController, StatsState>(
  StatsController.new,
);

class StatsController extends AsyncNotifier<StatsState> {
  @override
  Future<StatsState> build() async {
    final bookId = await ref.watch(activeBookIdProvider.future);
    if (bookId == null) {
      throw StateError('当前账本未就绪');
    }
    final now = DateTime.now();
    return _load(bookId, now.year, now.month);
  }

  Future<StatsState> _load(String bookId, int year, int month) async {
    final repo = ref.read(transactionRepositoryProvider);
    final categories = await ref.watch(categoriesProvider.future);
    final range = trendRange(year, month, kTrendMonths);
    final items = await repo.listByMonth(bookId, year, month);
    final trendRows = await repo.listByRange(bookId, range.start, range.end);
    return StatsState(
      bookId: bookId,
      year: year,
      month: month,
      kind: 'expense',
      items: items,
      trendRows: trendRows,
      categoryNames: <String, String>{
        for (final c in categories) c.id: c.name,
      },
    );
  }

  Future<void> _reload(String bookId, int year, int month) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(bookId, year, month));
  }

  /// 翻月：delta = -1 上一月，+1 下一月（调用方先判 `canGoNext`）。
  Future<void> shiftMonth(int delta) async {
    final current = state.value;
    if (current == null) return;
    var y = current.year;
    var m = current.month + delta;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    await _reload(current.bookId, y, m);
  }

  /// 切换统计方向（支出 / 收入），不重新查库。
  void setKind(String kind) {
    final current = state.value;
    if (current == null || current.kind == kind) return;
    state = AsyncData(current.copyWith(kind: kind));
  }

  /// 重新加载当前账本当前月（记一笔/导入后刷新用）。
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    await _reload(current.bookId, current.year, current.month);
  }
}
