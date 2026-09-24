/// 搜索匹配口径（纯函数，不碰 UI 与数据库）。
///
/// 四类字段取**并集**：备注 / 分类名 / **账户名** / 金额。口径见
/// `docs/SPEC-F7.4-search.md` §3.2（F7.7 D 批追加账户名一路）：
/// - 查询串预处理：去首尾空白、去 `¥ ￥` 与千分位逗号、英文转小写
/// - 备注 / 分类名 / 账户名：子串包含（大小写不敏感）
/// - 金额：格式化为「元.分」文本（无千分位）后子串包含
///   —— 查 `88` 命中 `88.00` / `188.00` / `88.88`；查 `88.8` 命中 `88.80`；查 `0.5` 命中 `10.50`
///
/// F7.5 追加**类型筛选词**（`docs/SPEC-F7.5-search-overlay.md` §4.3）：
/// 「仅支出 / 仅收入 / 转账」这几个字**不在业务字段里**（备注 / 分类名 / 金额都匹配不到），
/// 直接当关键词搜恒为空，因此改为解析成 `Transactions.type` 的筛选条件。
///
/// F7.7 D 批追加两项（都不引新依赖、不改 schema）：
/// - **日期区间档** [SearchRange]：本月 / 近 3 月 / 全部，与关键词、类型词取交集；
/// - **高亮区间** [highlightRanges]：给命中子串算区间，供 UI 做底色高亮（纯函数，可单测）。
library;

import '../../../core/db/database.dart';
import '../../../core/utils/highlight.dart';
import '../../../core/utils/money.dart';

/// 高亮区间计算在 `core/utils/highlight.dart`（流水行等多处复用，避免模块循环）；
/// 这里 re-export，搜索侧的调用方 / 测试只 import 本文件即可。
export '../../../core/utils/highlight.dart' show MatchRange, highlightRanges;

/// 关键词长度上限（超出截断，避免超长串进匹配）。
const int kSearchKeywordMaxLength = 50;

/// 类型筛选词 → 数据库 `Transactions.type` 取值。
const Map<String, String> kTypeDirectives = <String, String>{
  '仅支出': 'expense',
  '仅收入': 'income',
  '转账': 'transfer',
};

/// 查询串预处理：去首尾空白、去金额符号与千分位、英文转小写、限长。
///
/// 中文不受 [String.toLowerCase] 影响，故大小写归一化对中文查询无副作用。
String normalizeQuery(String raw) {
  final s = raw
      .trim()
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll(',', '')
      .replaceAll('，', '')
      .toLowerCase();
  return s.length > kSearchKeywordMaxLength
      ? s.substring(0, kSearchKeywordMaxLength)
      : s;
}

/// 金额的「元.分」文本（无千分位），搜索比较用。
String amountTextOf(int cents) => centsToYuan(cents);

/// 日期区间档（SPEC §D.1.4）：本月 / 近 3 月 / 全部。
///
/// 口径（都是**自然月**，半开区间 `[start, end)`，与后端 `listByMonth` 的按月口径一致）：
/// - [thisMonth]：本月 1 日 00:00 ~ 下月 1 日 00:00
/// - [last3Months]：**本月 + 前两个自然月**（即「近 3 个月」= 含当月共 3 个月）
/// - [all]：不限时间
enum SearchRange { all, thisMonth, last3Months }

/// chip 文案（顺序即 UI 顺序，默认第一项「全部」）。
const Map<SearchRange, String> kRangeLabels = <SearchRange, String>{
  SearchRange.all: '全部',
  SearchRange.thisMonth: '本月',
  SearchRange.last3Months: '近3月',
};

/// 区间的时间窗（毫秒，半开）；[SearchRange.all] 返回 null（不限）。
({int start, int end})? rangeWindow(SearchRange range, DateTime now) {
  final DateTime? start = switch (range) {
    SearchRange.all => null,
    // DateTime 会自动归一化「月份为 0 / 负数」→ 跨年安全
    SearchRange.thisMonth => DateTime(now.year, now.month, 1),
    SearchRange.last3Months => DateTime(now.year, now.month - 2, 1),
  };
  if (start == null) return null;
  final DateTime end = DateTime(now.year, now.month + 1, 1);
  return (
    start: start.millisecondsSinceEpoch,
    end: end.millisecondsSinceEpoch,
  );
}

/// 某个发生时间（毫秒）是否落在 [range] 内。
bool inRange(int occurredAtMs, SearchRange range, {DateTime? now}) {
  final window = rangeWindow(range, now ?? DateTime.now());
  if (window == null) return true;
  return occurredAtMs >= window.start && occurredAtMs < window.end;
}

/// 一次搜索的执行计划：类型筛选 + 剩余文本关键词。
///
/// 由 [parsePlan] 从输入框原文解析得出；两个字段均为空表示「未输入」（引导态）。
class SearchPlan {
  const SearchPlan({required this.type, required this.text});

  /// `expense` / `income` / `transfer`；null 表示不限类型。
  final String? type;

  /// 剥离类型词后的剩余关键词（已 [normalizeQuery]）。
  final String text;

