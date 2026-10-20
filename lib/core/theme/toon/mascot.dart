part of '../toon.dart';

/// 小猪存钱罐吉祥物（原型 `#i-mascot`，64 网格）。
///
/// 耳朵 → 脸 → 鼻子 → 眼 → 鼻孔 → 腮红，顺序与原型一致（脸的填充会压住耳朵下沿）。
///
/// 它是**画在品牌底上的插画**，所以填充默认用 `p.veil`（白）、描边用 `p.decorInk`
/// （恒深色）—— 两者都不跟主题反色，否则深色主题下会得到「白底白描边」的一团。
class PigMascot extends StatelessWidget {
  const PigMascot({
    super.key,
    this.size = 64,
    this.body,
    this.snoutColor,
    this.rotate = false,
  });

  final double size;

  /// 身体填充；`null` = 白（`p.veil`）。
  final Color? body;

  /// 鼻子填充；`null` = 奶白（`p.snout`）。
  final Color? snoutColor;

  /// 原型 hero 上的小猪是歪着头的（6°）。
  final bool rotate;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Widget pig = CustomPaint(
      size: Size(size, size),
      painter: _PigPainter(
        body: body ?? p.veil,
        snout: snoutColor ?? p.snout,
        ink: p.decorInk,
        blush: p.blush,
      ),
    );
    if (!rotate) return pig;
    return Transform.rotate(angle: 6 * math.pi / 180, child: pig);
  }
}

class _PigPainter extends CustomPainter {
  const _PigPainter({
    required this.body,
    required this.snout,
    required this.ink,
    required this.blush,
  });

  final Color body;
  final Color snout;
  final Color ink;
  final Color blush;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = ink;
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
        ..color = ink,
    );

    // 眼 + 鼻孔
    final Paint inkFill = Paint()..color = ink;
    canvas.drawCircle(const Offset(25.4, 31), 2.8, inkFill);
    canvas.drawCircle(const Offset(38.6, 31), 2.8, inkFill);
    canvas.drawCircle(const Offset(29.7, 41.5), 1.35, inkFill);
    canvas.drawCircle(const Offset(34.3, 41.5), 1.35, inkFill);

    // 腮红
    final Paint blushPaint = Paint()..color = blush.withValues(alpha: 0.7);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(19, 38.5), width: 7.2, height: 4.6),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(45, 38.5), width: 7.2, height: 4.6),
      blushPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PigPainter old) =>
      old.body != body ||
      old.snout != snout ||
      old.ink != ink ||
      old.blush != blush;
}

/// 四角星贴纸（原型 `#i-sparkle`，24 网格）。
class Sparkle extends StatelessWidget {
  const Sparkle({
    super.key,
    this.size = 21,
    this.fill,
    this.opacity = 1,
  });

  final double size;

  /// 填充；`null` = 白（`p.veil`，贴纸画在品牌底上）。
  final Color? fill;

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size(size, size),
        painter: _SparklePainter(fill: fill ?? p.veil, ink: p.decorInk),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.fill, required this.ink});

  final Color fill;
  final Color ink;

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
        ..color = ink,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparklePainter old) =>
      old.fill != fill || old.ink != ink;
}
