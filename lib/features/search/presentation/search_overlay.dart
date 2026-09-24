/// 搜索浮层：按**分类名 / 备注 / 金额**检索当前账本的全部流水，并支持类型筛选。
///
/// 入口：首页 header 的搜索图标 → [showSearchOverlay]（见 `docs/SPEC-F7.5-search-overlay.md`）。
///
/// F7.5 起**不再是独立路由**（原 `/search` 已删除）：改为全屏 dialog，
/// 首页留在页面栈里当背景，提示块以下的毛玻璃透出首页 —— 视觉上不再像「换了个 App」。
/// dialog 内部 `ref` / `context.push` 均可用：浮层挂在 `ProviderScope` 与 `Router` 之下。
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_delete_dialog.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_group_list.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

import '../application/search_controller.dart';
import '../application/search_history.dart';
import '../application/search_query.dart';

/// 单次展示的结果上限：超出只显示最近 N 条（列表太长反而不好找）。
const int kSearchResultLimit = 200;

/// 毛玻璃模糊强度（SPEC Q3：先给 12，真机看过再调）。
const double kSearchGlassSigma = 12;

/// 打开搜索浮层（覆盖在当前页之上，不新增路由）。
Future<void> showSearchOverlay(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '搜索',
    // 遮罩自己画：要毛玻璃不要纯色，所以让 barrier 透明
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) => const SearchOverlay(),
    transitionBuilder: (_, Animation<double> anim, _, Widget child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

/// 搜索浮层主体。
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// 日期区间档（F7.7 D 批）：默认「全部」。
  ///
  /// 与类型词不同，区间**不进输入框**（没有对应的可解析指令词，写进去只会让
  /// `parsePlan` 把它当普通关键词 → 恒搜不到），改为浮层单选状态 + chip 高亮可见。
  SearchRange _range = SearchRange.all;

  @override
  void initState() {
    super.initState();
    // 输入变化只影响浮层（关键词不进 provider），直接 setState 刷新结果
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  /// 填入关键词并保持焦点（示例、chip、一键清空共用）。
  void _setKeyword(String value) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _focus.requestFocus();
  }

  /// 一键清空：清掉输入并重新聚焦，可以马上接着敲下一个关键词。
  void _clear() => _setKeyword('');

  /// 记一条搜索历史（只记关键词；纯类型词 / 空串不记，见 `search_history.dart`）。
  void _remember(String raw) {
    final String keyword = stripTypeWords(raw).trim();
    if (keyword.isEmpty) return;
    unawaited(ref.read(searchHistoryProvider.notifier).remember(keyword));
  }

  /// 点历史词：填进输入框 + 提前到历史最前（最近用过的排前面）。
  void _pickHistory(String keyword) {
    _setKeyword(keyword);
    _remember(keyword);
  }

  void _pickRange(SearchRange range) {
    if (_range == range) return;
    setState(() => _range = range);
  }

  /// 点类型 chip：已选中的再点 = 取消；否则换成该类型，剩余关键词原样保留。
  ///
  /// 词是**真的填进输入框**（SPEC Q1）：条件始终可见、可编辑、可一键清空，
  /// chip 高亮由输入框内容推导 → 不会出现「chip 亮着但输入框是空的」这种双份状态。
  void _toggleType(String word) {
    final String? current = parsePlan(_input.text).type;
    final String rest = stripTypeWords(_input.text);
    final String next;
    if (current == kTypeDirectives[word]) {
      next = rest; // 取消筛选
    } else {
      // 选中时补一个**尾随空格**：用户接着敲关键词就是「仅支出 11」，分隔开才会
      // 被解析成「类型 + 关键词」；否则拼成「仅支出11」不认指令、恒为空（真机走查发现的）。
      next = rest.isEmpty ? '$word ' : '$word $rest';
    }
    _setKeyword(next);
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _edit(TxRow tx) async {
    // 点了结果 = 这次搜索有用 → 记进历史（与回车、点历史 chip 同一套触发点）
    _remember(_input.text);
    await context.push('/record', extra: tx.id);
    if (!mounted) return;
    // 编辑可能改到金额 / 分类 / 备注，回来必须重查
    // （不依赖 .then：壳路由下回调不兑现，与 import_page 同一处理）
    await ref.read(searchProvider.notifier).refresh();
  }

  Future<void> _confirmDelete(TxRow tx) async {
    if (!await confirmDeleteTx(context)) return;
    await ref.read(transactionRepositoryProvider).softDelete(tx.id);
    await ref.read(searchProvider.notifier).refresh();
    // 首页 / 日历 / 统计是同屏数据的其它视图，常驻 Notifier 不会自己感知删除
    // （与 home_page 的删除链路保持一致）
    unawaited(ref.read(ledgerProvider.notifier).refresh());
    unawaited(ref.read(calendarProvider.notifier).refresh());
    unawaited(ref.read(statsProvider.notifier).refresh());
    ref.invalidate(yearDayIndexProvider);
    // 资产页 watch 数据版本号，bump 即重算
    ref.read(dataEpochProvider.notifier).bump();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SearchState> async = ref.watch(searchProvider);
    final SearchPlan plan = parsePlan(_input.text);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          // 1) 毛玻璃铺满全屏；提示块遮住上半部分 → 视觉上「提示块以下才是玻璃」，
          //    比只给下半屏铺玻璃简单，也不会在提示块边缘出现接缝。
          //    点玻璃区即关闭（内容区里可交互的部件会先消费点击）。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: kSearchGlassSigma,
                  sigmaY: kSearchGlassSigma,
                ),
                // 原型 `.glass`：暖白画布 55% + 11px 模糊
                child: ColoredBox(
                  color: Tok.canvas.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          // 2) 提示块（不透明）+ 内容区（浮在玻璃之上）
          Positioned.fill(
            child: Column(
              children: <Widget>[
                _SearchBar(
                  controller: _input,
                  focusNode: _focus,
                  plan: plan,
                  range: _range,
                  onClose: _close,
                  onClear: _clear,
                  onToggleType: _toggleType,
                  onPickRange: _pickRange,
                  onSubmit: _remember,
                ),
                Expanded(
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object e, StackTrace _) =>
                        Center(child: Text('加载失败：$e')),
                    data: (SearchState state) =>
                        _buildResults(state, plan, _range),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(SearchState state, SearchPlan plan, SearchRange range) {
    final List<String> history =
        ref.watch(searchHistoryProvider).value ?? const <String>[];

    // 没有任何条件（无类型词 / 无关键词 / 区间=全部）：给引导而不是「列出全部流水」
    if (!hasAnyFilter(plan, range)) {
      return _Intro(
        history: history,
        onPick: _setKeyword,
        onPickHistory: _pickHistory,
        onClearHistory: () =>
            ref.read(searchHistoryProvider.notifier).clear(),
      );
    }

    final String keyword = plan.text;
    final List<TxRow> hits = filterTx(
      items: state.items,
      categoryNameOf: state.nameOf,
      accountNameOf: state.nameOfAccount,
      query: _input.text,
      range: range,
    );
    if (hits.isEmpty) {
      return _NoResult(
        keyword: _input.text.trim(),
        range: range,
        onClear: _clear,
      );
    }

    final List<TxRow> shown = hits.length > kSearchResultLimit
        ? hits.sublist(0, kSearchResultLimit)
        : hits;

    return Column(
      children: <Widget>[
        _ResultBar(
          shown: shown.length,
          total: hits.length,
          summary: summarize(shown),
          range: range,
        ),
        Expanded(
          child: TxGroupList(
            items: shown,
            categoryNameOf: state.nameOf,
            // 高亮用的关键词：类型词已剥离（「仅支出」不该在行里被标黄）
            highlightQuery: keyword.isEmpty ? null : keyword,
            onEdit: _edit,
            onDelete: _confirmDelete,
          ),
        ),
      ],
    );
  }
}

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
    final bool hasInput = controller.text.trim().isNotEmpty;
    final String? active = plan.typeWord;

    return Material(
      // 不透明：盖住玻璃的上半部分
      color: Tok.paper,
      child: Container(
        // 原型 `.search-ovl .bar`：底部一条墨色描边
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Tok.ink, width: Tok.bw)),
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
                    const Text(
                      '时间',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Tok.ink2,
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Tok.ink2,
                      ),
                    ),
                  ),
                const Spacer(),
                _AmountCell(
                  label: '支出',
                  value: summary.expenseYuan,
                  color: Tok.red,
                ),
                const SizedBox(width: 12),
                _AmountCell(
                  label: '收入',
                  value: summary.incomeYuan,
                  color: Tok.green,
                ),
              ],
            ),
            if (total > shown)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '仅显示最近 $shown 笔，补充关键词可缩小范围',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$label ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Tok.ink2,
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

