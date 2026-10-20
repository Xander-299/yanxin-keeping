part of '../search_overlay.dart';

/// 未输入时的引导：说清能搜哪几类字段（示例点一下填进输入框）+ 最近搜过的关键词。
class _Intro extends StatelessWidget {
  const _Intro({
    required this.history,
    required this.onPick,
    required this.onPickHistory,
    required this.onClearHistory,
  });

  /// 最近搜索过的关键词（已按最近优先排序，最多 10 条）。
  final List<String> history;

  final ValueChanged<String> onPick;
  final ValueChanged<String> onPickHistory;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    // ⚠️ 这里**不能**用 SingleChildScrollView：Scrollable 会以 opaque 命中整块下方区域，
    // 点提示块以外的玻璃空白就关不掉浮层了（真机走查抓到的）。Align 只占内容高度，空白可穿透。
    // 内容约 180dp（带历史约 250dp），正常手机（逻辑高 ≥ 480）放得下，不需要滚动兜底。
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: ToonCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '输入分类、账户、备注或金额开始搜索',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '分类名（餐饮 / 交通）· 账户名（招行 / 支付宝）· 备注（房租）\n'
                '金额（88 命中 88.00、188.00）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String example in _examples)
                    ToonChip(
                      label: example,
                      selected: false,
                      onTap: () => onPick(example),
                    ),
                ],
              ),
              if (history.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Text(
                      '最近搜过',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Tok.ink2,
                      ),
                    ),
                    const Spacer(),
                    ToonButton(
                      key: const ValueKey<String>('search-history-clear'),
                      label: '清空历史',
                      kind: ToonButtonKind.ghost,
                      small: true,
                      onPressed: onClearHistory,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String keyword in history)
                      ToonChip(
                        key: ValueKey<String>('search-history-$keyword'),
                        label: keyword,
                        selected: false,
                        onTap: () => onPickHistory(keyword),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '搜的是当前账本的全时间流水，最多显示 $kSearchResultLimit 条\n'
                '顶上「时间」可只看本月 / 近 3 月',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态示例关键词：点一下就填进输入框，省得用户猜「能搜什么」。
const List<String> _examples = <String>['餐饮', '房租', '88', '工资'];

/// 有输入但没有命中（原型：小猪吉祥物 + 一句清空引导）。
class _NoResult extends StatelessWidget {
  const _NoResult({
    required this.keyword,
    required this.range,
    required this.onClear,
  });

  final String keyword;
  final SearchRange range;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // 同 _Intro：Align 只占内容高度，块外空白可穿透关闭（别用 Scrollable）
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: ToonCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const PigMascot(size: 52),
              const SizedBox(height: 10),
              Text(
                '没有匹配「$keyword」的账单',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // 区间收窄是常见「搜不到」原因，这里点一句（默认全部时不啰嗦）
                range == SearchRange.all
                    ? '换个分类名、账户名、备注里的字，或金额里的数字试试'
                    : '当前只搜「${kRangeLabels[range]}」，换回「全部」或换个词试试',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                ),
              ),
              const SizedBox(height: 12),
              ToonButton(
                label: '清空输入',
                kind: ToonButtonKind.ghost,
                small: true,
                onPressed: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 浮层里的面板统一用 `ToonCard`（白底 + 墨色描边 + 硬阴影）：玻璃下面就是首页内容，
// 文字需要一个实底才稳，原型 `.search-tip` / `.resbar` 也是实心白卡。
