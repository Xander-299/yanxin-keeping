/// 首页结余主卡：品牌色 hero + 本月支出大数字 + 收入/结余 + 月份切换 ‹ ›。
///
/// 视觉对齐页面原型 `.hero`：实心琥珀底 + 3px 墨色描边 + 6px 硬阴影 +
/// 右上角装饰圆 + 小猪存钱罐 + 四角星贴纸。
///
/// 原型的 hero 上还有「小猪摇摆」循环动画，这里**故意不做**：
/// 无限动画会让 widget 测试里的 `pumpAndSettle` 永不收敛。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

import '../../application/month_summary.dart';

/// 结余主卡。
class MonthHero extends StatelessWidget {
  const MonthHero({
    super.key,
    required this.year,
    required this.month,
    required this.summary,
    required this.canNext,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final int year;

  /// 1-12。
  final int month;

  final MonthSummary summary;

  /// 是否能切到下一个月（不能超过当前真实月份）。
  final bool canNext;

  final VoidCallback onPrevMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: p.brandTint,
        borderRadius: BorderRadius.circular(Tok.rXl),
        // hero 恒为琥珀底：**描边必须走 decorInk（恒深）** —— 深色主题下 p.ink 是暖白，
        // 压在琥珀上只有 ~1.3:1，描边会整条消失。
        border: Border.all(color: p.line),
        boxShadow: p.hard(d: 6),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: <Widget>[
          // 右上角装饰圆（原型 `.hero::after`）
          Positioned(
            right: -80,
            top: -110,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 同上：hero 上的「减淡层」只能是 veil（白），不能是 paper ——
                // 深色主题下 paper 是近黑，叠上去会变成个「洞」。
                color: p.veil.withValues(alpha: 0.32),
                border: Border.all(color: p.decorInk.withValues(alpha: 0.16), width: 3),
              ),
            ),
          ),
          // 卡通贴纸（星 + 小猪）已在 2026-10-28 换 Material 3 时移除
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '$month月 · 支出',
                      style: TextStyle(
                        color: p.heroInk.withValues(alpha: 0.78),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _RoundButton(label: '‹', onTap: onPrevMonth),
                    const SizedBox(width: 8),
                    _RoundButton(
                      label: '›',
                      enabled: canNext,
                      onTap: canNext ? onNextMonth : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '¥',
                      style: TextStyle(
                        color: p.heroInk,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: _FadeOnChange(
                        value: summary.expenseYuan,
                        child: Text(
                          summary.expenseYuan,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.heroInk,
                            fontSize: 40,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            shadows: <Shadow>[
                              // 非 const：`p` 来自 Theme，色值不是编译期常量
                              Shadow(
                                color: p.veil.withValues(alpha: 0.85),
                                offset: const Offset(2.5, 2.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _HeroCell(label: '收入', value: summary.incomeYuan),
                    const SizedBox(width: 14),
                    _HeroCell(label: '结余', value: summary.balanceYuan),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// hero 上的翻月圆钮（原型 `.h-nav button`）。
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? p.paper : p.veil.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? p.inkOn(p.brandTint)
                : p.inkOn(p.brandTint).withValues(alpha: 0.4),
            width: 2.5,
          ),
          boxShadow: p.hard(
            d: 2.5,
            color: enabled ? p.decorInk : p.decorInk.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            // 禁用态：钮底是浅琥珀（veil 叠出来的），字必须走 decorInk 才够 3:1
            color: enabled ? p.ink : p.decorInk.withValues(alpha: 0.75),
            fontSize: 17,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// 收入 / 结余气泡（原型 `.h-sub .c`）。
class _HeroCell extends StatelessWidget {
  const _HeroCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      decoration: BoxDecoration(
        // 气泡底 = veil 叠在琥珀上（两套主题下都是「浅琥珀」），配 heroInk 深棕字 ≈6:1。
        // 原来是 paper@0.55：深色主题下 paper 近黑 → 气泡被压成 #88662B，
        // 而 heroInk 恒为深棕 → **2.12:1**（浅色 6.00），这就是「深色下看不清」的主因。
        color: p.veil.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: p.inkOn(p.brandTint).withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: p.heroInk.withValues(alpha: 0.8),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: _FadeOnChange(
              value: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.heroInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数字变化时做一次 150ms 淡入（不改变布局，也不打断 `baseline` 对齐）。
///
/// 为什么不用 `AnimatedSwitcher`：它内部是 `Stack`，会把 Row 的基线对齐打断；
/// 这里只包一层 `FadeTransition`（RenderProxyBox 会透传基线），切换月份时旧数字直接换掉、
/// 新数字从 0 → 1 淡进来 —— 比硬切柔和，也不会有两个数字叠在一起。
class _FadeOnChange extends StatefulWidget {
  const _FadeOnChange({required this.value, required this.child});

  /// 用来判断「值变了没有」的标识（金额文本）。
  final String value;
  final Widget child;

  @override
  State<_FadeOnChange> createState() => _FadeOnChangeState();
}

class _FadeOnChangeState extends State<_FadeOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _FadeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c, child: widget.child);
}
