part of '../onboarding_art.dart';

class _Arrow extends StatelessWidget {
  const _Arrow({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(12, 14), painter: _ArrowPainter(up: up));
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.up});

  final bool up;

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
        ..color = Tok.brand
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    final Path head = Path()
      ..moveTo(x, tipY)
      ..lineTo(x - 4.5, headY)
      ..lineTo(x + 4.5, headY)
      ..close();
    canvas.drawPath(head, Paint()..color = Tok.brand);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up;
}

class _MiniRoundButton extends StatelessWidget {
  const _MiniRoundButton({required this.glyph});

  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Tok.paper,
        shape: BoxShape.circle,
        border: Border.all(color: Tok.ink, width: 1.6),
      ),
      child: Text(
        glyph,
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w900,
          color: Tok.ink,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Tok.line, width: 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: Tok.ink2),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Tok.ink,
            ),
          ),
        ],
      ),
    );
  }
}
