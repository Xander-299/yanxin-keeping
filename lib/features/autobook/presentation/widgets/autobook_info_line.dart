part of '../auto_book_page.dart';

/// 说明行：标题 + 内容。
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 74,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Tok.ink,
              ),
            ),
          ),
          Expanded(
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
