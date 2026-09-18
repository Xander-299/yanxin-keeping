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

/// hero 卡深色文字基色（琥珀底上的深棕）。
const Color kHeroInk = Tok.heroInk;

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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: Tok.brand,
        borderRadius: BorderRadius.circular(Tok.rXl),
        border: Border.all(color: Tok.ink, width: 3),
        boxShadow: Tok.hard(d: 6),
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
                color: Tok.paper.withValues(alpha: 0.32),
                border: Border.all(color: Tok.ink.withValues(alpha: 0.16), width: 3),
              ),
            ),
          ),
          // 星贴纸 + 小猪（歪 6°）。**画在内容之前** —— 原型里也是内容压住小猪，
          // 否则 64px 的小猪会盖掉右上角的翻月按钮。
          const Positioned(right: 86, top: 12, child: Sparkle(size: 21)),
          const Positioned(
            right: 24,
            bottom: 14,
            child: Sparkle(size: 15, opacity: 0.9),
          ),
          const Positioned(
            right: 2,
            top: 22,
            child: PigMascot(size: 64, rotate: true),
          ),
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
                        color: kHeroInk.withValues(alpha: 0.78),
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
                    const Text(
                      '¥',
                      style: TextStyle(
                        color: kHeroInk,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        summary.expenseYuan,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kHeroInk,
                          fontSize: 40,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          shadows: <Shadow>[
                            Shadow(
                              color: Color(0xD9FFFFFF),
                              offset: Offset(2.5, 2.5),
                            ),
                          ],
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
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Tok.paper : Tok.paper.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? Tok.ink : Tok.ink.withValues(alpha: 0.3),
            width: 2.5,
          ),
          boxShadow: Tok.hard(
            d: 2.5,
            color: enabled ? Tok.ink : Tok.ink.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Tok.ink : Tok.ink.withValues(alpha: 0.35),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      decoration: BoxDecoration(
        color: Tok.paper.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Tok.ink.withValues(alpha: 0.55), width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: kHeroInk.withValues(alpha: 0.8),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kHeroInk,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
