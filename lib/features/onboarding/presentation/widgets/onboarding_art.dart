/// F7.14 新手引导的迷你示意图 —— **全部矢量手绘**（不引图片资源）。
///
/// 设计约束（SPEC-F7.14 §3.3）：
/// - 只用 `Tok.*` 令牌与现成 `Toon*` 件，**不出现裸色值**；
/// - 迷你控件**复刻真实比例与同一组 IconData**（底栏 68→54、header 图标 40→26、中央方块 54×48→30×26）；
/// - 目标控件一律用 [HighlightBox] 圈住，配 [Callout] 标签 + 折线箭头。
///
/// 为什么不截图：截图要跟 UI 改版同步重做，还要出多套分辨率资源；手绘件改一处即全站生效。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

/// 迷你「屏幕」外壳：白底 + 墨色描边 + 硬阴影，固定宽 288（窄于任何机型的可用宽度）。
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.width = 288,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: width,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: Tok.cardDeco(radius: Tok.rMd, shadow: 3),
        child: child,
      ),
    );
  }
}

/// 高亮圈：品牌色描边 + 品牌浅底，圈住「这一页要说的是它」。
class HighlightBox extends StatelessWidget {
  const HighlightBox({super.key, required this.child, this.radius = 11});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Tok.brandTint2.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Tok.brand, width: 2),
      ),
      child: child,
    );
  }
}

/// 指引标签 + 折线箭头。[up] = 箭头在标签**上方**并指向上（标签位于目标下方时用）。
class Callout extends StatelessWidget {
  const Callout({super.key, required this.label, this.up = false});

  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Tok.brandTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Tok.brand, width: 1.6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Tok.brandInk,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (up) const _Arrow(up: true),
        pill,
        if (!up) const _Arrow(up: false),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(12, 14), painter: _ArrowPainter(up: up));
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.up});

  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final double x = size.width / 2;
    final double tipY = up ? 0 : size.height;
    final double tailY = up ? size.height : 0;
    final double headY = up ? 5 : size.height - 5;

    canvas.drawLine(
      Offset(x, tailY),
      Offset(x, headY),
      Paint()
        ..color = Tok.brand
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    final Path head = Path()
      ..moveTo(x, tipY)
      ..lineTo(x - 4.5, headY)
      ..lineTo(x + 4.5, headY)
      ..close();
    canvas.drawPath(head, Paint()..color = Tok.brand);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up;
}

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '默认账本',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Tok.ink,
                  ),
                ),
              ),
              const Icon(Icons.expand_more, size: 15, color: Tok.ink),
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
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Tok.ink, width: 1.6),
      ),
      child: Icon(icon, size: 14, color: Tok.ink),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Tok.line, width: 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: Tok.ink2),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Tok.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────── 第 4 页：翻月箭头 + 预算铅笔 ───────────────────

class MonthBudgetArt extends StatelessWidget {
  const MonthBudgetArt({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
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
              SizedBox(height: 10),
              Text(
                '本月支出',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Tok.ink2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '1,286.00',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Tok.ink,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 6),
        Callout(label: '换月份（不能翻到未来）'),
        SizedBox(height: 14),
        MiniScreen(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: <Widget>[
              Text(
                '本月预算',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Tok.ink,
                ),
              ),
              SizedBox(width: 8),
              Text(
                '¥2000.00',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Tok.brandDeep,
                ),
              ),
              Spacer(),
              HighlightBox(
                radius: 9,
                child: Icon(Icons.edit_outlined, size: 15, color: Tok.ink),
              ),
            ],
          ),
        ),
        SizedBox(height: 6),
        Callout(label: '点这里改预算'),
      ],
    );
  }
}

class _MiniRoundButton extends StatelessWidget {
  const _MiniRoundButton({required this.glyph});

  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Tok.paper,
        shape: BoxShape.circle,
        border: Border.all(color: Tok.ink, width: 1.6),
      ),
      child: Text(
        glyph,
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w900,
          color: Tok.ink,
        ),
      ),
    );
  }
}

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

// ────────────── 第 6 页：资产页的 `+` / 账户行 + 报表三档 ──────────────

class AssetsReportsArt extends StatelessWidget {
  const AssetsReportsArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MiniScreen(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Text(
                    '资产',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Tok.ink,
                    ),
                  ),
                  Spacer(),
                  HighlightBox(
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
                    color: Tok.paper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 13,
                        color: Tok.ink2,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '现金',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Tok.ink,
                        ),
                      ),
                      Spacer(),
                      Text(
                        '¥286.88',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Tok.ink2,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 13, color: Tok.ink2),
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
              const Text(
                '报表',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Tok.ink,
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
    return SizedBox(
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: Tok.brandTint,
              shape: BoxShape.circle,
              border: Tok.inkBorder(),
            ),
          ),
          const PigMascot(size: 92, rotate: true),
          const Positioned(top: 14, right: 84, child: Sparkle(size: 24)),
          Positioned(
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Tok.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Tok.ink, width: 2),
                boxShadow: Tok.hard(d: 2.5),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.person_rounded, size: 13, color: Tok.ink2),
                  SizedBox(width: 4),
                  Text(
                    '我的',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Tok.ink,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 13, color: Tok.ink2),
                  Text(
                    '新手引导',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Tok.brandDeep,
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
