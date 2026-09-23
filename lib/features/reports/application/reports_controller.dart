/// 报表页状态：当前账本 + 当前月份 + 当前档位 + 当月流水与名字映射。
///
/// 与首页 `ledgerProvider`、日历 `calendarProvider`、统计 `statsProvider` 一样
/// **独立记月份**：报表页翻月不带走其它页。
///
/// 取数与首页/日历/统计同一句 `listByMonth`，口径天然一致（软删已过滤）。
///
/// 写操作后自动重载：`listen` 数据版本号（见 `core/providers/data_epoch.dart`），
/// 不用在每个写操作处补一行 `reportsProvider.refresh()`。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/account_providers.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';

import 'report_aggregate.dart';

/// 明细档。
const String kReportTabDetail = 'detail';

/// 分类档（首页 header「报表」的默认档）。
const String kReportTabCategory = 'category';

/// 账户档。
const String kReportTabAccount = 'account';

/// `ToonSeg` 的档位顺序（下标 ↔ [kReportTabs]）。
const List<String> kReportTabs = <String>[
  kReportTabDetail,
  kReportTabCategory,
  kReportTabAccount,
];

/// `ToonSeg` 的档位文案。
const List<String> kReportTabLabels = <String>['明细', '分类', '账户'];

/// 档位在下标里的位置（未知档位退回「明细」）。
int reportTabIndex(String tab) {
  final int i = kReportTabs.indexOf(tab);
  return i < 0 ? 0 : i;
}

/// 路由进入报表页时由 `extra` 带入的参数（都可空：为空沿用 controller 当前状态）。
class ReportsArgs {
  const ReportsArgs({this.tab, this.year, this.month});

  final String? tab;
  final int? year;
  final int? month;

  bool get isEmpty => tab == null && year == null && month == null;
}

/// 报表页状态快照。
class ReportsState {
  const ReportsState({
    required this.bookId,
    required this.year,
    required this.month,
    required this.tab,
    required this.items,
    required this.categoryNames,
    required this.accountNames,
  });

  final String bookId;

  final int year;

  /// 1-12。
  final int month;

  /// [kReportTabDetail] / [kReportTabCategory] / [kReportTabAccount]。
  final String tab;

  /// 当月全部未删流水（发生时间倒序）。
  final List<TxRow> items;

  /// 分类 id → 名称。
  final Map<String, String> categoryNames;

  /// 账户 id → 名称（**只含当前账本未软删的账户**，其 key 集合即「已知账户」）。
  final Map<String, String> accountNames;

  /// 当月收支汇总（与首页 / 统计页同一口径）。
  MonthSummary get summary => summarize(items);

  /// 分类名解析：无分类或查不到名字都归「未分类」。
  String categoryNameOf(String? id) =>
      (id == null ? null : categoryNames[id]) ?? kUncategorized;

  /// 账户名解析：只在 [groupByAccount] 判定为「已知账户」时被调用。
  String accountNameOf(String id) => accountNames[id] ?? kOtherAccountTitle;

  /// 分类档某方向的聚合（金额降序）。
  List<ReportGroup> groupsOf(String type) =>
      groupByCategory(items, type: type, nameOf: categoryNameOf);

  /// 账户档聚合（支出 / 收入 / 转账三向）。
  List<ReportGroup> get accountGroups => groupByAccount(
    items,
    knownAccountIds: accountNames.keys.toSet(),
    nameOf: accountNameOf,
  );

  /// 当月转账流水（分类档单列一段）。
  List<TxRow> get transfers => transferRows(items);

  ReportsState copyWith({String? tab}) => ReportsState(
    bookId: bookId,
    year: year,
    month: month,
    tab: tab ?? this.tab,
    items: items,
    categoryNames: categoryNames,
    accountNames: accountNames,
  );
}

/// 报表页 controller。
final reportsProvider = AsyncNotifierProvider<ReportsController, ReportsState>(
  ReportsController.new,
);

