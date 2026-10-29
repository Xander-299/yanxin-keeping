/// 调色板对比度护栏（2026-10-28 换 Material 3 后重写）。
///
/// 历史：F7.17 那份守的是卡通调色板的三条规则（hero 只能用 veil / 描边跟底色走 /
/// 前景必须配对底色）。换 M3 后色板来自 `ColorScheme.fromSeed(森绿)`，语义配对变成
/// **onX on X**；本文件改成钉 M3 的配对与阈值，防止「换主题时顺手改坏可读性」。
///
/// 门槛（WCAG AA）：正文小字 4.5:1；描边 / 图形 3.0:1；发丝分割线只要求可见（1.4:1）。
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

String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';

/// 断言「前景 on 背景」达到 [min]，失败信息带具体比值。
void expectPair(Color fg, Color bg, double min, String why) {
  final double c = contrast(fg, bg);
  expect(
    c >= min,
    isTrue,
    reason: '$why：${_hex(fg)} on ${_hex(bg)} 只有 ${c.toStringAsFixed(2)}:1（需 $min）',
  );
}

void main() {
  final Map<String, ToonPalette> palettes = <String, ToonPalette>{
    '浅色': ToonPalette.light,
    '深色': ToonPalette.dark,
  };

  group('文字层级（onSurface / onSurfaceVariant / outline）', () {
    for (final MapEntry<String, ToonPalette> e in palettes.entries) {
      final ToonPalette p = e.value;

      test('${e.key}：ink 与 ink2 在三种表面上都过 4.5', () {
        for (final Color bg in <Color>[p.paper, p.canvas, p.canvas2]) {
          expectPair(p.ink, bg, 4.5, '${e.key} 主文字');
          expectPair(p.ink2, bg, 4.5, '${e.key} 次要文字');
        }
      });

      test('${e.key}：ink3（outline）在纸底上至少 3.0', () {
        // M3 的 outline 是给「次级文字 / 图标」用的，一般 ≥4.5；这里只钉下限
        expectPair(p.ink3, p.paper, 3.0, '${e.key} 三级字');
      });

      test('${e.key}：层级没丢（ink 比 ink2 更强，ink2 不弱于 ink3）', () {
        final double c1 = contrast(p.ink, p.paper);
        final double c2 = contrast(p.ink2, p.paper);
        final double c3 = contrast(p.ink3, p.paper);
        expect(c1, greaterThan(c2));
        expect(c2, greaterThanOrEqualTo(c3));
      });
    }
  });

  group('实心底上的前景（M3 配对）', () {
    for (final MapEntry<String, ToonPalette> e in palettes.entries) {
      final ToonPalette p = e.value;

      test('${e.key}：onBrand/brand、brandInk/brandTint 过 4.5', () {
        expectPair(p.onBrand, p.brand, 4.5, '${e.key} 主按钮文字');
        expectPair(p.brandInk, p.brandTint, 4.5, '${e.key} 品牌浅底文字');
      });

      test('${e.key}：onRed/red、redInk/redTint 过 4.5', () {
        // 左滑删除动作区：白字压实心红往往不够，M3 用 onError
        expectPair(p.onRed, p.red, 4.5, '${e.key} 危险按钮文字');
        expectPair(p.redInk, p.redTint, 4.5, '${e.key} 错误浅底文字');
      });

      test('${e.key}：hero 主金额（heroInk on brand）过 4.5', () {
        expectPair(p.heroInk, p.brandTint, 4.5, '${e.key} hero 主金额');
      });
    }
  });

  group('描边与分割线', () {
    for (final MapEntry<String, ToonPalette> e in palettes.entries) {
      final ToonPalette p = e.value;

      test('${e.key}：发丝分割线在纸底上可见（≥1.4）', () {
        expectPair(p.line, p.paper, 1.4, '${e.key} 分割线');
      });
    }
  });
}
