part of '../onboarding_art.dart';

// ─────────────────────────── 第 1 页：欢迎 ───────────────────────────

class WelcomeArt extends StatelessWidget {
  const WelcomeArt({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 134,
            height: 134,
            decoration: BoxDecoration(
              color: Tok.brandTint,
              shape: BoxShape.circle,
              border: Tok.inkBorder(),
            ),
          ),
          const PigMascot(size: 96, rotate: true),
          const Positioned(top: 10, right: 82, child: Sparkle(size: 26)),
          const Positioned(
            bottom: 18,
            left: 78,
            child: Sparkle(size: 17, fill: Tok.brandTint2),
          ),
        ],
      ),
    );
  }
}

// ──────────────────── 第 2 页：底栏中央的「记一笔」 ────────────────────

class MiniTabBarArt extends StatelessWidget {
  const MiniTabBarArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: const EdgeInsets.all(8),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: Tok.paper,
              borderRadius: BorderRadius.circular(Tok.rSm),
              border: Tok.inkBorder(w: 2),
            ),
            child: const Row(
              children: <Widget>[
                Expanded(
                  child: _MiniTab(
                    icon: Icons.home_rounded,
                    label: '首页',
                  ),
                ),
                Expanded(
                  child: _MiniTab(
                    icon: Icons.calendar_today_rounded,
                    label: '日历',
                  ),
                ),
                Expanded(
                  child: Center(
                    child: HighlightBox(radius: 10, child: _MiniAddSquare()),
                  ),
                ),
                Expanded(
                  child: _MiniTab(
                    icon: Icons.account_balance_wallet_rounded,
                    label: '资产',
                  ),
                ),
                Expanded(
                  child: _MiniTab(
                    icon: Icons.person_rounded,
                    label: '我的',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Callout(label: '记一笔', up: true),
      ],
    );
  }
}

class _MiniTab extends StatelessWidget {
  const _MiniTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 15, color: Tok.ink3),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Tok.ink3,
          ),
        ),
      ],
    );
  }
}

/// 中央「记一笔」：品牌色圆角方块，歪 4°（与真件 `_CenterAddButton` 一致）。
class _MiniAddSquare extends StatelessWidget {
  const _MiniAddSquare();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -4 * 3.1415926535 / 180,
      child: Container(
        width: 30,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Tok.brand,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Tok.ink, width: 1.8),
        ),
        child: const Icon(Icons.add, size: 16, color: Tok.brandInk),
      ),
    );
  }
}
