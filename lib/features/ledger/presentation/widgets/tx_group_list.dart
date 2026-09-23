/// 流水列表：按本地日期分组，倒序展示。
///
/// 视觉对齐页面原型 `.list` + `.group-label`：分组是贴着的小气泡贴纸，
/// 列表是白卡描边 + 硬阴影，组内条目之间用虚线分隔。
library;

import 'package:flutter/material.dart';

import '../../../../core/db/database.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/theme/toon.dart';
import '../../../../core/utils/date.dart';
import '../../../../core/utils/money.dart';

/// 按天分组的流水列表。
///
/// [categoryNameOf] 由外层按 categoryId 查名字；查不到时退回「未分类」。
/// [shrinkWrap] 为 true 时（首页嵌入滚动视图）不自己滚动、去掉底部留白。
class TxGroupList extends StatelessWidget {
  const TxGroupList({
    super.key,
    required this.items,
    required this.categoryNameOf,
    required this.onEdit,
    required this.onDelete,
    this.shrinkWrap = false,
  });

  final List<TxRow> items;
  final String Function(String? categoryId) categoryNameOf;
  final ValueChanged<TxRow> onEdit;
  final ValueChanged<TxRow> onDelete;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final groups = groupByDay<TxRow>(items, (TxRow t) => t.occurredAt);
    return ListView.builder(
      padding: EdgeInsets.only(bottom: shrinkWrap ? 0 : 96),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: groups.length,
      itemBuilder: (BuildContext context, int index) {
        final group = groups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: _GroupChip(label: group.label, count: group.items.length),
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
                          categoryName: categoryNameOf(group.items[i].categoryId),
                          onTap: () => onEdit(group.items[i]),
                          onLongPress: () => onDelete(group.items[i]),
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

/// 日期分组气泡：`今天` / `今天 · 2 笔`。
class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.label, required this.count});

  final String label;
  final int count;

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
          if (count > 1) ...<Widget>[
            const SizedBox(width: 4),
            Text(
              '· $count 笔',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Tok.ink2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条流水。
///
/// [onTap] / [onLongPress] 传空 = **只读行**（报表页用：只展示，不进编辑、不删）。
class TxTile extends StatelessWidget {
  const TxTile({
    super.key,
    required this.tx,
    required this.categoryName,
    this.onTap,
    this.onLongPress,
    this.neutral = false,
  });

  final TxRow tx;
  final String categoryName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 转账行：不算收支方向 → 金额用次级灰、不带 ± 号（SPEC-F7.7 §A.3 口径）。
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = tx.type == 'income';
    final String initial = categoryName.isEmpty ? '?' : categoryName.substring(0, 1);
    // 中国习惯：支出红 / 收入绿（糖果色，对齐原型）
    final Color amountColor = neutral
        ? Tok.ink2
        : (isIncome ? Tok.green : Tok.red);
    final String sign = neutral ? '' : (isIncome ? '+' : '-');
    return ToonPress(
      dx: 0,
      dy: 0,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: <Widget>[
            ToonAvatar(
              text: initial,
              bg: neutral
                  ? Tok.track
                  : (isIncome ? Tok.greenTint : Tok.redTint),
              fg: amountColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              // 分类名与备注同排（原型 `.tx-name` + `.tx-note` 一行）
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (tx.note.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Flexible(
                      flex: 2,
                      child: Text(
                        tx.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tok.ink2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$sign${centsToYuan(tx.amountCents)}',
              style: TextStyle(
                color: amountColor,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
