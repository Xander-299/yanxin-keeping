/// 趋势柱高度策略单测（纯函数，不渲染）。
///
/// 回归背景：无数据的月份原先也画一对 2px 内高的「基座胶囊」，
/// 4 个月没流水时看着像每月都有小额收支 → 改为返回 null（不画）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/stats/presentation/widgets/trend_bars.dart';

void main() {
  test('无数据（0 分）→ null，不画柱', () {
    expect(trendBarHeight(0, 10000), isNull);
    expect(trendBarHeight(0, 0), isNull);
  });

  test('区间最大值为 0（整个区间都没流水）→ 全部不画', () {
    for (final int cents in <int>[0, 0, 0]) {
      expect(trendBarHeight(cents, 0), isNull);
    }
  });

  test('有数据：按区间最大值等比缩放，满值顶到柱区上限', () {
    expect(trendBarHeight(10000, 10000), kTrendBarHeight);
    expect(trendBarHeight(5000, 10000), kTrendBarHeight / 2);
    expect(trendBarHeight(2500, 10000), kTrendBarHeight / 4);
  });

  test('极小金额仍是正高度（还有 2px 描边兜底可见）', () {
    final double? tiny = trendBarHeight(1, 1000000);
    expect(tiny, isNotNull);
    expect(tiny!, greaterThan(0));
    expect(tiny, lessThan(0.01));
  });

  test('负数（脏数据）也按「无数据」处理，不会画出反向柱', () {
    expect(trendBarHeight(-100, 10000), isNull);
  });
}
