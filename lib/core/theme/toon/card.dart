part of '../toon.dart';

// ────────────────────────────── 卡片 ──────────────────────────────

/// 卡片底 + 墨色描边 + 硬阴影的卡片。
class ToonCard extends StatelessWidget {
  const ToonCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = Tok.rLg,
    this.color,
    this.shadow = 4,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// 卡片底色；`null` = 主题的卡片色（`p.paper`）。
  final Color? color;

  final double shadow;
  final VoidCallback? onTap;

  /// 内部列表要「贴边」时打开（描边内裁切，避免子项盖住圆角）。
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    Widget box = Container(
      margin: margin,
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: p.cardDeco(
        color: color ?? p.paper,
        radius: radius,
        depth: shadow,
      ),
      child: child,
    );
    if (onTap != null) {
      box = ToonPress(onTap: onTap, child: box);
    }
    return box;
  }
}
