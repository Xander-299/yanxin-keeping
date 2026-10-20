part of '../toon.dart';

// ────────────────────────────── 卡片 ──────────────────────────────

/// 白底 + 墨色描边 + 硬阴影的卡片。
class ToonCard extends StatelessWidget {
  const ToonCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = Tok.rLg,
    this.color = Tok.paper,
    this.shadow = 4,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color color;
  final double shadow;
  final VoidCallback? onTap;

  /// 内部列表要「贴边」时打开（描边内裁切，避免子项盖住圆角）。
  final bool clip;

  @override
  Widget build(BuildContext context) {
    Widget box = Container(
      margin: margin,
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: Tok.cardDeco(color: color, radius: radius, shadow: shadow),
      child: child,
    );
    if (onTap != null) {
      box = ToonPress(onTap: onTap, child: box);
    }
    return box;
  }
}
