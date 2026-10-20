part of '../toon.dart';

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
    final ToonPalette p = context.toon;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: p.brand,
              shape: BoxShape.circle,
              border: Border.all(color: p.ink, width: 2),
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
