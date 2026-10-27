part of '../toon.dart';

/// 按钮形态：`primary`（Filled）/ `tonal`（Filled tonal）/ `ghost`（Outlined）/ `danger`（Filled + error）。
enum ToonButtonKind { primary, tonal, ghost, danger }

/// 按钮（Material 3）：胶囊形、48 高（`small` 36）。
///
/// 旧版是「描边 + 硬阴影 + 按下位移」，现在交给 M3 的 Filled/Outlined 方案：
/// 文字与图标颜色由 `ButtonStyle` 统一给，调用点只关心 `kind`。
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

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final ButtonStyle base = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(block ? double.infinity : 0, small ? 36 : 48),
      ),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: small ? 14 : 20),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        TextStyle(fontSize: small ? 13 : 14, fontWeight: FontWeight.w600),
      ),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
    );

    final Widget content = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: small ? 16 : 18),
          if (label != null || child != null) const SizedBox(width: 8),
        ],
        if (child != null)
          child!
        else if (label != null)
          Text(label!, overflow: TextOverflow.ellipsis),
      ],
    );

    final Widget button = switch (kind) {
      ToonButtonKind.primary => FilledButton(
        onPressed: onPressed,
        style: base,
        child: content,
      ),
      ToonButtonKind.tonal => FilledButton.tonal(
        onPressed: onPressed,
        style: base,
        child: content,
      ),
      ToonButtonKind.ghost => OutlinedButton(
        onPressed: onPressed,
        style: base,
        child: content,
      ),
      ToonButtonKind.danger => FilledButton(
        onPressed: onPressed,
        style: base.copyWith(
          backgroundColor: WidgetStatePropertyAll<Color>(p.redTint),
          foregroundColor: WidgetStatePropertyAll<Color>(p.redInk),
        ),
        child: content,
      ),
    };

    return block ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 图标按钮（Material 3）：`boxed` → `IconButton.filledTonal`，否则纯图标。
///
/// `muted`（「建设中」占位）与 `size` / `iconSize` 保留为兼容参数。
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
    final Color fg = muted ? p.ink3 : p.ink2;
    final Widget button = IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: fg),
      tooltip: tooltip,
      style: boxed
          ? IconButton.styleFrom(
              backgroundColor: p.canvas2,
              foregroundColor: fg,
              minimumSize: Size.square(size),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tok.rMd),
              ),
            )
          : IconButton.styleFrom(foregroundColor: fg),
    );
    return button;
  }
}
