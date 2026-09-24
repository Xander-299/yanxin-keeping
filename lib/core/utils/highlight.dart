/// 文本命中高亮：把「命中区间」算成纯数据，UI 层再决定怎么画。
///
/// 放在 `core/utils` 而不是搜索模块里：流水行（`TxTile`）在首页 / 日历 / 报表 /
/// 搜索多处复用，它需要**通用**的区间计算；若把函数留在 `features/search`，
/// 就会让 `features/ledger` 反向依赖 `features/search`（模块循环）。
library;

/// 高亮区间（半开 `[start, end)`，下标基于**原始文本**）。
typedef MatchRange = ({int start, int end});

/// 文本里所有命中 [query] 的区间（大小写不敏感，不重叠、从左到右）。
///
/// - 空 query / 空文本 → 空列表（调用方不必特判）
/// - 不做任何 normalize：调用方负责传「已归一化的关键词 + 界面上真正显示的那串文本」，
///   两者下标才对齐（流水行金额无千分位 = `amountTextOf` 的口径）
List<MatchRange> highlightRanges(String text, String query) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty || text.isEmpty) return const <MatchRange>[];
  final String hay = text.toLowerCase();
  final List<MatchRange> out = <MatchRange>[];
  var from = 0;
  while (from <= hay.length - q.length) {
    final int i = hay.indexOf(q, from);
    if (i < 0) break;
    out.add((start: i, end: i + q.length));
    from = i + q.length; // 命中后从区间末尾继续：不重叠，也不会死循环
  }
  return out;
}
