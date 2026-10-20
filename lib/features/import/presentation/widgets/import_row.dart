part of '../import_page.dart';

// ────────────────────────────── 预览列表行 ──────────────────────────────

class _ImpRow extends StatelessWidget {
  const _ImpRow({
    required this.index,
    required this.row,
    required this.cancelled,
    required this.onToggle,
  });

  final int index;
  final ParsedRow row;
  final bool cancelled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final bool income = row.direction == 'income';
    final String estimate = categorizeRow(row).categoryName;
    return ToonPress(
      key: ValueKey<String>('imp-row-$index'),
      dx: 2,
      dy: 2,
      onTap: onToggle,
      child: Container(
        color: cancelled ? p.canvas2 : p.paper,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            _CheckBox(on: !cancelled),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${row.counterparty}'
                    '${row.product.isEmpty ? '' : ' · ${row.product}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cancelled ? p.ink3 : p.ink,
                      decoration: cancelled
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtTime(row.occurredAt)} · $estimate',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${income ? '+' : '-'}${centsToYuan(row.amountCents)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cancelled ? p.ink3 : (income ? p.green : p.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方勾选框（原型 `.cb`：22 网格 + 2.5px 描边 + 硬阴影）。
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? p.brand : p.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.ink, width: 2.5),
        boxShadow: p.hard(d: 1.5),
      ),
      child: on ? Icon(Icons.check, size: 14, color: p.onBrand) : null,
    );
  }
}

/// 文字链按钮（原型 `.linkbtn`）。
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonPress(
      dx: 1.5,
      dy: 1.5,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: p.brandDeep,
            decoration: TextDecoration.underline,
            decorationThickness: 2,
          ),
        ),
      ),
    );
  }
}
