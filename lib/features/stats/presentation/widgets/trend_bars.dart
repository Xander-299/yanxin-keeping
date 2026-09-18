/// 近 N 月收支趋势柱状图（自绘布局，不引图表库）。
///
/// 每个月两根柱：支出红 / 收入绿（中国习惯），高度按区间内最大值等比缩放。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/utils/money.dart';

import '../../application/stats_aggregate.dart';

/// 趋势柱高度上限（逻辑像素）。
const double kTrendBarHeight = 96;

/// 近 N 月趋势。
class TrendBars extends StatelessWidget {
  const TrendBars({required this.points, required this.anchorYear, super.key});

  final List<MonthPoint> points;

  /// 用于判断是否需要带年份（跨年时显示为「25年12月」）。
  final int anchorYear;

  @override
  Widget build(BuildContext context) {
    final max = points.fold<int>(0, (int m, MonthPoint p) {
      final v = p.incomeCents > p.expenseCents ? p.incomeCents : p.expenseCents;
      return v > m ? v : m;
    });

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final p in points)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: kTrendBarHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        _Bar(
                          cents: p.expenseCents,
                          max: max,
                          color: Tok.red,
                          tooltip: '支出',
                        ),
                        const SizedBox(width: 4),
                        _Bar(
                          cents: p.incomeCents,
                          max: max,
                          color: Tok.green,
                          tooltip: '收入',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.labelOf(anchorYear),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Tok.ink2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.cents,
    required this.max,
    required this.color,
    required this.tooltip,
  });

  final int cents;
  final int max;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final height = max == 0 || cents == 0
        ? 2.0
        : (cents / max) * kTrendBarHeight;
    return Tooltip(
      message: '$tooltip ${centsToYuan(cents)} 元',
      child: Container(
        width: 13,
        // +4 抵消 2px 描边（Container 的 border 画在尺寸内侧，原型是 content-box）
        height: height + 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(3),
          ),
          border: Border.all(color: Tok.ink, width: 2),
        ),
      ),
    );
  }
}
