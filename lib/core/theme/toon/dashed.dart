part of '../toon.dart';

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
        painter: _DashPainter(
          color: color,
          dash: dash,
          gap: gap,
          thickness: height,
        ),
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
      old.color != color ||
      old.dash != dash ||
      old.gap != gap ||
      old.thickness != thickness;
}

/// 虚线描边的圆角框 / 正圆（原型 `.hdr .iconbtn.muted` 的虚线方框、
/// `.eb-ic` 的虚线圆）。
///
/// 走 `Path.computeMetrics()` 分段画：手写循环只能画直线，圆弧段画不了。
/// [background] 非空时先铺底，绘制顺序由 `CustomPaint` 保证在 child 之下。
class ToonDashedBorder extends StatelessWidget {
  const ToonDashedBorder({
    super.key,
    required this.child,
    this.radius = 13,
    this.circle = false,
    this.color = Tok.ink3,
    this.thickness = 2,
    this.dash = 5,
    this.gap = 4,
    this.background,
  });

  final Widget child;
  final double radius;
  final bool circle;
  final Color color;
  final double thickness;
  final double dash;
  final double gap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        radius: radius,
        circle: circle,
        color: color,
        thickness: thickness,
        dash: dash,
        gap: gap,
        background: background,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.radius,
    required this.circle,
    required this.color,
    required this.thickness,
    required this.dash,
    required this.gap,
    required this.background,
  });

  final double radius;
  final bool circle;
  final Color color;
  final double thickness;
  final double dash;
  final double gap;
  final Color? background;

  @override
  void paint(Canvas canvas, Size size) {
    // 描边居中在路径上，故路径内缩半个线宽，边缘才不会被裁掉
    final double inset = thickness / 2;
    final Rect rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - thickness,
      size.height - thickness,
    );
    final Path path = Path();
    if (circle) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }

    if (background != null) {
      canvas.drawPath(path, Paint()..color = background!);
    }

    final Paint p = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final double end = math.min(d + dash, m.length);
        canvas.drawPath(m.extractPath(d, end), p);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.radius != radius ||
      old.circle != circle ||
      old.color != color ||
      old.thickness != thickness ||
      old.dash != dash ||
      old.gap != gap ||
      old.background != background;
}

// ────────────────────────────── 按钮 ──────────────────────────────

/// 「建设中」占位提示（原型 `data-act="toast"` 的等价物）。
///
/// 统一走这里，避免各页各写一份时长/文案不一致的 SnackBar。
void showWipToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
}
