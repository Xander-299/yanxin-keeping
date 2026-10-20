part of '../onboarding_art.dart';

// ────────────── 第 6 页：资产页的 `+` / 账户行 + 报表三档 ──────────────

class AssetsReportsArt extends StatelessWidget {
  const AssetsReportsArt({super.key});

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '资产',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: p.ink,
                    ),
                  ),
                  const Spacer(),
                  const HighlightBox(
                    radius: 9,
                    child: _MiniIconBox(icon: Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              HighlightBox(
                radius: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.paper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 13,
                        color: p.ink2,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '现金',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '¥286.88',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: p.ink2,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 13, color: p.ink2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Callout(label: '+ 加账户；点账户行 = 编辑'),
        const SizedBox(height: 14),
        MiniScreen(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '报表',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: ToonSeg(
                  labels: const <String>['明细', '分类', '账户'],
                  index: 1,
                  onChanged: (int _) {},
                  small: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Callout(label: '三档换视角看同一批流水'),
      ],
    );
  }
}

// ──────────────────────── 第 7 页：完成 ────────────────────────

class DoneArt extends StatelessWidget {
  const DoneArt({super.key});

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return SizedBox(
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: p.brandTint,
              shape: BoxShape.circle,
              border: p.inkBorder(),
            ),
          ),
          const PigMascot(size: 92, rotate: true),
          const Positioned(top: 14, right: 84, child: Sparkle(size: 24)),
          Positioned(
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: p.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.ink, width: 2),
                boxShadow: p.hard(d: 2.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.person_rounded, size: 13, color: p.ink2),
                  const SizedBox(width: 4),
                  Text(
                    '我的',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 13, color: p.ink2),
                  Text(
                    '新手引导',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: p.brandDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
