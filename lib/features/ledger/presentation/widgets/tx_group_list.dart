/// 流水列表：按本地日期分组，倒序展示。
library;

import 'package:flutter/material.dart';

import '../../../../core/db/database.dart';
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                group.label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (final tx in group.items)
                    TxTile(
                      tx: tx,
                      categoryName: categoryNameOf(tx.categoryId),
                      onTap: () => onEdit(tx),
                      onLongPress: () => onDelete(tx),
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

/// 单条流水。
class TxTile extends StatelessWidget {
  const TxTile({
    super.key,
    required this.tx,
    required this.categoryName,
    required this.onTap,
    required this.onLongPress,
  });

  final TxRow tx;
  final String categoryName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type == 'income';
    final initial = categoryName.isEmpty ? '?' : categoryName.substring(0, 1);
    // 深色主题下的收支配色（中国习惯：支出红 / 收入绿）
    final amountColor = isIncome ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    final sign = isIncome ? '+' : '-';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: amountColor.withValues(alpha: 0.12),
              child: Text(
                initial,
                style: TextStyle(color: amountColor, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(categoryName, style: const TextStyle(fontSize: 15)),
                  if (tx.note.isNotEmpty)
                    Text(
                      tx.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$sign${centsToYuan(tx.amountCents)}',
              style: TextStyle(
                color: amountColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
