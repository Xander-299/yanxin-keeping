/// 搜索历史：最近 10 条关键词，持久化在 `schema_meta` KV（**不动 schema**）。
///
/// 记录时机（只在「确实搜了」的动作用户操作上触发，不做逐键记录）：
/// - 输入框回车 / 键盘「搜索」键
/// - 点了历史 chip、示例 chip（该关键词被当成一次真实搜索）
/// - 点了某条结果（说明这次搜索有用）
///
/// 只记**关键词**部分：纯类型指令（如「仅支出」）不算关键词，不入历史。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database.dart';

/// 历史上限（SPEC §D.1.3：最近 10 条）。
const int kSearchHistoryMax = 10;

/// KV key（`schema_meta.key`）。
const String kSearchHistoryKey = 'search_history';

/// 把一条关键词并进历史。
///
/// - 去首尾空白；空串直接原样返回（不记空）
/// - 去重**忽略大小写**，命中的旧项移除 → 等价于「提到最前」，且保留用户这次的写法
/// - 截断到 [max]
List<String> pushKeyword(
  List<String> current,
  String keyword, {
  int max = kSearchHistoryMax,
}) {
  final String k = keyword.trim();
  if (k.isEmpty || max <= 0) return current;
  final String lower = k.toLowerCase();
  final List<String> out = <String>[
    k,
    for (final String c in current)
      if (c.trim().toLowerCase() != lower) c,
  ];
  return out.length > max ? out.sublist(0, max) : out;
}

/// 解析 KV 里存的 JSON。
///
/// **任何损坏都当空历史**（非 JSON / 不是字符串数组 / 元素不是字符串）——
/// 搜索历史坏了不该让整个搜索页打不开。
List<String> decodeHistory(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return <String>[
      for (final Object? item in decoded)
        if (item is String && item.trim().isNotEmpty) item,
    ];
  } on FormatException {
    return const <String>[];
  }
}

/// 编码成 KV 值。
String encodeHistory(List<String> history) => jsonEncode(history);

/// 搜索历史状态（本机、跨账本共用一份：关键词是用户习惯，不属于某个账本）。
final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryController, List<String>>(
      SearchHistoryController.new,
    );

class SearchHistoryController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final String? raw = await ref
        .read(appMetaRepositoryProvider)
        .get(kSearchHistoryKey);
    return decodeHistory(raw);
  }

  /// 记一条（同词提前到最前）。顺序没变化则不写库。
  Future<void> remember(String keyword) async {
    final List<String> current = state.value ?? await future;
    final List<String> next = pushKeyword(current, keyword);
    if (listEquals(next, current)) return;
    state = AsyncData<List<String>>(next);
    await ref
        .read(appMetaRepositoryProvider)
        .set(kSearchHistoryKey, encodeHistory(next));
  }

  /// 清空历史（连 KV 行一起删，不留空数组）。
  Future<void> clear() async {
    state = const AsyncData<List<String>>(<String>[]);
    await ref.read(appMetaRepositoryProvider).remove(kSearchHistoryKey);
  }
}
