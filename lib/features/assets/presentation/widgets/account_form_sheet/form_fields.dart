part of '../account_form_sheet.dart';

/// 原型的小标（`.s12.mute2`）：输入框 / chips 上方的字段名。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Tok.ink2,
        ),
      ),
    );
  }
}

/// 墨色描边圆角输入框（原型 `.input`）；内部放裸 `TextField`。
class _BareInput extends StatelessWidget {
  const _BareInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(Tok.rMd),
        border: Tok.inkBorder(),
      ),
      child: child,
    );
  }
}
