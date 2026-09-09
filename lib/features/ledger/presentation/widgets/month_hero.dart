/// 首页结余主卡：月份切换 ‹ › + 结余 + 支出/收入。
library;

import 'package:flutter/material.dart';

import '../../application/month_summary.dart';

/// 结余主卡（渐变 + 圆角，对齐旧栈 index.vue 的 hero）。
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
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[primary, primary.withValues(alpha: 0.72)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: primary.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MonthSwitcher(
            year: year,
            month: month,
            canNext: canNext,
            onPrevMonth: onPrevMonth,
            onNextMonth: onNextMonth,
          ),
          const SizedBox(height: 12),
          const Text(
            '结余',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            summary.balanceYuan,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _HeroCell(label: '支出', value: summary.expenseYuan),
              const SizedBox(
                height: 28,
                child: VerticalDivider(color: Colors.white24, width: 32),
              ),
              _HeroCell(label: '收入', value: summary.incomeYuan),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.year,
    required this.month,
    required this.canNext,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final int year;
  final int month;
  final bool canNext;
  final VoidCallback onPrevMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        _RoundButton(label: '‹', onTap: onPrevMonth),
        const SizedBox(width: 12),
        Text(
          '$year年$month月',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        _RoundButton(
          label: '›',
          enabled: canNext,
          onTap: canNext ? onNextMonth : null,
        ),
      ],
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
      radius: 22,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: enabled ? 0.18 : 0.08),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.35),
            fontSize: 20,
            height: 1,
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
