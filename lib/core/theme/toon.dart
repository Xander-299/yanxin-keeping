/// F7.6 卡通控件库 —— 对齐页面原型的通用组件。
///
/// 全部零新依赖：描边用 [Border]，硬阴影用 `BoxShadow(blurRadius: 0)`，
/// 小猪存钱罐与四角星用 `CustomPainter` 按原型坐标（64 / 24 网格）复刻。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

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

/// 虚线分割线（原型 `repeating-linear-gradient` 的等价物）。
class ToonDashedLine extends StatelessWidget {
  const ToonDashedLine({
    super.key,
    this.height = 2,
    this.dash = 6,
    this.gap = 5,
    this.color = Tok.dash,
  });

  final double height;
  final double dash;
  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashPainter(color: color, dash: dash, gap: gap, thickness: height),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({
    required this.color,
    required this.dash,
    required this.gap,
    required this.thickness,
  });

  final Color color;
  final double dash;
  final double gap;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.square;
    final double y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      final double end = math.min(x + dash, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.dash != dash || old.gap != gap || old.thickness != thickness;
}

// ────────────────────────────── 按钮 ──────────────────────────────

/// 按钮形态：见原型 `.btn.primary / .tonal / .ghost / .danger`。
enum ToonButtonKind { primary, tonal, ghost, danger }

/// 胶囊按钮（48 高，small 为 36）。
class ToonButton extends StatelessWidget {
  const ToonButton({
    super.key,
    this.label,
    this.icon,
    this.child,
    required this.onPressed,
    this.kind = ToonButtonKind.primary,
    this.small = false,
    this.block = false,
  });

  final String? label;
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onPressed;
  final ToonButtonKind kind;
  final bool small;
  final bool block;

  Color get _bg => switch (kind) {
    ToonButtonKind.primary => Tok.brand,
    ToonButtonKind.tonal => Tok.brandTint,
    ToonButtonKind.ghost => Tok.paper,
    ToonButtonKind.danger => Tok.redTint,
  };

  Color get _fg => switch (kind) {
    ToonButtonKind.primary => Tok.brandInk,
    ToonButtonKind.tonal => Tok.brandDeep,
    ToonButtonKind.ghost => Tok.ink,
    ToonButtonKind.danger => Tok.red,
  };

  @override
  Widget build(BuildContext context) {
    final double d = small ? 2.5 : 4;
    final Widget body = Container(
      height: small ? 36 : 48,
      padding: EdgeInsets.symmetric(horizontal: small ? 15 : 20),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
        border: Tok.inkBorder(),
        boxShadow: Tok.hard(d: d),
      ),
      child: Row(
        mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: small ? 16 : 18, color: _fg),
            if (label != null || child != null) const SizedBox(width: 6),
          ],
          if (child != null)
            child!
          else if (label != null)
            Text(
              label!,
              style: TextStyle(
                fontSize: small ? 13 : 15,
                fontWeight: FontWeight.w800,
                color: _fg,
              ),
            ),
        ],
      ),
    );

    final Widget pressed = ToonPress(onTap: onPressed, child: body);
    if (!block) return pressed;
    return SizedBox(width: double.infinity, child: pressed);
  }
}

/// 40×40 图标按钮。
///
/// [boxed] = 白底 + 描边 + 小硬阴影（首页 header 那种）；
/// [muted] = 虚线描边、三级灰（建设中占位）。
class ToonIconButton extends StatelessWidget {
  const ToonIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.muted = false,
    this.boxed = false,
    this.size = 40,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool muted;
  final bool boxed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Color fg = muted ? Tok.ink3 : Tok.ink;
    final Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: boxed && !muted ? Tok.paper : null,
        borderRadius: BorderRadius.circular(13),
        border: boxed
            ? Border.all(color: muted ? Tok.ink3 : Tok.ink, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
        boxShadow: boxed && !muted ? Tok.hard(d: 2.5) : null,
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );

