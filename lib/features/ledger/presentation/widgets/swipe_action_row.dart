/// F7.8 左滑露出动作的行（零新依赖，手写滑动件）。
///
/// 语义：内容**只向左移**（`endToStart`），右侧露出一个固定宽度的动作区；
/// 点动作区才执行 —— **不做「滑走即删」**（软删除不可恢复，见 SPEC-F7.8 §4）。
///
/// 单开协调：外层持一个 [ValueNotifier]（值为当前展开行的 id），传进来后
/// 本行只在 `openRow.value == rowId` 时保持展开，其它行展开时自动收起。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/toon.dart';

/// 动作区宽度：够放「垃圾桶图标 + 删除」两字。
const double kSwipeActionWidth = 84;

/// 行程占比达到多少算「愿意打开」（SPEC-F7.8 §3）。
const double kSwipeOpenRatio = 0.45;

/// 甩动速度达到多少 px/s 也算打开（向左为负）。
const double kSwipeFlingSpeed = 350;

/// 开合判定（纯函数，便于单测）。
///
/// [dx] = 松手时内容已左移的距离（0..[actionWidth]）；
/// [velocity] = 松手瞬间的水平速度（px/s，向左为负）。
bool resolveSwipeOpen({
  required double dx,
  required double velocity,
  double actionWidth = kSwipeActionWidth,
  double ratio = kSwipeOpenRatio,
  double flingSpeed = kSwipeFlingSpeed,
}) {
  if (actionWidth <= 0) return false;
  if ((dx / actionWidth).clamp(0.0, 1.0) >= ratio) return true;
  return velocity <= -flingSpeed;
}

/// 左滑露出右侧动作区的行。
class SwipeActionRow extends StatefulWidget {
  const SwipeActionRow({
    super.key,
    required this.child,
    required this.onAction,
    this.rowId,
    this.openRow,
    this.actionLabel = '删除',
    this.actionIcon = Icons.delete_outline_rounded,
    this.enabled = true,
  });

  /// 行内容（通常是 `TxTile`）。
  final Widget child;

  /// 点动作区后执行；**执行完无论结果如何都收起本行**（删成功→该行随数据消失，
  /// 取消确认框→视觉上就是回弹）。
  final Future<void> Function() onAction;

  /// 本行 id 与「当前展开行」的协调器；不传 = 各自独立（也能用，只是不互斥）。
  final String? rowId;
  final ValueNotifier<String?>? openRow;

  final String actionLabel;
  final IconData actionIcon;

  /// false = 纯展示（不响应滑动，也不渲染动作区）。
  final bool enabled;

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow>
    with SingleTickerProviderStateMixin {
  /// 0 = 关闭，1 = 全开；`value * kSwipeActionWidth` 即位移。
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 0,
  );

  double get _dx => _anim.value * kSwipeActionWidth;

  @override
  void initState() {
    super.initState();
    widget.openRow?.addListener(_onOpenRowChanged);
  }

  @override
  void didUpdateWidget(covariant SwipeActionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openRow != widget.openRow) {
      oldWidget.openRow?.removeListener(_onOpenRowChanged);
      widget.openRow?.addListener(_onOpenRowChanged);
    }
    if (oldWidget.rowId != widget.rowId) _close();
  }

  @override
  void dispose() {
    widget.openRow?.removeListener(_onOpenRowChanged);
    _anim.dispose();
    super.dispose();
  }

  void _onOpenRowChanged() {
    if (widget.openRow?.value != widget.rowId) _close();
  }

  void _close() {
    if (_anim.value != 0) _anim.reverse();
  }

  void _onDragStart(DragStartDetails _) => _anim.stop();

  void _onDragUpdate(DragUpdateDetails details) {
    // delta.dx 向左为负 → 减去它即「值增大」= 越滑越开
    final double next = _anim.value - details.delta.dx / kSwipeActionWidth;
    _anim.value = next.clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final bool open = resolveSwipeOpen(
      dx: _dx,
      velocity: details.velocity.pixelsPerSecond.dx,
    );
    if (open) {
      // 通知协调器：本行展开 → 其它行自行收起
      if (widget.openRow != null && widget.rowId != null) {
        widget.openRow!.value = widget.rowId;
      }
      _anim.forward();
    } else {
      if (widget.openRow?.value == widget.rowId) widget.openRow!.value = null;
      _anim.reverse();
    }
  }

  Future<void> _runAction() async {
    await widget.onAction();
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 只注册横向识别器 → 竖向仍归外层滚动 / 月历翻月（手势竞技场按轴判定）
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      // 展开时整行点击 = 收起。未展开时内层 `ToonPress` 会赢手势竞技场，
      // 这里不会被调用 → 点行进编辑页的既有行为不变。
      onTap: () {
        if (_anim.value > 0.001) _close();
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (BuildContext context, Widget? child) {
          final bool open = _anim.value > 0.001;
          return Stack(
            children: <Widget>[
              // 动作区钉在右侧、上下撑满（Stack 会按行高给约束）
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: kSwipeActionWidth,
                child: _ActionPane(
                  label: widget.actionLabel,
                  icon: widget.actionIcon,
                  onTap: () => unawaited(_runAction()),
                ),
              ),
              Transform.translate(
                offset: Offset(-_dx, 0),
                // 展开时行本体不接手势 → 整行点击落到外层的「收起」上
                child: IgnorePointer(
                  ignoring: open,
                  // 行必须自带**不透明**底：`TxTile` 本身没有背景色（白是外层卡片给的），
                  // 否则 Stack 底层的红色动作区会「透」过行露出来 —— 未滑开就能看到一条红。
                  // 真机走查抓到（第一版漏了这层，见 `docs/acceptance-F7.8-swipe-delete.md`）。
                  child: ColoredBox(color: Tok.paper, child: child),
                ),
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// 右侧动作区：红底 + 白图标 + 白字（SPEC-F7.8 §3）。
class _ActionPane extends StatelessWidget {
  const _ActionPane({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 0,
      dy: 0,
      onTap: onTap,
      child: ColoredBox(
        color: Tok.red,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: Tok.paper),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Tok.paper,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
