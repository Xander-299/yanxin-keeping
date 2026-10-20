part of '../search_overlay.dart';

/// 顶部**不透明**提示块：关闭 + 输入框 + 一键清空 + 类型筛选 chips + 时间区间 chips。
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.plan,
    required this.range,
    required this.onClose,
    required this.onClear,
    required this.onToggleType,
    required this.onPickRange,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchPlan plan;
  final SearchRange range;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final ValueChanged<String> onToggleType;
  final ValueChanged<SearchRange> onPickRange;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final bool hasInput = controller.text.trim().isNotEmpty;
    final String? active = plan.typeWord;

    return Material(
      // 不透明：盖住玻璃的上半部分
      color: p.paper,
      child: Container(
        // 原型 `.search-ovl .bar`：底部一条墨色描边
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.ink, width: Tok.bw)),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 8, 0),
                child: Row(
                  children: <Widget>[
                    ToonIconButton(
                      key: const ValueKey<String>('search-close'),
                      icon: Icons.arrow_back,
                      tooltip: '关闭',
                      onPressed: onClose,
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('search-input'),
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        maxLength: kSearchKeywordMaxLength,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          hintText: '搜索分类、账户、备注或金额',
                          border: InputBorder.none,
                          // 主题给输入框统一加了填充 + 描边（表单用），这里要裸输入框
                          filled: false,
                          isDense: true,
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        // 回车 / 键盘「搜索」键 = 一次确定的搜索 → 记进历史
                        onSubmitted: onSubmit,
                      ),
                    ),
                    if (hasInput)
                      ToonIconButton(
                        key: const ValueKey<String>('search-clear'),
                        icon: Icons.close,
                        tooltip: '清空',
                        size: 36,
                        iconSize: 19,
                        onPressed: onClear,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                child: Row(
                  children: <Widget>[
                    for (final String word in kTypeDirectives.keys)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ToonChip(
                          key: ValueKey<String>('search-chip-$word'),
                          label: word,
                          selected: active == word,
                          onTap: () => onToggleType(word),
                        ),
                      ),
                  ],
                ),
              ),
              // 时间区间**独立一行**：与类型 chips 挤同一 Row，360dp 窄屏会溢出
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: <Widget>[
                    Text(
                      '时间',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: p.ink2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (final MapEntry<SearchRange, String> e
                        in kRangeLabels.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ToonChip(
                          key: ValueKey<String>('search-range-${e.value}'),
                          label: e.value,
                          selected: range == e.key,
                          onTap: () => onPickRange(e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
