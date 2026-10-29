part of '../toon.dart';

// ────────────────────────────── 选择类 ──────────────────────────────

/// 胶囊 chip（Material 3 `FilterChip`，**不带对勾**：选中变宽会挤位移，F7.5-a 真机教训）。
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
    final ToonPalette p = context.toon;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onTap == null ? null : (bool _) => onTap!(),
      selectedColor: p.brandTint,
      backgroundColor: p.canvas2,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: selected ? p.brandInk : p.ink2,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 分段控件（Material 3 `SegmentedButton`）：选中项填 `secondaryContainer`。
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
    return SegmentedButton<int>(
      segments: <ButtonSegment<int>>[
        for (int i = 0; i < labels.length; i++)
          ButtonSegment<int>(
            value: i,
            label: Text(labels[i]),
            tooltip: null,
          ),
      ],
      selected: <int>{index},
      showSelectedIcon: false,
      onSelectionChanged: (Set<int> s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      style: SegmentedButton.styleFrom(
        visualDensity: small ? VisualDensity.compact : VisualDensity.standard,
        textStyle: TextStyle(
          fontSize: small ? 12 : 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
