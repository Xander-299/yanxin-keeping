part of '../toon.dart';

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
        style: TextStyle(
          fontSize: small ? 13.5 : 15,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
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
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
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
