part of '../onboarding_art.dart';

class _Arrow extends StatelessWidget {
  const _Arrow({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return CustomPaint(
      size: const Size(12, 14),
      painter: _ArrowPainter(up: up, color: p.brand),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.up, required this.color});

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double x = size.width / 2;
    final double tipY = up ? 0 : size.height;
    final double tailY = up ? size.height : 0;
    final double headY = up ? 5 : size.height - 5;

    canvas.drawLine(
      Offset(x, tailY),
      Offset(x, headY),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    final Path head = Path()
      ..moveTo(x, tipY)
      ..lineTo(x - 4.5, headY)
      ..lineTo(x + 4.5, headY)
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up || old.color != color;
}

class _MiniRoundButton extends StatelessWidget {
  const _MiniRoundButton({required this.glyph});

  final String glyph;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.paper,
        shape: BoxShape.circle,
        border: Border.all(color: p.ink, width: 1.6),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w900,
          color: p.ink,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line, width: 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: p.ink2),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: p.ink,
            ),
          ),
        ],
      ),
    );
  }
}
