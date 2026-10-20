part of '../toon.dart';

/// 按钮形态：见原型 `.btn.primary / .tonal / .ghost / .danger`。
enum ToonButtonKind { primary, tonal, ghost, danger }

/// 胶囊按钮（48 高，small 为 36）。
class ToonButton extends StatelessWidget {
  const ToonButton({
    super.key,
    this.label,
    this.icon,
    this.child,
    required this.onPressed,
    this.kind = ToonButtonKind.primary,
    this.small = false,
    this.block = false,
  });

  final String? label;
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onPressed;
  final ToonButtonKind kind;
  final bool small;
  final bool block;

  Color get _bg => switch (kind) {
    ToonButtonKind.primary => Tok.brand,
    ToonButtonKind.tonal => Tok.brandTint,
    ToonButtonKind.ghost => Tok.paper,
    ToonButtonKind.danger => Tok.redTint,
  };

  Color get _fg => switch (kind) {
    ToonButtonKind.primary => Tok.brandInk,
    ToonButtonKind.tonal => Tok.brandDeep,
    ToonButtonKind.ghost => Tok.ink,
    ToonButtonKind.danger => Tok.red,
  };

  @override
  Widget build(BuildContext context) {
    final double d = small ? 2.5 : 4;
    final Widget body = Container(
      height: small ? 36 : 48,
      padding: EdgeInsets.symmetric(horizontal: small ? 15 : 20),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
        border: Tok.inkBorder(),
        boxShadow: Tok.hard(d: d),
      ),
      child: Row(
        mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: small ? 16 : 18, color: _fg),
            if (label != null || child != null) const SizedBox(width: 6),
          ],
          if (child != null)
            child!
          else if (label != null)
            Text(
              label!,
              style: TextStyle(
                fontSize: small ? 13 : 15,
                fontWeight: FontWeight.w800,
                color: _fg,
              ),
            ),
        ],
      ),
    );

    final Widget pressed = ToonPress(onTap: onPressed, child: body);
    if (!block) return pressed;
    return SizedBox(width: double.infinity, child: pressed);
  }
}

/// 40×40 图标按钮。
///
/// [boxed] = 白底 + 描边 + 小硬阴影（首页 header 那种）；
/// [muted] = 虚线描边、三级灰（建设中占位）。
class ToonIconButton extends StatelessWidget {
  const ToonIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.muted = false,
    this.boxed = false,
    this.size = 40,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool muted;
  final bool boxed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Color fg = muted ? Tok.ink3 : Tok.ink;
    // 原型 `.hdr .iconbtn` = 白底实线墨框 + 硬阴影；
    // `.hdr .iconbtn.muted` = 白底**虚线**墨框、无阴影（「建设中」入口）。
    final bool dashed = boxed && muted;
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: boxed && !muted ? Tok.paper : null,
        borderRadius: BorderRadius.circular(13),
        border: boxed && !dashed
            ? Border.all(color: Tok.ink, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
        boxShadow: boxed && !muted ? Tok.hard(d: 2.5) : null,
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );
    if (dashed) {
      button = ToonDashedBorder(
        radius: 13,
        color: Tok.ink3,
        background: Tok.paper,
        child: button,
      );
    }

    final Widget tappable = ToonPress(
      dx: 2,
      dy: 2,
      onTap: onPressed,
      child: Center(child: button),
    );
    return tooltip == null
        ? tappable
        : Tooltip(message: tooltip!, child: tappable);
  }
}
