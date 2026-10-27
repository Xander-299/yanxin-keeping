part of '../toon.dart';

// ────────────────────────────── 按压反馈 ──────────────────────────────

/// 点击反馈：Material 水波纹（`InkWell`）。
///
/// 历史：卡通版是「按下位移 + 阴影收紧」（`transform: translate(dx,dy)`）。换 M3 后
/// 反馈交给 ripple，`dx` / `dy` 只为不改 42 处调用点而保留，**不再生效**。
class ToonPress extends StatelessWidget {
  const ToonPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.dx = 0,
    this.dy = 0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 已废弃：仅为兼容旧调用点保留。
  final double dx;

  /// 已废弃：仅为兼容旧调用点保留。
  final double dy;

  @override
  Widget build(BuildContext context) {
    if (onTap == null && onLongPress == null) return child;
    return InkWell(onTap: onTap, onLongPress: onLongPress, child: child);
  }
}
