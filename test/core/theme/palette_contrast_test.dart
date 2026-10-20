/// 调色板对比度护栏（F7.17 深色模式对比度修复）。
///
/// 背景：用户报「切到深色后部分字看不清」。量化后发现根因**不是**「深色普遍更差」
/// （实测深色大多反而更好），而是两处具体的坑：
///
/// 1. **hero（恒琥珀底）上的合成色方向反了** —— `paper@0.55` 当「减淡层」时，深色主题下
///    `paper` 是近黑 → 气泡被压成 `#88662B`，而 `heroInk` 恒为深棕 → **2.12:1**（浅色 6.00）。
///    修法：hero 上的减淡层只能用 `veil`（白）、描边只能用 `decorInk`（恒深）。
/// 2. **三级灰 `ink3` 在深色纸底上只有 3.96:1**，而它承担底栏标签(11px) / 输入框 hint /
///    8px 月历辅助字 → 提亮到 `#A098AE`（paper 5.52 / canvas2 6.09 / track 4.73）。
///
/// 本文件用 WCAG 相对亮度公式把这两条钉死，**防止再退化**。
/// 门槛：正文小字 4.5:1；描边 / 图形 3.0:1（WCAG AA）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/theme/palette.dart';

/// WCAG 对比度。
double contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 半透明前景叠在实底上的**实际呈现色**（`withValues(alpha:)` 的合成结果）。
Color over(Color fg, Color bg, double alpha) => Color.fromARGB(
  255,
  (alpha * fg.r * 255 + (1 - alpha) * bg.r * 255).round(),
  (alpha * fg.g * 255 + (1 - alpha) * bg.g * 255).round(),
  (alpha * fg.b * 255 + (1 - alpha) * bg.b * 255).round(),
);

/// 断言一组「前景 on 背景」都过 [min]，失败信息带上具体比值。
void expectAll(
  ToonPalette p,
  List<Color> fgs,
  List<Color> bgs,
  double min, {
  required String why,
}) {
  for (final Color f in fgs) {
    for (final Color b in bgs) {
      final double c = contrast(f, b);
      expect(
        c >= min,
        isTrue,
        reason: '$why：#${f.toARGB32().toRadixString(16)} on '
            '#${b.toARGB32().toRadixString(16)} 只有 ${c.toStringAsFixed(2)}:1（需 $min）',
      );
    }
  }
}

void main() {
  group('深色 · 文字三阶（本次修复的重点）', () {
    const ToonPalette p = ToonPalette.dark;
    final List<Color> bgs = <Color>[p.paper, p.canvas, p.canvas2, p.track];

    test('ink / ink2 / ink3 在所有纸底上都过 AA 4.5', () {
      expectAll(p, <Color>[p.ink, p.ink2, p.ink3], bgs, 4.5, why: '深色文字三阶');
    });

    test('ink3 具体比值（底栏标签 / hint / 8px 辅助字都用它）', () {
      expect(contrast(p.ink3, p.paper), greaterThanOrEqualTo(4.5));
      expect(contrast(p.ink3, p.track), greaterThanOrEqualTo(4.5));
      // 层级不能丢：仍要明显暗于 ink2
      expect(contrast(p.ink3, p.paper), lessThan(contrast(p.ink2, p.paper)));
    });
  });

  group('hero（恒琥珀底）上的合成色 —— 深浅两套必须都可读', () {
    for (final MapEntry<String, ToonPalette> e in <MapEntry<String, ToonPalette>>[
      const MapEntry<String, ToonPalette>('浅色', ToonPalette.light),
      const MapEntry<String, ToonPalette>('深色', ToonPalette.dark),
    ]) {
      test('${e.key}：收入 / 结余气泡（veil@0.55 叠琥珀）+ heroInk 深棕字过 4.5', () {
        final ToonPalette p = e.value;
        // 减淡层**只能是 veil**：用 paper 的话深色主题下会压成暗琥珀 → 2.12:1
        final Color bubble = over(p.veil, p.brand, 0.55);
        expect(contrast(p.heroInk, bubble), greaterThanOrEqualTo(4.5));
      });

      test('${e.key}：hero 描边 decorInk 在琥珀上过 3.0（图形 / 描边门槛）', () {
        // 深色主题下 p.ink 是暖白，压在琥珀上只有 ~1.3:1 → 描边整条消失
        expect(
          contrast(e.value.decorInk, e.value.brand),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('${e.key}：hero 主金额 heroInk 在琥珀上过 4.5', () {
        expect(contrast(e.value.heroInk, e.value.brand), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('实心色底上的字 / 图标', () {
    for (final MapEntry<String, ToonPalette> e in <MapEntry<String, ToonPalette>>[
      const MapEntry<String, ToonPalette>('浅色', ToonPalette.light),
      const MapEntry<String, ToonPalette>('深色', ToonPalette.dark),
    ]) {
      test('${e.key}：onBrand / brandInk / redInk / onRed 都过 4.5', () {
        final ToonPalette p = e.value;
        expect(contrast(p.onBrand, p.brand), greaterThanOrEqualTo(4.5));
        expect(contrast(p.brandInk, p.brandTint), greaterThanOrEqualTo(4.5));
        expect(contrast(p.redInk, p.redTint), greaterThanOrEqualTo(4.5));
        // 左滑删除动作区：白字在实心红上只有 ~2.8/3.0，必须走 onRed
        expect(contrast(p.onRed, p.red), greaterThanOrEqualTo(4.5));
      });

      test('${e.key}：品牌调的字放在纸底上也要够（底栏选中标签用 brandInk）', () {
        // 底栏图标画在琥珀块上 → onBrand；标签画在纸底上 → 必须换 brandInk，
        // 否则深色下是「深棕压近黑」（onBrand on paper ≈1.1:1，整个标签看不见）
        final ToonPalette p = e.value;
        expect(contrast(p.brandInk, p.paper), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('浅色 · 既有值（F7.6 遗留，只钉下限防退化）', () {
    const ToonPalette p = ToonPalette.light;

    test('ink / ink2 过 AA 4.5', () {
      expectAll(
        p,
        <Color>[p.ink, p.ink2],
        <Color>[p.paper, p.canvas, p.canvas2],
        4.5,
        why: '浅色文字主阶',
      );
    });

    test('ink3 未达 AA（2.7:1）—— 已记录待设计侧决定，这里只钉住不更差', () {
      // F7.6 定下的浅色三级灰就是 2.7:1；改成 4.5 会让 ink3 与 ink2 几乎同色、层级丢失。
      // 本次只修深色（用户报的那侧），浅色维持原样并守住下限。
      expect(contrast(p.ink3, p.paper), greaterThanOrEqualTo(2.5));
    });
  });
}
