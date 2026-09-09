/// 日期工具：内部时间一律毫秒 epoch，展示层才格式化。
///
/// 月份边界按**本地时区**计算——用户感知的「9 月」是本地时间的 9 月，不是 UTC。
/// 用 [DateTime] 构造「某月 1 号 00:00:00.000」即可正确跨越月末 / 闰年 / 跨年。
library;

/// 某年某月的起止毫秒（左闭右开 [start, end)）。[month] 取值 1-12。
({int start, int end}) monthRange(int year, int month) {
  final start = DateTime(year, month, 1).millisecondsSinceEpoch;
  final end = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
  return (start: start, end: end);
}

/// 判断毫秒时间是否落在指定月份内（本地时区）。
bool isInMonth(int ms, int year, int month) {
  final r = monthRange(year, month);
  return ms >= r.start && ms < r.end;
}

/// 本地日期 key（YYYY-MM-DD），用于流水按天分组。
String dayKey(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

String _dayKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 友好展示：今天「今天」，昨天「昨天」，否则「M月D日」（跨年带年份）。
String formatDayLabel(int ms, {int? now}) {
  final a = DateTime.fromMillisecondsSinceEpoch(ms);
  final b = DateTime.fromMillisecondsSinceEpoch(now ?? DateTime.now().millisecondsSinceEpoch);
  final sameYear = a.year == b.year;
  final key = _dayKeyOf(a);
  if (key == _dayKeyOf(b)) return '今天';
  final yesterday = DateTime(b.year, b.month, b.day - 1);
  if (key == _dayKeyOf(yesterday)) return '昨天';
  return sameYear ? '${a.month}月${a.day}日' : '${a.year}年${a.month}月${a.day}日';
}

/// 按本地日期分组的一条分组结果。
class DayGroup<T> {
  /// 分组 key（YYYY-MM-DD）。
  const DayGroup({required this.key, required this.label, required this.items});

  /// 分组 key，YYYY-MM-DD。
  final String key;

  /// 展示标签（今天 / 昨天 / M月D日）。
  final String label;

  /// 该日的流水，保持入参顺序。
  final List<T> items;
}

/// 把流水列表按本地日期分组（倒序：新的日期在前）。
///
/// [occurredAtOf] 取出每项的毫秒时间，避免对元素类型做约束。
List<DayGroup<T>> groupByDay<T>(List<T> list, int Function(T item) occurredAtOf) {
  final order = <String>[];
  final map = <String, List<T>>{};
  for (final item in list) {
    final key = dayKey(occurredAtOf(item));
    if (!map.containsKey(key)) {
      map[key] = <T>[];
      order.add(key);
    }
    map[key]!.add(item);
  }
  // 日期降序（YYYY-MM-DD 的字典序即时间序）
  order.sort((a, b) => b.compareTo(a));
  return [
    for (final key in order)
      DayGroup<T>(
        key: key,
        label: formatDayLabel(occurredAtOf(map[key]!.first)),
        items: map[key]!,
      ),
  ];
}
