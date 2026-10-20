part of '../onboarding_art.dart';

// ───────────────────── 第 5 页：三个藏起来的手势 ─────────────────────

class GesturesArt extends StatelessWidget {
  const GesturesArt({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _GestureRow(
          art: _DayCellArt(),
          title: '长按日历格子',
          text: '直接记这一天的账',
        ),
        SizedBox(height: 9),
        _GestureRow(
          art: _SwipeMonthArt(),
          title: '月历左右滑',
          text: '翻上 / 下个月',
        ),
        SizedBox(height: 9),
        _GestureRow(
          art: _SwipeRowArt(),
          title: '流水行向左滑',
          text: '露出「删除」，点了才删',
        ),
      ],
    );
  }
}

class _GestureRow extends StatelessWidget {
  const _GestureRow({
    required this.art,
    required this.title,
    required this.text,
  });

  final Widget art;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return MiniScreen(
      padding: const EdgeInsets.all(9),
      child: Row(
        children: <Widget>[
          SizedBox(width: 74, child: art),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Tok.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ① 日历格子 + 手指（长按）。
class _DayCellArt extends StatelessWidget {
  const _DayCellArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 40,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Tok.paper,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Tok.ink, width: 1.8),
            ),
            child: const Text(
              '15',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Tok.ink,
              ),
            ),
          ),
          const Positioned(
            right: 0,
            bottom: 0,
            child: HighlightBox(
              radius: 8,
              child: Icon(
                Icons.touch_app_rounded,
                size: 13,
                color: Tok.brandDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ② 月历 + 左右双向箭头。
class _SwipeMonthArt extends StatelessWidget {
  const _SwipeMonthArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: <Widget>[
              for (int i = 0; i < 9; i++)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: i == 4 ? Tok.brandTint2 : Tok.line,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
            ],
          ),
          const HighlightBox(
            radius: 8,
            child: Icon(Icons.swap_horiz_rounded, size: 13, color: Tok.brandDeep),
          ),
        ],
      ),
    );
  }
}

/// ③ 流水行左滑露出红色「删除」。
class _SwipeRowArt extends StatelessWidget {
  const _SwipeRowArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Tok.ink, width: 1.8),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Center(
              child: Text(
                '-28.00',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Tok.red,
                ),
              ),
            ),
          ),
          Container(
            width: 22,
            alignment: Alignment.center,
            color: Tok.red,
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 13,
              color: Tok.paper,
            ),
          ),
        ],
      ),
    );
  }
}