  /// 什么都没输（既无类型词也无文本）→ 调用方显示引导态而非「全部流水」。
  bool get isEmpty => type == null && text.isEmpty;

  /// 当前生效的类型词（供 chip 高亮：高亮态与输入框同源，不会出现「chip 亮着但输入框空」）。
  String? get typeWord {
    for (final MapEntry<String, String> e in kTypeDirectives.entries) {
      if (e.value == type) return e.key;
    }
    return null;
  }
}

/// 按空白切词，丢掉空串。
List<String> _tokens(String raw) => raw
    .trim()
    .split(RegExp(r'\s+'))
    .where((String t) => t.isNotEmpty)
    .toList();

/// 去掉所有**独立成词**的类型词，其余按空格拼回（保留原文，不做 normalize）。
String _strip(List<String> toks) => toks
    .where((String t) => !kTypeDirectives.containsKey(t))
    .join(' ');

/// 从**原文**剥离类型词，供 chip 切换时回填输入框用。
///
/// 与 [parsePlan] 不同，这里不 normalize——避免把用户输入的 `¥200` 显示成 `200`。
String stripTypeWords(String raw) => _strip(_tokens(raw));

/// 解析输入框原文 → 执行计划。
///
/// - 类型词须**独立成词**（前后为空白 / 串首尾）：`转账手续费` 不会被误判成指令，
///   仍按普通关键词搜（能搜到备注里含这五个字的流水）。
/// - 同时出现多个类型词时**以最后出现的为准**（SPEC Q2），且所有类型词都会被剥离。
SearchPlan parsePlan(String raw) {
  final List<String> toks = _tokens(raw);
  String? type;
  for (final String t in toks) {
    final String? hit = kTypeDirectives[t];
    if (hit != null) type = hit; // 顺序遍历，后者覆盖前者 = 以最后出现的为准
  }
  final String text = normalizeQuery(
    _strip(toks),
  );
  return SearchPlan(type: type, text: text);
}

/// 单笔流水是否命中关键词。
///
/// 空关键词恒为 `false`（调用方负责显示引导态，而不是「全部流水」）。
/// [categoryName] / [accountName] 由调用方解析（分类查不到回退「未分类」），本函数不查库。
bool matchesQuery({
  required TxRow tx,
  required String categoryName,
  required String accountName,
  required String query,
}) {
  final q = normalizeQuery(query);
  if (q.isEmpty) return false;
  if (tx.note.toLowerCase().contains(q)) return true;
  if (categoryName.toLowerCase().contains(q)) return true;
  if (accountName.toLowerCase().contains(q)) return true;
  if (_hasDigit.hasMatch(q) && amountTextOf(tx.amountCents).contains(q)) {
    return true;
  }
  return false;
}

final RegExp _hasDigit = RegExp(r'\d');

/// 是否有**任何**生效条件（类型词 / 关键词 / 非「全部」的日期区间）。
///
/// 三者都没有 = 引导态（不列出全部流水）；只要有一个，就该出结果。
bool hasAnyFilter(SearchPlan plan, SearchRange range) =>
    !plan.isEmpty || range != SearchRange.all;

/// 过滤一批流水，保持入参顺序（入参已是时间倒序 → 结果也是时间倒序）。
///
/// F7.5 起按 [parsePlan] 执行：先按类型筛（若输入含类型词），剩余文本再走 F7.4 原口径。
/// F7.7 D 批追加：账户名参与关键词匹配；[range] 与关键词 / 类型取**交集**。
/// - 只输类型词（如「仅支出」）→ 返回该类型**全部**流水（这正是筛选的意义）
/// - 只选日期区间（无关键词）→ 同理，返回该区间**全部**流水
/// - 三个条件都没有 → 返回**空列表**（搜索页未输入时显示引导，不该列出全部流水）
List<TxRow> filterTx({
  required List<TxRow> items,
  required String Function(String? categoryId) categoryNameOf,
  required String Function(String accountId) accountNameOf,
  required String query,
  SearchRange range = SearchRange.all,
  DateTime? now,
}) {
  final SearchPlan plan = parsePlan(query);
  if (!hasAnyFilter(plan, range)) return const <TxRow>[];
  final DateTime ref = now ?? DateTime.now();
  return <TxRow>[
    for (final TxRow tx in items)
      if (inRange(tx.occurredAt, range, now: ref) &&
          _matchesPlan(
            tx: tx,
            categoryName: categoryNameOf(tx.categoryId),
            accountName: accountNameOf(tx.accountId),
            plan: plan,
          ))
        tx,
  ];
}

bool _matchesPlan({
  required TxRow tx,
  required String categoryName,
  required String accountName,
  required SearchPlan plan,
}) {
  final String? type = plan.type;
  if (type != null && tx.type != type) return false;
  if (plan.text.isEmpty) return true; // 只按类型 / 区间筛（或不带条件的查询，已被上层拦掉）
  return matchesQuery(
    tx: tx,
    categoryName: categoryName,
    accountName: accountName,
    query: plan.text,
  );
}