class ReportsController extends AsyncNotifier<ReportsState> {
  @override
  Future<ReportsState> build() async {
    // 写操作（记一笔 / 删除流水 / 导入账单）成功后都会 bump 版本号 → 这里
    // 静默重载当前月，**保留用户已选的档位与月份**（`refresh()` 同口径）。
    //
    // 用 `listen` 而**不是** `watch`：`watch` 会让 build 重跑，把月份 / 档位
    // 重置回「当月 + 明细」，等于吞掉用户在报表页翻的月份（SPEC §A.2
    // 「报表页独立记月份」）。必须放第一个 await 之前，否则事件会丢。
    ref.listen<int>(dataEpochProvider, (int? previous, int next) {
      unawaited(refresh());
    });
    final bookId = await ref.watch(activeBookIdProvider.future);
    if (bookId == null) {
      throw StateError('当前账本未就绪');
    }
    final now = DateTime.now();
    return _load(bookId, now.year, now.month, kReportTabDetail);
  }

  Future<ReportsState> _load(
    String bookId,
    int year,
    int month,
    String tab,
  ) async {
    final items = await ref
        .read(transactionRepositoryProvider)
        .listByMonth(bookId, year, month);
    final categories = await ref.watch(categoriesProvider.future);
    final accounts = await ref.watch(accountsProvider.future);
    return ReportsState(
      bookId: bookId,
      year: year,
      month: month,
      tab: tab,
      items: items,
      categoryNames: <String, String>{
        for (final Category c in categories) c.id: c.name,
      },
      accountNames: <String, String>{
        for (final Account a in accounts) a.id: a.name,
      },
    );
  }

  /// 静默重载：**不**先切到 `AsyncLoading`。
  ///
  /// 报表页的月份切换器在 AppBar 里；中途若把 state 置成 `AsyncLoading`，
  /// `async.value` 会变 null → 切换器整条消失（像按钮被吃掉）。
  /// 保持旧数据直到新数据就绪，翻月体验也更顺。
  Future<void> _reload(String bookId, int year, int month, String tab) async {
    final AsyncValue<ReportsState> next = await AsyncValue.guard(
      () => _load(bookId, year, month, tab),
    );
    state = next;
  }

  /// 路由进入时按 [args] 对齐月份与档位。
  ///
  /// 与当前状态**完全一致时不动**（避免一次多余查询 + 白闪）；调用方是
  /// `unawaited(...)`，所以 build 失败时这里静默返回，错误由页面上的
  /// `AsyncValue.error` 分支呈现。
  Future<void> open(ReportsArgs? args) async {
    if (args == null || args.isEmpty) return;
    final ReportsState? cached = state.value;
    if (cached != null) {
      await _apply(cached, args);
      return;
    }
    final ReportsState? loaded = await _awaitInitial();
    if (loaded == null) return;
    await _apply(loaded, args);
  }

  /// 等首次 build 完成；失败时返回 null（错误已由 state 的 error 分支呈现）。
  Future<ReportsState?> _awaitInitial() async {
    try {
      return await future;
    } on Object {
      return null;
    }
  }

  Future<void> _apply(ReportsState current, ReportsArgs args) async {
    final int year = args.year ?? current.year;
    final int month = args.month ?? current.month;
    final String tab = args.tab ?? current.tab;
    if (year != current.year || month != current.month) {
      await _reload(current.bookId, year, month, tab);
    } else if (tab != current.tab) {
      // 只换档位：同一批数据换种看法，不必重查库
      state = AsyncData(current.copyWith(tab: tab));
    }
  }

  /// 翻月：delta = -1 上一月，+1 下一月（调用方先判 `canGoNext`）。
  Future<void> shiftMonth(int delta) async {
    final ReportsState? current = state.value;
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
    await _reload(current.bookId, y, m, current.tab);
  }

  /// 切档位（不重查库）。
  void setTab(String tab) {
    final ReportsState? current = state.value;
    if (current == null || current.tab == tab) return;
    state = AsyncData(current.copyWith(tab: tab));
  }

  /// 重新加载当前账本当前月（记一笔 / 删除后刷新用）。
  Future<void> refresh() async {
    final ReportsState? current = state.value;
    if (current == null) return;
    await _reload(current.bookId, current.year, current.month, current.tab);
  }
}
