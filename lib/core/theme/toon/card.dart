part of '../toon.dart';

// ────────────────────────────── 卡片 ──────────────────────────────

/// 卡片：Material 3 `Card`（surface 底 + elevation + 圆角，**无描边**）。
///
/// 参数名沿用旧版（`shadow` = 阴影强度、`radius`、`color`、`clip`），语义按 M3 映射：
/// `shadow` 0 → elevation 0，1–3 → 1，≥4 → 2。
class ToonCard extends StatelessWidget {
  const ToonCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = Tok.rLg,
    this.color,
    this.shadow = 1,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// 卡片底色；`null` = 主题 surface。
  final Color? color;

  /// 阴影强度（映射到 M3 elevation）。
  final double shadow;

  final VoidCallback? onTap;

  /// 内部列表要「贴边」时打开（裁切到圆角内）。
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final double elevation = shadow <= 0
        ? 0
        : shadow >= 4
        ? 2
        : 1;
    final Widget body = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
    return Card(
      margin: margin ?? EdgeInsets.zero,
      color: color ?? p.paper,
      elevation: elevation,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}
