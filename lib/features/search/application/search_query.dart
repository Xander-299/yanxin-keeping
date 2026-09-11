/// 搜索匹配口径（纯函数，不碰 UI 与数据库）。
///
/// 三类字段取**并集**：备注 / 分类名 / 金额。口径见 `docs/SPEC-F7.4-search.md` §3.2：
/// - 查询串预处理：去首尾空白、去 `¥ ￥` 与千分位逗号、英文转小写
/// - 备注与分类名：子串包含（大小写不敏感）
/// - 金额：格式化为「元.分」文本（无千分位）后子串包含
///   —— 查 `88` 命中 `88.00` / `188.00` / `88.88`；查 `88.8` 命中 `88.80`；查 `0.5` 命中 `10.50`
library;

import '../../../core/db/database.dart';
import '../../../core/utils/money.dart';

/// 关键词长度上限（超出截断，避免超长串进匹配）。
const int kSearchKeywordMaxLength = 50;

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

/// 单笔流水是否命中关键词。
///
/// 空关键词恒为 `false`（调用方负责显示引导态，而不是「全部流水」）。
/// [categoryName] 由调用方解析（形如「未分类」），本函数不查库。
bool matchesQuery({
  required TxRow tx,
  required String categoryName,
  required String query,
}) {
  final q = normalizeQuery(query);
  if (q.isEmpty) return false;
  if (tx.note.toLowerCase().contains(q)) return true;
  if (categoryName.toLowerCase().contains(q)) return true;
  if (_hasDigit.hasMatch(q) && amountTextOf(tx.amountCents).contains(q)) {
    return true;
  }
  return false;
}

final RegExp _hasDigit = RegExp(r'\d');

/// 过滤一批流水，保持入参顺序（入参已是时间倒序 → 结果也是时间倒序）。
///
/// 空关键词返回**空列表**：搜索页在未输入时应显示引导，不该列出全部流水。
List<TxRow> filterTx({
  required List<TxRow> items,
  required String Function(String? categoryId) categoryNameOf,
  required String query,
}) {
  if (normalizeQuery(query).isEmpty) return const <TxRow>[];
  return <TxRow>[
    for (final tx in items)
      if (matchesQuery(
        tx: tx,
        categoryName: categoryNameOf(tx.categoryId),
        query: query,
      ))
        tx,
  ];
}
