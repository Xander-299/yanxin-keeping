/// 搜索历史：纯函数（去重 / 截断 / 容错解析）+ `schema_meta` KV 持久化。
///
/// F7.7 D 批：SPEC §D.3 原计划新建 `app_meta` 表（schema → v4），
/// 实际复用**已存在**的 `schema_meta` KV 表 → 本批不动 schema（见 §G 记录）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/app_meta_repository.dart';
import 'package:yanxin/features/search/application/search_history.dart';

import '../../helpers/test_database.dart';

void main() {
  group('pushKeyword', () {
    test('新词插到最前', () {
      expect(pushKeyword(<String>['打车'], '午餐'), <String>['午餐', '打车']);
      expect(pushKeyword(<String>[], '午餐'), <String>['午餐']);
    });

    test('重复词提到最前，且保留这次的写法', () {
      expect(
        pushKeyword(<String>['午餐', '打车'], '午餐'),
        <String>['午餐', '打车'],
      );
      expect(
        pushKeyword(<String>['午餐', '打车'], '打车'),
        <String>['打车', '午餐'],
      );
      // 去重忽略大小写，但存的是用户这次输入的原文
      expect(pushKeyword(<String>['lunch'], 'Lunch'), <String>['Lunch']);
    });

    test('去首尾空白；空白词 / 空串不记（原样返回）', () {
      expect(pushKeyword(<String>['午餐'], '  打车  '), <String>['打车', '午餐']);
      expect(pushKeyword(<String>['午餐'], '   '), <String>['午餐']);
      expect(pushKeyword(<String>['午餐'], ''), <String>['午餐']);
    });

    test('超过上限截断到最近 10 条（老的丢掉）', () {
      List<String> h = <String>[];
      for (int i = 1; i <= 12; i++) {
        h = pushKeyword(h, '词$i');
      }
      expect(h, hasLength(kSearchHistoryMax));
      expect(h.first, '词12');
      expect(h.last, '词3'); // 词1 / 词2 被挤出
    });
  });

  group('decodeHistory（容错解析）', () {
    test('encode → decode 往返一致', () {
      final h = <String>['午餐', '88', 'Lunch'];
      expect(decodeHistory(encodeHistory(h)), h);
    });

    test('null / 空串 → 空历史', () {
      expect(decodeHistory(null), isEmpty);
      expect(decodeHistory(''), isEmpty);
    });

    test('坏数据一律当空历史，绝不抛异常（历史坏了不该打不开搜索页）', () {
      expect(decodeHistory('{不是数组}'), isEmpty);
      expect(decodeHistory('["午餐",'), isEmpty); // 截断的 JSON
      expect(decodeHistory('123'), isEmpty); // 不是数组
      expect(decodeHistory('["午餐", 5, null]'), <String>['午餐']); // 非字符串项被丢弃
      expect(decodeHistory('["  ", "打车"]'), <String>['打车']); // 空白项被丢弃
    });
  });

  group('SearchHistoryController（落 schema_meta KV）', () {
    test('remember 写库（新 container = 冷启动后仍在），clear 连行一起删', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      // Riverpod 3 未公开导出 Override 类型 → 不写类型注解
      final first = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(first.dispose);

      expect(await first.read(searchHistoryProvider.future), isEmpty);
      await first.read(searchHistoryProvider.notifier).remember('午餐');
      await first.read(searchHistoryProvider.notifier).remember('打车');
      expect(
        first.read(searchHistoryProvider).value,
        <String>['打车', '午餐'],
      );
      // 同词再来一次：顺序不变，也不报错
      await first.read(searchHistoryProvider.notifier).remember('打车');
      expect(
        first.read(searchHistoryProvider).value,
        <String>['打车', '午餐'],
      );

      // 真写进了 KV（值是一段 JSON）
      final String? raw = await AppMetaRepository(db).get(kSearchHistoryKey);
      expect(raw, isNotNull);
      expect(decodeHistory(raw), <String>['打车', '午餐']);

      // 冷启动：新 container 从库里读回来
      final second = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(second.dispose);
      expect(
        await second.read(searchHistoryProvider.future),
        <String>['打车', '午餐'],
      );

      // 清空：状态空 + KV 行删除
      await second.read(searchHistoryProvider.notifier).clear();
      expect(second.read(searchHistoryProvider).value, isEmpty);
      expect(await AppMetaRepository(db).get(kSearchHistoryKey), isNull);
    });
  });

  group('AppMetaRepository（通用 KV）', () {
    test('set / get / remove 与覆盖写', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repo = AppMetaRepository(db);

      expect(await repo.get('k'), isNull);
      await repo.set('k', 'v1');
      expect(await repo.get('k'), 'v1');
      await repo.set('k', 'v2'); // 覆盖，不新增行
      expect(await repo.get('k'), 'v2');
      await repo.remove('k');
      expect(await repo.get('k'), isNull);
      await repo.remove('k'); // 删不存在的 key 也不报错
    });
  });
}