    final Widget tappable = ToonPress(
      dx: 2,
      dy: 2,
      onTap: onPressed,
      child: Center(child: button),
    );
    return tooltip == null ? tappable : Tooltip(message: tooltip!, child: tappable);
  }
}

// ────────────────────────────── 选择类 ──────────────────────────────

/// 胶囊 chip（**不带对勾**：选中变宽会挤位移，F7.5-a 真机教训）。
class ToonChip extends StatelessWidget {
  const ToonChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Tok.brand : Tok.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Tok.ink, width: 2),
          boxShadow: Tok.hard(d: 2.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Tok.brandInk : Tok.ink,
          ),
        ),
      ),
    );
  }
}

/// 分段控件（原型 `.seg`）：白底描边胶囊 + 选中项填品牌色。
class ToonSeg extends StatelessWidget {
  const ToonSeg({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.small = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(999),
        border: Tok.inkBorder(),
        boxShadow: Tok.hard(d: 2.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
              child: ToonPress(
                dx: 1.5,
                dy: 1.5,
                onTap: () => onChanged(i),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: small ? 12 : 18,
                    vertical: small ? 5 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: i == index ? Tok.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: i == index ? Tok.ink : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: small ? 12 : 13.5,
                      fontWeight: FontWeight.w800,
                      color: i == index ? Tok.brandInk : Tok.ink2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 行式表单字段（原型 `.field`）：`label | value | 附加 | ›`。
class ToonField extends StatelessWidget {
  const ToonField({
    super.key,
    required this.label,
    this.value,
    this.placeholder = false,
    this.trailing,
    this.onTap,
    this.dashedTop = false,
    this.child,
    this.valueColor,
  });

  final String label;
  final String? value;
  final bool placeholder;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dashedTop;
  final Widget? child;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Tok.ink2,
              ),
            ),
          ),
          Expanded(
            child: child ??
                Text(
                  value ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: valueColor ??
                        (placeholder ? Tok.ink3 : Tok.ink),
                  ),
                ),
          ),
          if (trailing != null) ...<Widget>[trailing!, const SizedBox(width: 6)],
          const Icon(Icons.chevron_right, size: 18, color: Tok.ink2),
        ],
      ),
    );

    final Widget body = onTap == null ? row : ToonPress(onTap: onTap, child: row);
    if (!dashedTop) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[const ToonDashedLine(), body],
    );
  }
}

// ────────────────────────────── 装饰件 ──────────────────────────────

/// 分类 / 账本用的字母头像（圆角方块 + 描边 + 硬阴影）。
class ToonAvatar extends StatelessWidget {
  const ToonAvatar({
    super.key,
    required this.text,
    this.bg = Tok.brandTint,
    this.fg = Tok.brandDeep,
    this.small = false,
  });

  final String text;
  final Color bg;
  final Color fg;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final double s = small ? 34 : 38;
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(small ? 12 : 13),
        border: Border.all(color: Tok.ink, width: 2),
        boxShadow: Tok.hard(d: 2),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: small ? 13.5 : 15, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

/// 预算环形进度（原型 `.ring`：58 网格，外圈墨色描边靠底环露出）。
class ToonRing extends StatelessWidget {
  const ToonRing({
    super.key,
    required this.progress,
    required this.color,
    required this.text,
    this.size = 62,
  });

  final double progress;
  final Color color;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size(size - 4, size - 4),
            painter: _RingPainter(progress: progress.clamp(0, 1), color: color),
          ),
          Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = (size.width - 8) / 2;
    const double pi2 = math.pi * 2;

