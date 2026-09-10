/// 日历页状态：当前账本 + 当前月份 + 选中日 + 该月流水。
///
/// 与首页的 `ledgerProvider` **刻意分离**：日历翻月/选日不应把首页的月份一起带走，
/// 两个 tab 各自记住自己的位置。数据源同为 `transactionRepositoryProvider.listByMonth`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';

import 'calendar_aggregate.dart';

/// 日历页状态快照。
class CalendarState {
  const CalendarState({
    required this.bookId,
    required this.year,
    required this.month,
    required this.selectedDay,
    required this.items,
  });

  final String bookId;

  final int year;

  /// 1-12。
  final int month;

  /// 选中的「当月第几天」（1-31）。
  final int selectedDay;

  /// 该月全部流水（发生时间倒序）。
  final List<TxRow> items;

  /// 月度汇总（月结余 = 收入 - 支出）。
  MonthSummary get summary => summarize(items);

  /// 按天聚合，供日历格子标注每天的支出/收入。
  Map<int, DayAgg> get byDay => aggregateByDay(items);

  /// 日均支出（分）。当月按已过天数折算。
  int get dailyAvgExpenseCents => dailyAverageExpenseCents(
    expenseCents: summary.expenseCents,
    year: year,
    month: month,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );

  /// 选中日期的流水（当天、倒序）。
  List<TxRow> get selectedItems {
    return items
        .where(
          (TxRow t) =>
              DateTime.fromMillisecondsSinceEpoch(t.occurredAt).day == selectedDay,
        )
        .toList(growable: false);
  }

  /// 选中日期的 0 点毫秒（记一笔默认日期用）。
  int get selectedDayMs =>
      DateTime(year, month, selectedDay).millisecondsSinceEpoch;

  CalendarState copyWith({int? selectedDay}) => CalendarState(
    bookId: bookId,
    year: year,
    month: month,
    selectedDay: selectedDay ?? this.selectedDay,
    items: items,
  );
}

/// 日历页 controller。
final calendarProvider =
    AsyncNotifierProvider<CalendarController, CalendarState>(
      CalendarController.new,
    );

class CalendarController extends AsyncNotifier<CalendarState> {
  @override
  Future<CalendarState> build() async {
    final bookId = await ref.watch(activeBookIdProvider.future);
    if (bookId == null) {
      throw StateError('当前账本未就绪');
    }
    final now = DateTime.now();
    return _load(bookId, now.year, now.month);
  }

  Future<CalendarState> _load(
    String bookId,
    int year,
    int month, {
    int? selectedDay,
  }) async {
    final items = await ref
        .read(transactionRepositoryProvider)
        .listByMonth(bookId, year, month);
    return CalendarState(
      bookId: bookId,
      year: year,
      month: month,
      selectedDay: selectedDay ?? _defaultDay(year, month, items),
      items: items,
    );
  }

  /// 默认选中日：当月 → 今天；其他月 → 该月最后一个有账的日子；都没有 → 1 号。
  int _defaultDay(int year, int month, List<TxRow> items) {
    final now = DateTime.now();
    if (year == now.year && month == now.month) return now.day;
    if (items.isEmpty) return 1;
    var maxDay = 1;
    for (final t in items) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.occurredAt).day;
      if (d > maxDay) maxDay = d;
    }
    return maxDay;
  }

  Future<void> _reload(String bookId, int year, int month, {int? selectedDay}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(bookId, year, month, selectedDay: selectedDay),
    );
  }

  /// 选中某一天（只改选中态，不重新查库）。
  void selectDay(int day) {
    final current = state.value;
    if (current == null) return;
    if (current.selectedDay == day) return;
    state = AsyncData(current.copyWith(selectedDay: day));
  }

  /// 翻月：delta = -1 上一月，+1 下一月。
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

  /// 直接跳到指定年月（月份选择子页用），可同时指定选中日。
  Future<void> jumpTo(int year, int month, {int? day}) async {
    final current = state.value ?? await future;
    await _reload(current.bookId, year, month, selectedDay: day);
  }

  /// 重新加载当前账本当前月（记一笔保存后刷新用）。
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    await _reload(
      current.bookId,
      current.year,
      current.month,
      selectedDay: current.selectedDay,
    );
  }

  /// 软删除一笔并刷新（不物理删，DB 里 deleted_at 非空）。
  Future<void> removeTx(String id) async {
    await ref.read(transactionRepositoryProvider).softDelete(id);
    await refresh();
  }
}

/// 某一年里「每个月有账的日期集合」：`{月: {日, ...}}`。
///
/// 供月份选择子页在缩略图上标出有账的日期。一次查全年，避免 12 次查询。
final yearDayIndexProvider =
    FutureProvider.family<Map<int, Set<int>>, int>((ref, int year) async {
      final bookId = await ref.watch(activeBookIdProvider.future);
      if (bookId == null) return const <int, Set<int>>{};
      final rows = await ref
          .watch(transactionRepositoryProvider)
          .listByYear(bookId, year);
      final map = <int, Set<int>>{};
      for (final r in rows) {
        final d = DateTime.fromMillisecondsSinceEpoch(r.occurredAt);
        (map[d.month] ??= <int>{}).add(d.day);
      }
      return map;
    });
