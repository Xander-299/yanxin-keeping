/// 分类占比圆环（自绘，不引图表库）。
///
/// 只画「比例」：金额一律整数分进、整数分出，double 仅出现在画笔的角度换算里。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/utils/money.dart';

import '../../application/stats_aggregate.dart';

/// 分类配色（按顺序循环取用，取自原型 `PIE_COLORS`）。
const List<Color> kCategoryColors = Tok.pie;

/// 多瓣之间的缝隙（弧度）。
const double kDonutGap = 0.02;

/// 第 [index] 个分类的颜色。
Color categoryColor(int index) =>
    kCategoryColors[index % kCategoryColors.length];

/// 分类占比圆环 + 圆心合计。
class CategoryPie extends StatelessWidget {
  const CategoryPie({required this.slices, this.size = 148, super.key});

  final List<CategorySlice> slices;

  final double size;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (int a, CategorySlice s) => a + s.cents);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size(size, size),
            painter: DonutPainter(slices: slices),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                centsToYuan(total, group: true),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                slices.isEmpty ? '暂无数据' : '合计（元）',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 圆环画笔（公开以便单测直接喂一个记录型 Canvas）。
class DonutPainter extends CustomPainter {
  const DonutPainter({required this.slices});

  final List<CategorySlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final thickness = outer * 0.34;
    final rect = Rect.fromCircle(
      center: center,
      radius: outer - thickness / 2,
    );

    if (slices.isEmpty) {
      // useCenter 恒为 false：为 true 时路径会连到圆心，
      // 粗描边会把弧画成「圆心 → 外圈」的实心楔形（整圆时则是多出一条辐条）。
      canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..color = Tok.track
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
      return;
    }

    var start = -math.pi / 2;
    // 多瓣之间留一点缝隙，单瓣（100%）不留
    final gap = slices.length > 1 ? kDonutGap : 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].ratio * 2 * math.pi;
      if (sweep <= 0) continue;
      // 缝隙在两瓣的接缝处**各让一半**：若整段缝都从瓣尾扣，
      // 首尾相接那段会宽成 n 倍（其余接缝各 0.02，收口处 0.02·n）。
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.01),
        false,
        Paint()
          ..color = categoryColor(i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
