/// 报表页的两类列表：
/// - [ReportDayList]：明细档，按本地日倒序分组（组头带笔数与当日支出合计）
/// - [ReportGroupList]：分类档 / 账户档，行可点击展开该组的流水
///
/// 流水行复用首页的 [TxTile]（**只读**：报表页不做编辑 / 删除，见 SPEC §A.4）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_group_list.dart';

import '../../application/report_aggregate.dart';

/// 分组行的形态。
enum ReportGroupKind {
  /// 分类档：一行一个分类（单方向金额 + 占比条）。
  category,

  /// 账户档：一行一个账户（支出 / 收入 / 转账 + 笔数）。
  account,
}

// ────────────────────────────── 明细档 ──────────────────────────────

/// 明细档列表：一天一块，组头 `今天 9月23日 周三 · 3 笔 · 支出 ¥88.88`。
class ReportDayList extends StatelessWidget {
  const ReportDayList({
    super.key,
    required this.items,
    required this.categoryNameOf,
  });

  final List<TxRow> items;
  final String Function(String?) categoryNameOf;

  @override
  Widget build(BuildContext context) {
    final List<DayGroup<TxRow>> groups = groupByDay<TxRow>(
      items,
      (TxRow t) => t.occurredAt,
    );
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: groups.length,
      itemBuilder: (BuildContext context, int index) {
        final DayGroup<TxRow> group = groups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: _DayChip(
                label: reportDayLabel(group.items.first.occurredAt),
                count: group.items.length,
                expenseCents: sumCentsOf(group.items, kReportExpense),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              decoration: Tok.cardDeco(),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < group.items.length; i++)
                    Column(
                      children: <Widget>[
                        if (i > 0) const ToonDashedLine(),
                        TxTile(
                          tx: group.items[i],
                          categoryName: categoryNameOf(
                            group.items[i].categoryId,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 日期分组气泡：`9月8日 周一 · 2 笔 · 支出 ¥35.00`。
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.count,
    required this.expenseCents,
  });

  final String label;
  final int count;
  final int expenseCents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Tok.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Tok.ink, width: 2),
        boxShadow: Tok.hard(d: 2.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 4),
          Text(
            '· $count 笔 · 支出 ¥${centsToYuan(expenseCents)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Tok.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 只读流水卡（转账段用）：与明细档同款白卡 + 虚线分隔。
class ReportTxCard extends StatelessWidget {
  const ReportTxCard({
    super.key,
    required this.items,
    required this.categoryNameOf,
    this.neutral = false,
  });

  final List<TxRow> items;
  final String Function(String?) categoryNameOf;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: Tok.cardDeco(),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            Column(
              children: <Widget>[
                if (i > 0) const ToonDashedLine(),
                TxTile(
                  tx: items[i],
                  categoryName: categoryNameOf(items[i].categoryId),
                  neutral: neutral,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ────────────────────────── 分类档 / 账户档 ──────────────────────────

/// 可展开的分组列表（分类档 / 账户档共用）。
class ReportGroupList extends StatefulWidget {
  const ReportGroupList({
    super.key,
    required this.groups,
    required this.kind,
    required this.categoryNameOf,
    this.type = kReportExpense,
    this.sectionTotalCents = 0,
  });

  final List<ReportGroup> groups;
  final ReportGroupKind kind;
  final String Function(String?) categoryNameOf;

  /// 分类档的方向（决定金额与占比条颜色）；账户档忽略。
  final String type;

  /// 分类档该段的合计（占比条的分母）。
  final int sectionTotalCents;

  @override
  State<ReportGroupList> createState() => _ReportGroupListState();
}

class _ReportGroupListState extends State<ReportGroupList> {
  /// 展开的组 key；展开状态**不持久化**（SPEC §A.4）。
  final Set<String> _expanded = <String>{};

  void _toggle(String key) {
    setState(() {
      // remove 返回 true = 本来就展开 → 收起；false = 展开
      if (!_expanded.remove(key)) _expanded.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ReportGroup group in widget.groups)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: Tok.cardDeco(),
              child: Column(
                children: <Widget>[
                  ToonPress(
                    dx: 2,
                    dy: 2,
                    onTap: () => _toggle(group.key),
                    child: widget.kind == ReportGroupKind.category
                        ? _CategoryRow(
                            group: group,
                            type: widget.type,
                            ratio: widget.sectionTotalCents == 0
                                ? 0
                                : group.totalCents / widget.sectionTotalCents,
                            expanded: _expanded.contains(group.key),
                          )
                        : _AccountRow(
                            group: group,
                            expanded: _expanded.contains(group.key),
                          ),
                  ),
                  if (_expanded.contains(group.key)) ..._detail(group),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 展开区：虚线分隔的只读流水行（超上限截断 + 尾注）。
  List<Widget> _detail(ReportGroup group) {
    final List<TxRow> rows = group.items.length > kReportDetailLimit
        ? group.items.sublist(0, kReportDetailLimit)
        : group.items;
    return <Widget>[
      const ToonDashedLine(),
      for (int i = 0; i < rows.length; i++)
        Column(
          children: <Widget>[
            if (i > 0) const ToonDashedLine(),
            TxTile(
              tx: rows[i],
              categoryName: widget.categoryNameOf(rows[i].categoryId),
            ),
          ],
        ),
      if (rows.length < group.items.length)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Text(
            '仅显示前 ${rows.length} 笔（共 ${group.items.length} 笔），可到首页按天查看',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Tok.ink2,
            ),
          ),
        ),
    ];
  }
}

/// 分类档一行：头像 + 名称 + 笔数 + 占比条 + 金额。
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.group,
    required this.type,
    required this.ratio,
    required this.expanded,
  });

  final ReportGroup group;
  final String type;
  final double ratio;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = type == kReportIncome;
    final Color color = isIncome ? Tok.green : Tok.red;
    final Color bg = isIncome ? Tok.greenTint : Tok.redTint;
    final String name = group.title;
    final double safeRatio = ratio.clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: <Widget>[
          ToonAvatar(
            text: name.isEmpty ? '?' : name.substring(0, 1),
            bg: bg,
            fg: color,
            small: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${group.txCount} 笔',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Tok.ink2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(child: _RatioBar(ratio: safeRatio, color: color)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${(safeRatio * 100).toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Tok.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            centsToYuan(group.totalCents, group: true),
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          _ExpandIcon(expanded: expanded),
        ],
      ),
    );
  }
}

/// 账户档一行：头像 + 名称 + 支出/收入/转账 + 笔数。
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.group, required this.expanded});

  final ReportGroup group;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final String name = group.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: <Widget>[
          ToonAvatar(
            text: name.isEmpty ? '?' : name.substring(0, 1),
            small: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                // Wrap 而不是 Row：金额位数多时（如 ¥1,234,567.89）自动换行，不会溢出
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: <Widget>[
                    _MiniAmount(
                      label: '支出',
                      cents: group.expenseCents,
                      color: Tok.red,
                    ),
                    _MiniAmount(
                      label: '收入',
                      cents: group.incomeCents,
                      color: Tok.green,
                    ),
                    _MiniAmount(
                      label: '转账',
                      cents: group.transferCents,
                      color: Tok.ink2,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${group.txCount} 笔',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Tok.ink2,
            ),
          ),
          _ExpandIcon(expanded: expanded),
        ],
      ),
    );
  }
}

/// 「支出 ¥12.00」小字。
class _MiniAmount extends StatelessWidget {
  const _MiniAmount({
    required this.label,
    required this.cents,
    required this.color,
  });

  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label ¥${centsToYuan(cents, group: true)}',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

/// 占比条：底槽 + 左对齐的填充（`ratio` 0..1）。
class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 7,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: ColoredBox(color: Tok.track)),
            // heightFactor 必须显式给 1：FractionallySizedBox 在松约束下会缩成
            // 子节点的自然高度（ColoredBox 无子节点 = 0），进度条就看不见了。
            if (ratio > 0)
              FractionallySizedBox(
                widthFactor: ratio,
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// 展开指示箭头（收起朝下 / 展开朝上）。
class _ExpandIcon extends StatelessWidget {
  const _ExpandIcon({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Icon(
        expanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: Tok.ink2,
      ),
    );
  }
}
