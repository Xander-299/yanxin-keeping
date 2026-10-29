/// 分类选择底部弹层（两级：一级宫格 → 有子分类时进子级列表）。
///
/// 规则（任务书 §5）：
/// - **只列同方向、未归档**的分类：新建支出账单看不到收入分类，也看不到已归档分类；
/// - 一级分类**可以被直接选中**（二级是可选功能，不强制）；
/// - 有子分类的一级分类点进去后，第一项是「父分类本身（不细分）」；
/// - 归档分类不会出现在这里，但历史账单仍能显示它的名字/图标（名称解析在仓储层）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/constants/category_icons.dart';
import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

/// 打开分类选择器，返回选中的分类（取消返回 null）。
///
/// [categories] 传**全量**分类（含收入、含归档），过滤在本组件里做。
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  String kind = 'expense',
  String? selectedId,
}) {
  final ToonPalette p = context.toon;
  return showModalBottomSheet<Category>(
    context: context,
    backgroundColor: p.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
    ),
    builder: (BuildContext _) => _CategoryPicker(
      categories: categories,
      kind: kind,
      selectedId: selectedId,
    ),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.kind,
    this.selectedId,
  });

  final List<Category> categories;
  final String kind;
  final String? selectedId;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  late String _kind = widget.kind;

  /// 当前正在看哪个一级分类的子分类；null = 一级宫格。
  String? _parentId;

  List<Category> get _mine => widget.categories
      .where((Category c) => c.kind == _kind && c.isArchived == 0)
      .toList();

  List<Category> get _roots {
    final List<Category> list = _mine
        .where((Category c) => c.parentId == null)
        .toList()
      ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  List<Category> _childrenOf(String parentId) => _mine
      .where((Category c) => c.parentId == parentId)
      .toList()
    ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));

  Category? get _parent =>
      _parentId == null ? null : widget.categories.firstWhere((Category c) => c.id == _parentId);

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Category? parent = _parent;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 46,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: p.ink3,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                if (parent != null) ...<Widget>[
                  IconButton(
                    tooltip: '返回一级分类',
                    onPressed: () => setState(() => _parentId = null),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      parent.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...<Widget>[
                  const Text(
                    '选择分类',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  ToonSeg(
                    labels: const <String>['支出', '收入'],
                    index: _kind == 'income' ? 1 : 0,
                    small: true,
                    onChanged: (int i) => setState(() {
                      _kind = i == 1 ? 'income' : 'expense';
                      _parentId = null;
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: parent == null ? _rootsGrid() : _childrenList(parent),
            ),
            const SizedBox(height: 8),
            Text(
              parent == null ? '带「›」的分类可以再选细分项；也可以直接用它记账。' : '选「${parent.name}」本身也可以，不强制细分。',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rootsGrid() {
    final List<Category> roots = _roots;
    final double cellW = (MediaQuery.sizeOf(context).width - 40 - 24) / 4;
    if (roots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '还没有${_kind == 'expense' ? '支出' : '收入'}分类，去「我的 → 分类管理」建一个吧',
          style: TextStyle(fontSize: 13, color: context.toon.ink2),
        ),
      );
    }
    return SingleChildScrollView(
      child: Wrap(
        spacing: 8,
        runSpacing: 12,
        children: <Widget>[
          for (final Category c in roots)
            SizedBox(
              width: cellW,
              child: _CategoryCell(
                category: c,
                selected: c.id == widget.selectedId,
                hasChildren: _childrenOf(c.id).isNotEmpty,
                onTap: () {
                  if (_childrenOf(c.id).isEmpty) {
                    Navigator.of(context).pop(c);
                  } else {
                    setState(() => _parentId = c.id);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _childrenList(Category parent) {
    final List<Category> kids = _childrenOf(parent.id);
    final ToonPalette p = context.toon;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _Avatar(category: parent),
            title: Text('${parent.name}（不细分）'),
            trailing: parent.id == widget.selectedId
                ? Icon(Icons.check_rounded, size: 18, color: p.brandDeep)
                : null,
            onTap: () => Navigator.of(context).pop(parent),
          ),
          Divider(color: p.line, height: 1),
          for (final Category c in kids)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _Avatar(category: c, small: true),
              title: Text(c.name),
              trailing: c.id == widget.selectedId
                  ? Icon(Icons.check_rounded, size: 18, color: p.brandDeep)
                  : null,
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.category, this.small = false});

  final Category category;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Color bg = categoryColor(p, category.color, kind: category.kind);
    final Color fg = categoryOnColor(p, category.color, kind: category.kind);
    final double s = small ? 32 : 38;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(small ? Tok.rSm : Tok.rMd),
      ),
      child: Icon(
        categoryIconData(category.icon, kind: category.kind),
        size: small ? 17 : 20,
        color: fg,
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.hasChildren,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final bool hasChildren;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Color bg = categoryColor(p, category.color, kind: category.kind);
    final Color fg = categoryOnColor(p, category.color, kind: category.kind);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tok.rMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? p.brandTint : bg,
                    borderRadius: BorderRadius.circular(Tok.rMd),
                    border: selected
                        ? Border.all(color: p.brandDeep, width: 2)
                        : null,
                  ),
                  child: Icon(
                    categoryIconData(category.icon, kind: category.kind),
                    size: 22,
                    color: selected ? p.brandInk : fg,
                  ),
                ),
                if (hasChildren)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: p.paper,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.line),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 12,
                        color: p.ink2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
