part of '../toon.dart';

/// 段落标题（Material 3）：`titleMedium` 文本 + 可选尾部动作。
///
/// 旧版前面有个「描边圆点」（卡通风），M3 里用字重与字号建立层级，不需要装饰圆点。
class ToonSectionTitle extends StatelessWidget {
  const ToonSectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 12, 8),
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
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
