part of '../toon.dart';

/// 行式表单字段（Material 3）：`label | value | 附加 | ›`。
///
/// 旧版的「虚线分割」换成 M3 的 `Divider`（hairline）；文字权重从 w800 降到 w500/600。
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

  /// 兼容旧名：现在画的是 M3 分割线（不是虚线）。
  final bool dashedTop;

  final Widget? child;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: p.ink2,
              ),
            ),
          ),
          Expanded(
            child:
                child ??
                Text(
                  value ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? (placeholder ? p.ink3 : p.ink),
                  ),
                ),
          ),
          if (trailing != null) ...<Widget>[
            trailing!,
            const SizedBox(width: 6),
          ],
          if (onTap != null) Icon(Icons.chevron_right, size: 20, color: p.ink3),
        ],
      ),
    );

    final Widget body = onTap == null
        ? row
        : InkWell(onTap: onTap, child: row);
    if (!dashedTop) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[Divider(height: 1, color: p.line), body],
    );
  }
}
