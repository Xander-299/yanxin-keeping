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

  Color _bg(ToonPalette p) => switch (kind) {
    ToonButtonKind.primary => p.brand,
    ToonButtonKind.tonal => p.brandTint,
    ToonButtonKind.ghost => p.paper,
    ToonButtonKind.danger => p.redTint,
  };

  Color _fg(ToonPalette p) => switch (kind) {
    // 亮琥珀底 → 用 onBrand（深浅两套都是深棕）；品牌浅底 → 用 brandInk
    ToonButtonKind.primary => p.onBrand,
    ToonButtonKind.tonal => p.brandDeep,
    ToonButtonKind.ghost => p.ink,
    ToonButtonKind.danger => p.red,
  };

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final double d = small ? 2.5 : 4;
    final Color bg = _bg(p);
    final Color fg = _fg(p);
    final Widget body = Container(
      height: small ? 36 : 48,
      padding: EdgeInsets.symmetric(horizontal: small ? 15 : 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        // 描边跟着**底色**走：primary 是琥珀底 → decorInk；其余底色的 ink 描边不变
        border: p.inkBorder(on: kind == ToonButtonKind.primary ? p.brand : null),
        boxShadow: p.hard(d: d),
      ),
      child: Row(
        mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: small ? 16 : 18, color: fg),
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
                color: fg,
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
/// [boxed] = 卡片底 + 描边 + 小硬阴影（首页 header 那种）；
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
    final ToonPalette p = context.toon;
    final Color fg = muted ? p.ink3 : p.ink;
    // 原型 `.hdr .iconbtn` = 卡片底实线墨框 + 硬阴影；
    // `.hdr .iconbtn.muted` = 卡片底**虚线**墨框、无阴影（「建设中」入口）。
    final bool dashed = boxed && muted;
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: boxed && !muted ? p.paper : null,
        borderRadius: BorderRadius.circular(13),
        border: boxed && !dashed
            ? Border.all(color: p.ink, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
        boxShadow: boxed && !muted ? p.hard(d: 2.5) : null,
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );
    if (dashed) {
      button = ToonDashedBorder(
        radius: 13,
        color: p.ink3,
        background: p.paper,
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
