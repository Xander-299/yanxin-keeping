/// 分类圆环画笔单测：只喂一个「记录型 Canvas」，验证描边语义与接缝均分。
///
/// 回归背景：`useCenter` 曾误传 `true`，粗描边把每瓣画成「圆心 → 外圈」的实心楔形
/// （多瓣叠加成风车、圆心文字被盖住）。这里锁死 `useCenter == false`。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/stats/application/stats_aggregate.dart';
import 'package:yanxin/features/stats/presentation/widgets/category_pie.dart';

/// 一次 drawArc 的入参快照。
class _ArcCall {
  const _ArcCall(this.start, this.sweep, this.useCenter, this.paint);

  final double start;
  final double sweep;
  final bool useCenter;
  final Paint paint;
}

/// 只记录 drawArc / drawCircle 的 Canvas 替身（其余成员走 noSuchMethod）。
class _RecordingCanvas implements Canvas {
  final List<_ArcCall> arcs = <_ArcCall>[];
  final List<Paint> circles = <Paint>[];

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) {
    arcs.add(_ArcCall(startAngle, sweepAngle, useCenter, paint));
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(paint);

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// 用「整数分」造切片 —— 与 [categoryBreakdown] 一致，ratio 之和天然为 1。
List<CategorySlice> _slices(List<int> cents) {
  final int total = cents.fold<int>(0, (int a, int b) => a + b);
  return <CategorySlice>[
    for (var i = 0; i < cents.length; i++)
      CategorySlice(
        id: 'c$i',
        name: '分类$i',
        cents: cents[i],
        ratio: total == 0 ? 0 : cents[i] / total,
      ),
  ];
}

const Size _kSize = Size(148, 148);

/// 相邻两瓣之间的缝隙宽度（首尾相接处按整圆收口计算），顺序与 [_ArcCall] 一致。
List<double> _gaps(List<_ArcCall> arcs) {
  final gaps = <double>[];
  for (var i = 0; i < arcs.length; i++) {
    final next = arcs[(i + 1) % arcs.length];
    var gap = next.start - (arcs[i].start + arcs[i].sweep);
    if (i == arcs.length - 1) gap += 2 * math.pi; // 收口：最后一瓣 → 第一瓣
    gaps.add(gap);
  }
  return gaps;
}

void main() {
  test('每一瓣都只描边、不连圆心（useCenter 恒为 false）', () {
    final canvas = _RecordingCanvas();
    DonutPainter(slices: _slices(<int>[3100, 2700, 2600, 1200, 400]))
        .paint(canvas, _kSize);

    expect(canvas.arcs, hasLength(5));
    for (final _ArcCall a in canvas.arcs) {
      expect(a.useCenter, isFalse, reason: 'useCenter=true 会画出圆心楔形');
      expect(a.paint.style, PaintingStyle.stroke);
    }
  });

  test('接缝均分：首尾相接处与其余接缝等宽', () {
    final canvas = _RecordingCanvas();
    DonutPainter(slices: _slices(<int>[3100, 2700, 2600, 1200, 400]))
        .paint(canvas, _kSize);

    final gaps = _gaps(canvas.arcs);
    expect(gaps, hasLength(5));
    for (final double gap in gaps) {
      expect(gap, closeTo(kDonutGap, 1e-9));
    }
  });

  test('单瓣 100%：不留缝隙，整圆铺满', () {
    final canvas = _RecordingCanvas();
    DonutPainter(slices: _slices(<int>[10000])).paint(canvas, _kSize);

    expect(canvas.arcs, hasLength(1));
    expect(canvas.arcs.single.start, closeTo(-math.pi / 2, 1e-9));
    expect(canvas.arcs.single.sweep, closeTo(2 * math.pi, 1e-9));
  });

  test('占比为 0 的瓣不画', () {
    final canvas = _RecordingCanvas();
    DonutPainter(slices: _slices(<int>[6000, 0, 4000])).paint(canvas, _kSize);

    expect(canvas.arcs, hasLength(2));
  });

  test('空数据：画一条底槽整圆，同样不连圆心', () {
    final canvas = _RecordingCanvas();
    const DonutPainter(slices: <CategorySlice>[]).paint(canvas, _kSize);

    expect(canvas.arcs, hasLength(1));
    expect(canvas.arcs.single.useCenter, isFalse);
    expect(canvas.arcs.single.sweep, closeTo(2 * math.pi, 1e-9));
  });
}
