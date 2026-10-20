part of '../auto_book_page.dart';

/// 权限 / 能力状态行。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.ok,
    required this.okText,
    required this.badText,
  });

  final IconData icon;
  final String title;
  final bool ok;
  final String okText;
  final String badText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: Tok.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: ok ? Tok.greenTint : Tok.redTint,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Tok.ink, width: 2),
            ),
            child: Text(
              ok ? okText : badText,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ok ? Tok.green : Tok.redInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
