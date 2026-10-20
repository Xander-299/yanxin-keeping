part of '../toon.dart';

// ────────────────────────────── 选择类 ──────────────────────────────

/// 胶囊 chip（**不带对勾**：选中变宽会挤位移，F7.5-a 真机教训）。
class ToonChip extends StatelessWidget {
  const ToonChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Tok.brand : Tok.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Tok.ink, width: 2),
          boxShadow: Tok.hard(d: 2.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Tok.brandInk : Tok.ink,
          ),
        ),
      ),
    );
  }
}

/// 分段控件（原型 `.seg`）：白底描边胶囊 + 选中项填品牌色。
class ToonSeg extends StatelessWidget {
  const ToonSeg({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.small = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(999),
        border: Tok.inkBorder(),
        boxShadow: Tok.hard(d: 2.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
              child: ToonPress(
                dx: 1.5,
                dy: 1.5,
                onTap: () => onChanged(i),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: small ? 12 : 18,
                    vertical: small ? 5 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: i == index ? Tok.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: i == index ? Tok.ink : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: small ? 12 : 13.5,
                      fontWeight: FontWeight.w800,
                      color: i == index ? Tok.brandInk : Tok.ink2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
