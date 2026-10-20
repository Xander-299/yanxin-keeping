part of '../onboarding_art.dart';

// ─────────────────── 第 4 页：翻月箭头 + 预算铅笔 ───────────────────

class MonthBudgetArt extends StatelessWidget {
  const MonthBudgetArt({super.key});

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Align(
                alignment: Alignment.centerRight,
                child: HighlightBox(
                  radius: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _MiniRoundButton(glyph: '‹'),
                      SizedBox(width: 3),
                      _MiniRoundButton(glyph: '›'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '本月支出',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: p.ink2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '1,286.00',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: p.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Callout(label: '换月份（不能翻到未来）'),
        const SizedBox(height: 14),
        MiniScreen(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: <Widget>[
              Text(
                '本月预算',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '¥2000.00',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: p.brandDeep,
                ),
              ),
              const Spacer(),
              HighlightBox(
                radius: 9,
                child: Icon(Icons.edit_outlined, size: 15, color: p.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Callout(label: '点这里改预算'),
      ],
    );
  }
}
