part of '../receipt_page.dart';

/// 三步进度条（选图 / 核对 / 完成）。
class _ReceiptStepBar extends StatelessWidget {
  const _ReceiptStepBar({required this.step});

  final int step;

  static const List<String> _labels = <String>['选图', '核对', '完成'];

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _labels.length; i++) ...<Widget>[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: (i + 1) <= step ? p.ink : p.line,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (i + 1) <= step ? p.brand : p.track,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.ink, width: 2),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: (i + 1) <= step ? p.onBrand : p.ink2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: (i + 1) <= step ? p.ink : p.ink2,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 提示条种类（决定配色与图标）。
enum _ReceiptNoticeKind { tip, warn, error }

/// 一行提示条（不阻断，只说明）。
class _ReceiptNotice extends StatelessWidget {
  const _ReceiptNotice({required this.text, required this.kind});

  final String text;
  final _ReceiptNoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final (Color bg, Color fg, IconData icon) = switch (kind) {
      _ReceiptNoticeKind.tip => (p.track, p.ink2, Icons.info_outline),
      _ReceiptNoticeKind.warn => (p.brandTint, p.brandInk, Icons.error_outline),
      _ReceiptNoticeKind.error => (p.redTint, p.redInk, Icons.warning_amber_rounded),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Tok.rMd),
        border: p.inkBorder(on: bg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态小胶囊（成功 / 退款 / 失败 / 取消 / 待付款 / 不明）。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReceiptStatus status;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final (Color bg, Color fg) = switch (status) {
      ReceiptStatus.ok => (p.greenTint, p.green),
      ReceiptStatus.refund => (p.blueTint, p.blue),
      ReceiptStatus.failed || ReceiptStatus.cancelled => (p.redTint, p.red),
      ReceiptStatus.pending => (p.brandTint, p.brandInk),
      ReceiptStatus.unknown => (p.track, p.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.ink, width: 1.5),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// 需要用户确认的问题清单。
class _IssueList extends StatelessWidget {
  const _IssueList({required this.draft});

  final ReceiptDraft draft;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '需要你确认',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final ReceiptIssue issue in draft.issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    issue.blocking
                        ? Icons.cancel_outlined
                        : Icons.error_outline,
                    size: 14,
                    color: issue.blocking ? p.red : p.brandInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.message,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: issue.blocking ? p.redInk : p.ink2,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 多个金额时的一排候选（点一下换金额）。
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.amounts,
    required this.currentCents,
    required this.onPick,
  });

  final List<int> amounts;
  final int? currentCents;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '识别到多个金额，点一下换成你要记的那个',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.ink2,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final int cents in amounts)
              ToonChip(
                label: '¥${centsToYuan(cents)}',
                selected: cents == currentCents,
                onTap: () => onPick(cents),
              ),
          ],
        ),
      ],
    );
  }
}

/// 识别原文（默认折叠 —— 只在用户想核对时才看）。
class _RawTextBlock extends StatelessWidget {
  const _RawTextBlock({
    required this.text,
    required this.expanded,
    required this.elapsedMs,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final int elapsedMs;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ToonPress(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: p.ink2,
                ),
                const SizedBox(width: 6),
                Text(
                  '查看识别原文（${elapsedMs}ms）',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.track,
              borderRadius: BorderRadius.circular(Tok.rMd),
              border: p.inkBorder(on: p.track),
            ),
            child: SelectableText(
              text.isEmpty ? '（没有识别到文字）' : text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: p.ink2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// 截图缩略图（文件可能已不存在 —— 静默降级成一个图标）。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              color: p.track,
              child: Icon(Icons.image_not_supported_outlined, size: 18, color: p.ink3),
            ),
      ),
    );
  }
}
