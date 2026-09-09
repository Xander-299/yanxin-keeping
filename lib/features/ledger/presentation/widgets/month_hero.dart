/// 首页结余主卡：琥珀渐变 + 本月支出大数字 + 收入/结余 + 月份切换 ‹ ›。
///
/// 视觉对齐 app_template/home_ui.jpg 的 hero 卡（浅琥珀底、深色字）。
library;

import 'package:flutter/material.dart';

import '../../application/month_summary.dart';

/// hero 卡深色文字基色（琥珀底上的深棕）。
const Color kHeroInk = Color(0xFF241503);

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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFE8C2), Color(0xFFFFC978)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '$month月 · 支出',
                style: TextStyle(
                  color: kHeroInk.withValues(alpha: 0.65),
                  fontSize: 13,
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
          const SizedBox(height: 6),
          Text(
            summary.expenseYuan,
            style: const TextStyle(
              color: kHeroInk,
              fontSize: 38,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _HeroCell(label: '收入', value: summary.incomeYuan),
              const SizedBox(width: 28),
              _HeroCell(label: '结余', value: summary.balanceYuan),
            ],
          ),
        ],
      ),
    );
  }
}

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
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: enabled ? 0.08 : 0.04),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: kHeroInk.withValues(alpha: enabled ? 0.9 : 0.35),
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HeroCell extends StatelessWidget {
  const _HeroCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: kHeroInk.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: kHeroInk,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
