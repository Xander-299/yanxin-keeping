/// 统计页：分类占比（圆环）+ 近 6 月收支趋势 + 当月汇总。
///
/// 入口：首页 header 的「统计」图标 → `/stats`。月份与首页/日历**各自独立**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';

import '../application/stats_aggregate.dart';
import '../application/stats_controller.dart';
import 'widgets/category_pie.dart';
import 'widgets/trend_bars.dart';

/// 统计页。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
        data: (StatsState state) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _MonthBar(
              year: state.year,
              month: state.month,
              onPrev: () => ref.read(statsProvider.notifier).shiftMonth(-1),
              onNext: () => ref.read(statsProvider.notifier).shiftMonth(1),
            ),
            const SizedBox(height: 12),
            _SummaryCard(summary: state.summary),
            const SizedBox(height: 12),
            _BreakdownCard(
              state: state,
              onKindChanged: (String kind) =>
                  ref.read(statsProvider.notifier).setKind(kind),
            ),
            const SizedBox(height: 12),
            _TrendCard(state: state),
          ],
        ),
      ),
    );
  }
}

/// 月份切换条（‹ 2026年9月 ›），与首页一致的「不能超过当前月」约束。
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.year,
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final int year;
  final int month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: '上一月',
          onPressed: onPrev,
        ),
        Text(
          '$year年$month月',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: '下一月',
          onPressed: canGoNext(year, month) ? onNext : null,
        ),
      ],
    );
  }
}

/// 当月收支汇总卡。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _StatCell(
                label: '收入',
                value: summary.incomeYuan,
                color: const Color(0xFF4CAF50),
              ),
            ),
            Expanded(
              child: _StatCell(
                label: '支出',
                value: summary.expenseYuan,
                color: const Color(0xFFFF6B6B),
              ),
            ),
            Expanded(
              child: _StatCell(
                label: '结余',
                value: summary.balanceYuan,
                color: Tok.brandDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 分类占比卡：支出/收入切换 + 圆环 + 图例。
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.state, required this.onKindChanged});

  final StatsState state;
  final ValueChanged<String> onKindChanged;

  @override
  Widget build(BuildContext context) {
    final slices = state.slices;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '分类占比',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                SizedBox(
                  height: 32,
                  child: SegmentedButton<String>(
                    key: const ValueKey<String>('stats-kind-toggle'),
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: 'expense',
                        label: Text('支出'),
                      ),
                      ButtonSegment<String>(value: 'income', label: Text('收入')),
                    ],
                    selected: <String>{state.kind},
                    // Flutter 3.32+ 起回调改名 onSelectionChanged（onSelected 已移除）
                    onSelectionChanged: (Set<String> v) => onKindChanged(v.first),
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (slices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    state.kind == 'income'
                        ? '${state.year}年${state.month}月还没有收入记录'
                        : '${state.year}年${state.month}月还没有支出记录',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ),
              )
            else
              Row(
                children: <Widget>[
                  CategoryPie(slices: slices),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (var i = 0; i < slices.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _LegendRow(
                              slice: slices[i],
                              color: categoryColor(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 图例一行：色块 + 分类名 + 占比 + 金额。
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.color});

  final CategorySlice slice;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            slice.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text(slice.percentText, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(width: 10),
        Text(
          centsToYuan(slice.cents, group: true),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// 近 6 个月趋势卡。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.state});

  final StatsState state;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '近 6 个月趋势',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _Dot(
                  color: const Color(0xFFFF6B6B),
                  label: '支出',
                  muted: muted,
                ),
                const SizedBox(width: 12),
                _Dot(
                  color: const Color(0xFF4CAF50),
                  label: '收入',
                  muted: muted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TrendBars(points: state.trend, anchorYear: state.year),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label, required this.muted});

  final Color color;
  final String label;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }
}