    // 1) 墨色粗底环：彩色弧画上去后两侧自然露出 1.5px 描边
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Tok.ink,
    );
    // 2) 底槽
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Tok.track,
    );
    // 3) 进度弧
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        pi2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// 小猪存钱罐吉祥物（原型 `#i-mascot`，64 网格）。
///
/// 耳朵 → 脸 → 鼻子 → 眼 → 鼻孔 → 腮红，顺序与原型一致（脸的填充会压住耳朵下沿）。
class PigMascot extends StatelessWidget {
  const PigMascot({
    super.key,
    this.size = 64,
    this.body = Tok.paper,
    this.snoutColor = Tok.snout,
    this.rotate = false,
  });

  final double size;
  final Color body;
  final Color snoutColor;

  /// 原型 hero 上的小猪是歪着头的（6°）。
  final bool rotate;

  @override
  Widget build(BuildContext context) {
    final Widget pig = CustomPaint(
      size: Size(size, size),
      painter: _PigPainter(body: body, snout: snoutColor),
    );
    if (!rotate) return pig;
    return Transform.rotate(angle: 6 * math.pi / 180, child: pig);
  }
}

class _PigPainter extends CustomPainter {
  const _PigPainter({required this.body, required this.snout});

  final Color body;
  final Color snout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Tok.ink;
    final Paint fill = Paint()..color = body;

    // 耳朵（两个三角）
    final Path earL = Path()
      ..moveTo(15, 14.5)
      ..lineTo(23, 22.5)
      ..lineTo(11.5, 24.5)
      ..close();
    final Path earR = Path()
      ..moveTo(49, 14.5)
      ..lineTo(41, 22.5)
      ..lineTo(52.5, 24.5)
      ..close();
    for (final Path ear in <Path>[earL, earR]) {
      canvas.drawPath(ear, fill);
      canvas.drawPath(ear, stroke);
    }

    // 脸
    canvas.drawCircle(const Offset(32, 35), 20, fill);
    canvas.drawCircle(const Offset(32, 35), 20, stroke);

    // 鼻子
    final Rect nose = Rect.fromCenter(
      center: const Offset(32, 41.5),
      width: 13.6,
      height: 10.2,
    );
    canvas.drawOval(nose, Paint()..color = snout);
    canvas.drawOval(
      nose,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Tok.ink,
    );

    // 眼 + 鼻孔
    final Paint inkFill = Paint()..color = Tok.ink;
    canvas.drawCircle(const Offset(25.4, 31), 2.8, inkFill);
    canvas.drawCircle(const Offset(38.6, 31), 2.8, inkFill);
    canvas.drawCircle(const Offset(29.7, 41.5), 1.35, inkFill);
    canvas.drawCircle(const Offset(34.3, 41.5), 1.35, inkFill);

    // 腮红
    final Paint blush = Paint()..color = Tok.blush.withValues(alpha: 0.7);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(19, 38.5), width: 7.2, height: 4.6),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(45, 38.5), width: 7.2, height: 4.6),
      blush,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PigPainter old) => old.body != body || old.snout != snout;
}

/// 四角星贴纸（原型 `#i-sparkle`，24 网格）。
class Sparkle extends StatelessWidget {
  const Sparkle({super.key, this.size = 21, this.fill = Tok.paper, this.opacity = 1});

  final double size;
  final Color fill;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(size: Size(size, size), painter: _SparklePainter(fill: fill)),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.fill});

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final Path star = Path()
      ..moveTo(12, 2.5)
      ..lineTo(14.3, 9.7)
      ..lineTo(21.5, 12)
      ..lineTo(14.3, 14.3)
      ..lineTo(12, 21.5)
      ..lineTo(9.7, 14.3)
      ..lineTo(2.5, 12)
      ..lineTo(9.7, 9.7)
      ..close();
    canvas.drawPath(star, Paint()..color = fill);
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = Tok.ink,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.fill != fill;
}

/// 段落标题（原型 `.sec`）：前面一个描边圆点 + 标题。
class ToonSectionTitle extends StatelessWidget {
  const ToonSectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 16, 6),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Tok.brand,
              shape: BoxShape.circle,
              border: Border.all(color: Tok.ink, width: 2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
