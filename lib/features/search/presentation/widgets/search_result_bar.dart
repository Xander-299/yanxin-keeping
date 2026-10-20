part of '../search_overlay.dart';

/// 结果条：命中笔数 + 收支合计（复用 `summarize`，与首页 / 统计页口径一致）。
class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.shown,
    required this.total,
    required this.summary,
    required this.range,
  });

  final int shown;
  final int total;
  final MonthSummary summary;
  final SearchRange range;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: ToonCard(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '共 $total 笔',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // 「共 N 笔」占一个独立 Text：既有测试按整串断言，后缀必须分开写
                if (range != SearchRange.all)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '· ${kRangeLabels[range]}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.ink2,
                      ),
                    ),
                  ),
                const Spacer(),
                _AmountCell(
                  label: '支出',
                  value: summary.expenseYuan,
                  color: p.red,
                ),
                const SizedBox(width: 12),
                _AmountCell(
                  label: '收入',
                  value: summary.incomeYuan,
                  color: p.green,
                ),
              ],
            ),
            if (total > shown)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '仅显示最近 $shown 笔，补充关键词可缩小范围',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: p.ink2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountCell extends StatelessWidget {
  const _AmountCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.ink2,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
