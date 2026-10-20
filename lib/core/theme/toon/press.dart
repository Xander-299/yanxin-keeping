part of '../toon.dart';

// ────────────────────────────── 按压反馈 ──────────────────────────────

/// 按下「陷进去」：位移 + 阴影收紧（原型 `.press:active` 的行为）。
///
/// 手势挂在外层盒子上，所以「陷下去」不会让命中区跟着跑。
class ToonPress extends StatefulWidget {
  const ToonPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.dx = 3,
    this.dy = 3,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double dx;
  final double dy;

  @override
  State<ToonPress> createState() => _ToonPressState();
}

class _ToonPressState extends State<ToonPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (TapDownDetails _) => _set(true) : null,
      onTapUp: enabled ? (TapUpDetails _) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          _down ? widget.dx : 0,
          _down ? widget.dy : 0,
          0,
        ),
        child: widget.child,
      ),
    );
  }
}
