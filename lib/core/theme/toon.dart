/// F7.6 卡通控件库 —— 对齐页面原型的通用组件。
///
/// 全部零新依赖：描边用 [Border]，硬阴影用 `BoxShadow(blurRadius: 0)`，
/// 小猪存钱罐与四角星用 `CustomPainter` 按原型坐标（64 / 24 网格）复刻。
library;

import 'dart:math' as math;
// 虚线边框要按路径长度分段，PathMetric 只有 dart:ui 提供
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'tokens.dart';

part 'toon/press.dart';
part 'toon/card.dart';
part 'toon/dashed.dart';
part 'toon/button.dart';
part 'toon/chip_seg.dart';
part 'toon/field.dart';
part 'toon/avatar_ring.dart';
part 'toon/mascot.dart';
part 'toon/section_title.dart';
