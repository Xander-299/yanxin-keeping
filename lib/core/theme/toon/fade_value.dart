part of '../toon.dart';

// ────────────────────────────── 数值淡入 ──────────────────────────────

/// 「值一变就淡入」的包装：默认 150ms，值没变不播。
///
/// 为什么不用 `AnimatedSwitcher`：它内部是 `Stack`，会打断 Row 的**基线对齐**
/// （`¥` 与金额、标签与数值都会错位）；这里用 `FadeTransition` 包一层，
/// `RenderProxyBox` 会透传基线，也不会出现新旧两个数字叠影。
///
/// 用在：hero 主金额、收入/结余气泡、统计页汇总数字、预算条百分比。
class ToonFadeValue extends StatefulWidget {
  const ToonFadeValue({
    super.key,
    required this.value,
    required this.child,
    this.duration = const Duration(milliseconds: 150),
  });

  /// 用来判断「值变了没有」的标识（金额 / 百分比文本本身）。
  final String value;

  final Widget child;

  final Duration duration;

  @override
  State<ToonFadeValue> createState() => _ToonFadeValueState();
}

class _ToonFadeValueState extends State<ToonFadeValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant ToonFadeValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c, child: widget.child);
}
