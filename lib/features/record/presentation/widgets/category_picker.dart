/// 分类选择底部弹层（4 列宫格 + 弹层内切换支出/收入）。
///
/// 视觉对齐页面原型 `sheet-category`：
/// 抓手 + 「选择分类 | 支出/收入 seg」标题行 + 4 列宫格（圆角头像 + 墨色描边 +
/// 硬阴影）+ 底部说明；选中的头像换成品牌琥珀底（原型 `.catgrid button.on .c-ava`）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

/// 打开分类选择器，返回选中的分类（取消返回 null）。
///
/// [categories] 传**全量**分类（含支出与收入），类型切换由弹层自己管；
/// 调用方按返回值的 `kind` 同步自己的类型状态。
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  String kind = 'expense',
  String? selectedId,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    showDragHandle: false,
    backgroundColor: Tok.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
      side: BorderSide(color: Tok.ink, width: Tok.bw),
    ),
    builder: (BuildContext context) => _CategoryGrid(
      categories: categories,
      kind: kind,
      selectedId: selectedId,
    ),
  );
}

class _CategoryGrid extends StatefulWidget {
  const _CategoryGrid({
    required this.categories,
    required this.kind,
    this.selectedId,
  });

  final List<Category> categories;
  final String kind;
  final String? selectedId;

  @override
  State<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<_CategoryGrid> {
  late String _kind = widget.kind;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = _kind == 'income';
    final Color avaBg = isIncome ? Tok.greenTint : Tok.redTint;
    final Color avaFg = isIncome ? Tok.green : Tok.red;
    final List<Category> list = widget.categories
        .where((Category c) => c.kind == _kind)
        .toList(growable: false);
    // 4 列宫格：外层左右各 20 + 列间距 8。
    final double cellW = (MediaQuery.sizeOf(context).width - 40 - 24) / 4;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 抓手
            Center(
              child: Container(
                width: 46,
                height: 6,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Tok.ink,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                const Text(
                  '选择分类',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                ToonSeg(
                  labels: const <String>['支出', '收入'],
                  index: isIncome ? 1 : 0,
                  small: true,
                  onChanged: (int i) => setState(
                    () => _kind = i == 1 ? 'income' : 'expense',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 14,
                  children: <Widget>[
                    for (final Category c in list)
                      SizedBox(
                        width: cellW,
                        child: _CategoryCell(
                          name: c.name,
                          bg: avaBg,
                          fg: avaFg,
                          selected: c.id == widget.selectedId,
                          onTap: () => Navigator.of(context).pop(c),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '预置分类不可删；到「我的 → 分类管理」可新增自定义分类。',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.name,
    required this.bg,
    required this.fg,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color bg;
  final Color fg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 选中：整块换品牌琥珀 + 深棕字（原型 `button.on .c-ava`）
                color: selected ? Tok.brand : bg,
                borderRadius: BorderRadius.circular(17),
                border: Tok.inkBorder(),
                boxShadow: Tok.hard(d: 2.5),
              ),
              child: Text(
                name.isEmpty ? '?' : name.substring(0, 1),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: selected ? Tok.brandInk : fg,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
