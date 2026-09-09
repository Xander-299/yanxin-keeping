/// 本月预算卡 —— **纯占位**：静态数字还原参考图视觉，不接真实预算功能。
///
/// TODO(预算功能)：环形进度 = 已消费/预算；日均消费、剩余可消费按天折算。
library;

import 'package:flutter/material.dart';

/// 预算占位卡。
class BudgetCardPlaceholder extends StatelessWidget {
  const BudgetCardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('本月预算', style: TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                '1,000.00',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.edit_note_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: <Widget>[
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        value: 0.102,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        color: Color(0xFF66BB6A),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    Text(
                      '10.2%',
                      style: TextStyle(fontSize: 12, color: Color(0xFF66BB6A)),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 20),
              _Metric(value: '101.52', label: '已消费'),
              SizedBox(width: 20),
              _Metric(
                value: '898.48',
                label: '剩余额度 ⓘ',
                valueColor: Color(0xFF66BB6A),
              ),
            ],
          ),
          const Divider(height: 20),
          const _DayRow(
            dotColor: Color(0xFFFFC978),
            label: '本月日均消费',
            value: '10.15',
          ),
          const SizedBox(height: 8),
          const _DayRow(
            dotColor: Color(0xFFB39DDB),
            label: '剩余每日可消费',
            value: '42.78',
            valueColor: Color(0xFF66BB6A),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.dotColor,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final Color dotColor;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }
}
