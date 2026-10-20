part of '../account_form_sheet.dart';

/// 「跟随类型」文字 chip（ToonChip 同款视觉：胶囊 + 墨描边 + 硬阴影）。
class _FollowTypeChip extends StatelessWidget {
  const _FollowTypeChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: onTap,
      child: Container(
        // 不设 alignment：Wrap 的宽松约束下 alignment 会把 Container 撑满整行。
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? p.brand : p.paper,
          borderRadius: BorderRadius.circular(999),
          border: p.inkBorder(w: 2, on: selected ? p.brand : p.paper),
          boxShadow: p.hard(d: 2.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? p.onBrand : p.ink2,
          ),
        ),
      ),
    );
  }
}

/// 图标选择块（40×40 方块，选中 = 品牌浅底 + 加重阴影）。
class _IconOption extends StatelessWidget {
  const _IconOption({
    super.key,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonPress(
      dx: 1.5,
      dy: 1.5,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.brandTint : p.paper,
          borderRadius: BorderRadius.circular(Tok.rMd),
          border: Border.all(color: p.ink, width: 2),
          boxShadow: p.hard(d: selected ? 3 : 2),
        ),
        child: Icon(
          icon,
          size: 21,
          color: selected ? p.brandDeep : p.ink2,
        ),
      ),
    );
  }
}

/// 颜色圆点（32×32，选中 = 墨色外圈 + 对勾）。
class _ColorOption extends StatelessWidget {
  const _ColorOption({
    super.key,
    required this.color,
    required this.selected,
    this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonPress(
      dx: 1.5,
      dy: 1.5,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: p.ink,
            width: selected ? 2.5 : 2,
          ),
          boxShadow: p.hard(d: selected ? 3 : 2),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 18, color: p.inkOn(color))
            : null,
      ),
    );
  }
}
