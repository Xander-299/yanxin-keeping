part of '../onboarding_art.dart';

// ────────────────────── 第 3 页：首页右上三个图标 ──────────────────────

class MiniHeaderArt extends StatelessWidget {
  const MiniHeaderArt({super.key});

  static const List<IconData> _icons = <IconData>[
    Icons.search_rounded,
    Icons.receipt_long_rounded,
    Icons.bar_chart_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '默认账本',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: p.ink,
                  ),
                ),
              ),
              Icon(Icons.expand_more, size: 15, color: p.ink),
              const SizedBox(width: 4),
              for (final IconData icon in _icons)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: HighlightBox(
                    radius: 9,
                    child: _MiniIconBox(icon: icon),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _Legend(icon: Icons.search_rounded, label: '搜流水'),
            SizedBox(width: 8),
            _Legend(icon: Icons.receipt_long_rounded, label: '报表'),
            SizedBox(width: 8),
            _Legend(icon: Icons.bar_chart_rounded, label: '统计'),
          ],
        ),
      ],
    );
  }
}

/// 迷你图标按钮（对应真件 `ToonIconButton(boxed: true)`）。
class _MiniIconBox extends StatelessWidget {
  const _MiniIconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.ink, width: 1.6),
      ),
      child: Icon(icon, size: 14, color: p.ink),
    );
  }
}
