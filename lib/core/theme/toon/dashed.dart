part of '../toon.dart';

/// 分割线（Material 3）：1dp `outlineVariant`，不再画虚线。
///
/// 参数保留为兼容（`dash` / `gap` 已无作用）。
class ToonDashedLine extends StatelessWidget {
  const ToonDashedLine({
    super.key,
    this.height = 1,
    this.dash = 6,
    this.gap = 5,
    this.color,
  });

  final double height;

  /// 已废弃：虚线不再是 M3 的写法。
  final double dash;

  /// 已废弃：同上。
  final double gap;

  /// 线条颜色；`null` = 主题的 `outlineVariant`。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Divider(height: height, thickness: height, color: color ?? p.dash);
  }
}

/// 圆角框 / 正圆（Material 3）：**实线** outline 描边，可选底色。
///
/// 旧版是手绘虚线（`Path.computeMetrics()` 分段画）；M3 里「空状态 / 占位」
/// 用实线 outline 表达即可，虚线与手绘感一并去掉。
class ToonDashedBorder extends StatelessWidget {
  const ToonDashedBorder({
    super.key,
    required this.child,
    this.radius = 12,
    this.circle = false,
    this.color,
    this.thickness = 1,
    this.dash = 5,
    this.gap = 4,
    this.background,
  });

  final Widget child;
  final double radius;
  final bool circle;
  final Color? color;
  final double thickness;

  /// 已废弃：虚线不再是 M3 的写法。
  final double dash;

  /// 已废弃：同上。
  final double gap;

  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(
          color: color ?? p.line,
          width: thickness,
        ),
      ),
      child: child,
    );
  }
}

// ────────────────────────────── 提示 ──────────────────────────────

/// 「建设中」占位提示。
///
/// 统一走这里，避免各页各写一份时长/文案不一致的 SnackBar。
void showWipToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
}
