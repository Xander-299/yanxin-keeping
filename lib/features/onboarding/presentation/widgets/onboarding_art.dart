/// F7.14 新手引导的迷你示意图 —— **全部矢量手绘**（不引图片资源）。
///
/// 设计约束（SPEC-F7.14 §3.3）：
/// - 只用 `Tok.*` 令牌与现成 `Toon*` 件，**不出现裸色值**；
/// - 迷你控件**复刻真实比例与同一组 IconData**（底栏 68→54、header 图标 40→26、中央方块 54×48→30×26）；
/// - 目标控件一律用 [HighlightBox] 圈住，配 [Callout] 标签 + 折线箭头。
///
/// 为什么不截图：截图要跟 UI 改版同步重做，还要出多套分辨率资源；手绘件改一处即全站生效。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

part 'onboarding_art/art_common.dart';
part 'onboarding_art/art_welcome.dart';
part 'onboarding_art/art_header.dart';
part 'onboarding_art/art_budget.dart';
part 'onboarding_art/art_gestures.dart';
part 'onboarding_art/art_assets_done.dart';

/// 迷你「屏幕」外壳：白底 + 墨色描边 + 硬阴影，固定宽 288（窄于任何机型的可用宽度）。
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.width = 288,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Center(
      child: Container(
        width: width,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: p.cardDeco(radius: Tok.rMd, depth: 3),
        child: child,
      ),
    );
  }
}

/// 高亮圈：品牌色描边 + 品牌浅底，圈住「这一页要说的是它」。
class HighlightBox extends StatelessWidget {
  const HighlightBox({super.key, required this.child, this.radius = 11});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.brandTint2.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.brand, width: 2),
      ),
      child: child,
    );
  }
}

/// 指引标签 + 折线箭头。[up] = 箭头在标签**上方**并指向上（标签位于目标下方时用）。
class Callout extends StatelessWidget {
  const Callout({super.key, required this.label, this.up = false});

  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: p.brandTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.brand, width: 1.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: p.brandInk,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (up) const _Arrow(up: true),
        pill,
        if (!up) const _Arrow(up: false),
      ],
    );
  }
}
