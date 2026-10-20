part of '../toon.dart';

/// 行式表单字段（原型 `.field`）：`label | value | 附加 | ›`。
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
  final bool dashedTop;
  final Widget? child;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Tok.ink2,
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
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? (placeholder ? Tok.ink3 : Tok.ink),
                  ),
                ),
          ),
          if (trailing != null) ...<Widget>[
            trailing!,
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right, size: 18, color: Tok.ink2),
        ],
      ),
    );

    final Widget body = onTap == null
        ? row
        : ToonPress(onTap: onTap, child: row);
    if (!dashedTop) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[const ToonDashedLine(), body],
    );
  }
}
