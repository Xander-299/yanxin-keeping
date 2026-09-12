/// 搜索页：按**分类名 / 备注 / 金额**检索当前账本的全部流水。
///
/// 入口：首页 header 的搜索图标 → `/search`（见 `docs/SPEC-F7.4-search.md`）。
/// 输入框带一键清空；结果按天分组复用 [TxGroupList]，行为与首页一致（点=编辑、长按=删除）。
library;

import 'dart:async';

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

/// 空态示例关键词：点一下就填进输入框，省得用户猜「能搜什么」。
const List<String> _examples = <String>['餐饮', '午餐', '88.88'];

/// 搜索页。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 输入变化只影响本页（关键词不进 provider），直接 setState 刷新结果
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

  /// 填入关键词并保持焦点（示例、一键清空共用）。
  void _setKeyword(String value) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _focus.requestFocus();
  }

  /// 一键清空：清掉输入并重新聚焦，可以马上接着敲下一个关键词。
  void _clear() => _setKeyword('');

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
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SearchState> async = ref.watch(searchProvider);
    final bool hasInput = _input.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // 标题位就是输入框；有输入才出现右侧一键清空
        title: TextField(
          key: const ValueKey<String>('search-input'),
          controller: _input,
          focusNode: _focus,
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
                    onPressed: _clear,
                  )
                : null,
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
        data: _buildResults,
      ),
    );
  }

  Widget _buildResults(SearchState state) {
    // 未输入：给引导而不是「列出全部流水」
    if (normalizeQuery(_input.text).isEmpty) {
      return _Intro(onPick: _setKeyword);
    }

    final hits = filterTx(
      items: state.items,
      categoryNameOf: state.nameOf,
      query: _input.text,
    );
    if (hits.isEmpty) {
      return _NoResult(keyword: _input.text.trim(), onClear: _clear);
    }

    final shown = hits.length > kSearchResultLimit
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
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

/// 未输入时的引导：说清能搜哪三类字段。
class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: <Widget>[
        Icon(Icons.search_rounded, size: 40, color: muted),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: <Widget>[
            for (final example in _examples)
              ActionChip(
                label: Text(example),
                onPressed: () => onPick(example),
              ),
          ],
        ),
      ],
    );
  }
}

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
    // 用整屏高度而非 body 高度：本页输入框 autofocus，键盘弹起会压扁 body，
    // 按 body 算的话提示块会跟着一起缩。
    final double blockHeight =
        MediaQuery.sizeOf(context).height * _heightFraction;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: blockHeight,
        child: Center(
          // 兜底：极小屏（逻辑高 < 约 550）放不下时可滚，不会 RenderFlex 溢出
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
    );
  }
}
