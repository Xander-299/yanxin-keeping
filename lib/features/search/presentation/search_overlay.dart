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
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_delete_dialog.dart';
import 'package:yanxin/features/ledger/presentation/widgets/tx_group_list.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

import '../application/search_controller.dart';
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
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
                child: ColoredBox(color: surface.withValues(alpha: 0.55)),
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
                  onClose: _close,
                  onClear: _clear,
                  onToggleType: _toggleType,
                ),
                Expanded(
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object e, StackTrace _) =>
                        Center(child: Text('加载失败：$e')),
                    data: (SearchState state) => _buildResults(state, plan),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(SearchState state, SearchPlan plan) {
    // 未输入：给引导而不是「列出全部流水」
    if (plan.isEmpty) {
      return _Intro(onPick: _setKeyword);
    }

    final List<TxRow> hits = filterTx(
      items: state.items,
      categoryNameOf: state.nameOf,
      query: _input.text,
    );
    if (hits.isEmpty) {
      return _NoResult(keyword: _input.text.trim(), onClear: _clear);
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
        ),
        Expanded(
          child: TxGroupList(
            items: shown,
            categoryNameOf: state.nameOf,
            onEdit: _edit,
            onDelete: _confirmDelete,
          ),
        ),
      ],
    );
  }
}

/// 顶部**不透明**提示块：关闭 + 输入框 + 一键清空 + 类型筛选 chips。
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.plan,
    required this.onClose,
    required this.onClear,
    required this.onToggleType,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchPlan plan;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final ValueChanged<String> onToggleType;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasInput = controller.text.trim().isNotEmpty;
    final String? active = plan.typeWord;

    return Material(
      // 不透明：盖住玻璃的上半部分
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: const ValueKey<String>('search-close'),
                  tooltip: '关闭',
                  icon: const Icon(Icons.arrow_back_rounded),
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
                    decoration: InputDecoration(
                      hintText: '搜索分类、备注或金额',
                      border: InputBorder.none,
                      counterText: '',
                      suffixIcon: hasInput
                          ? IconButton(
                              key: const ValueKey<String>('search-clear'),
                              tooltip: '清空',
                              icon: const Icon(Icons.cancel_rounded, size: 20),
                              onPressed: onClear,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: <Widget>[
                  for (final String word in kTypeDirectives.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey<String>('search-chip-$word'),
                        label: Text(word),
                        selected: active == word,
                        // 关掉对勾：它会让选中 chip 变宽、把后面几个挤位移（真机看出来的跳动）。
                        // 选中态靠底色/边框区分，足够了。
                        showCheckmark: false,
                        onSelected: (_) => onToggleType(word),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
  });

  final int shown;
  final int total;
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: _GlassPanel(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '共 $total 笔',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _AmountCell(
                  label: '支出',
                  value: summary.expenseYuan,
                  color: const Color(0xFFFF6B6B),
                ),
                const SizedBox(width: 12),
                _AmountCell(
                  label: '收入',
                  value: summary.incomeYuan,
                  color: const Color(0xFF4CAF50),
                ),
              ],
            ),
            if (total > shown)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '仅显示最近 $shown 笔，补充关键词可缩小范围',
                  style: TextStyle(fontSize: 11, color: muted),
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
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 未输入时的引导：说清能搜哪三类字段（示例点一下填进输入框）。
class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // ⚠️ 这里**不能**用 SingleChildScrollView：Scrollable 会以 opaque 命中整块下方区域，
    // 点提示块以外的玻璃空白就关不掉浮层了（真机走查抓到的）。Align 只占内容高度，空白可穿透。
    // 内容约 220dp，正常手机（逻辑高 ≥ 480）放得下，不需要滚动兜底。
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: _GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.search_rounded, size: 34, color: muted),
              const SizedBox(height: 10),
              const Text(
                '输入分类、备注或金额开始搜索',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '分类：餐饮 / 交通　备注：午餐　金额：88.88',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: <Widget>[
                  for (final String example in _examples)
                    ActionChip(
                      label: Text(example),
                      onPressed: () => onPick(example),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态示例关键词：点一下就填进输入框，省得用户猜「能搜什么」。
const List<String> _examples = <String>['餐饮', '午餐', '88.88'];

/// 有输入但没有命中。
///
/// 提示块**顶部对齐**且高度固定为屏高 × 1/5 —— 不再 `Center` 撑满整屏
/// （那样四周会留下大片空白，整页显得比实际更"空"）。
class _NoResult extends StatelessWidget {
  const _NoResult({required this.keyword, required this.onClear});

  final String keyword;
  final VoidCallback onClear;

  /// 提示块高度占整屏的比例。
  static const double _heightFraction = 1 / 5;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // 用整屏高度而非 body 高度：输入框 autofocus，键盘弹起会压扁 body，
    // 按 body 算的话提示块会跟着一起缩。
    final double blockHeight =
        MediaQuery.sizeOf(context).height * _heightFraction;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: blockHeight,
        child: Center(
          // 兜底：极小屏放不下时可滚，不会 RenderFlex 溢出
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _GlassPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.search_off_rounded, size: 32, color: muted),
                  const SizedBox(height: 6),
                  Text(
                    '没有匹配「$keyword」的账单',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    '换个分类名、备注里的字，或金额里的数字试试',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮在毛玻璃之上的半透明面板：玻璃下面就是首页内容，文字得有个底才稳。
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}
