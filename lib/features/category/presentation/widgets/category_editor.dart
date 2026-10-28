/// 新增 / 编辑分类弹层（名称、类型、父分类、图标、颜色）。
///
/// 校验在仓储层（`CategoryException`，中文文案），这里只负责展示与回显；
/// 所有写操作走 [CategoryActions]，UI 不直接碰数据库。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/constants/category_icons.dart';
import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/data/providers/category_providers.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

import '../../application/category_actions.dart';

/// 打开分类编辑弹层；保存成功返回 true。
Future<bool?> showCategoryEditor(
  BuildContext context, {
  required String bookId,
  required String kind,
  Category? editing,
  String? initialParentId,
}) {
  final ToonPalette p = context.toon;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
    ),
    builder: (BuildContext _) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _CategoryEditor(
        bookId: bookId,
        kind: kind,
        editing: editing,
        initialParentId: initialParentId,
      ),
    ),
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({
    required this.bookId,
    required this.kind,
    this.editing,
    this.initialParentId,
  });

  final String bookId;
  final String kind;
  final Category? editing;
  final String? initialParentId;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late String _kind = widget.editing?.kind ?? widget.kind;
  late String _icon = widget.editing?.icon ?? '';
  late String _color = widget.editing?.color ?? '';
  late String? _parentId = widget.editing?.parentId ?? widget.initialParentId;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.editing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Category> _parents(List<Category> all) => all
      .where(
        (Category c) =>
            c.kind == _kind &&
            c.parentId == null &&
            c.id != widget.editing?.id &&
            c.isArchived == 0,
      )
      .toList();

  Future<void> _save(List<Category> all) async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '分类名称不能为空');
      return;
    }
    if (_isEditing && _parentId != widget.editing!.parentId) {
      final bool hasKids = all.any((Category c) => c.parentId == widget.editing!.id);
      if (hasKids) {
        setState(() => _error = '这个分类下还有子分类，不能改成二级分类');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final CategoryActions actions = ref.read(categoryActionsProvider);
    try {
      if (_isEditing) {
        await actions.update(
          widget.editing!.id,
          name: name,
          icon: _icon,
          color: _color,
          parentId: _parentId,
          changeParent: _parentId != widget.editing!.parentId,
        );
      } else {
        await actions.create(
          bookId: widget.bookId,
          name: name,
          kind: _kind,
          parentId: _parentId,
          icon: _icon,
          color: _color,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on CategoryException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final List<Category> all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final List<Category> parents = _parents(all);
    final Category? parent = _parentId == null
        ? null
        : all.where((Category c) => c.id == _parentId).firstOrNull;
    final Color chipBg = categoryColor(p, _color, kind: _kind);
    final Color chipFg = categoryOnColor(p, _color, kind: _kind);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
            Text(
              _isEditing ? '编辑分类' : '新建分类',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),

            // 预览 + 名称
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(Tok.rMd),
                  ),
                  child: Icon(
                    categoryIconData(_icon, kind: _kind),
                    size: 24,
                    color: chipFg,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: !_isEditing,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(all),
                    maxLength: 12,
                    decoration: const InputDecoration(
                      labelText: '分类名称',
                      counterText: '',
                      hintText: '例如：早餐、打车、房租',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 类型（编辑时不可改：历史账单都挂在原方向上）
            if (!_isEditing) ...<Widget>[
              Text('收支类型', style: _labelStyle(p)),
              const SizedBox(height: 8),
              ToonSeg(
                labels: const <String>['支出', '收入'],
                index: _kind == 'income' ? 1 : 0,
                onChanged: (int i) => setState(() {
                  _kind = i == 1 ? 'income' : 'expense';
                  _parentId = null; // 换方向后父分类不再适用
                }),
              ),
              const SizedBox(height: 14),
            ],

            // 父分类
            Text('父分类（可选）', style: _labelStyle(p)),
            const SizedBox(height: 8),
            // 用 Material 而不是 Container 包 ListTile：否则水波纹画在下面的层，
            // Flutter 会断言「ListTile background color or ink splashes may be invisible」。
            Material(
              color: p.canvas2,
              borderRadius: BorderRadius.circular(Tok.rMd),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Text(parent == null ? '无（一级分类）' : parent.name),
                subtitle: const Text('二级分类会计入父分类的统计'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _saving ? null : () => _pickParent(parents),
              ),
            ),
            const SizedBox(height: 14),

            // 图标
            Text('图标', style: _labelStyle(p)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String key in kCategoryIconKeys)
                  _IconCell(
                    icon: categoryIconData(key, kind: _kind),
                    selected: key == _icon,
                    onTap: () => setState(() => _icon = key),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // 颜色
            Text('颜色', style: _labelStyle(p)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final String hex in kCategoryColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: parseHexColor(hex, p.brand),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hex == _color ? p.ink : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: p.redInk,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: ToonButton(
                    label: '取消',
                    kind: ToonButtonKind.ghost,
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ToonButton(
                    label: _saving ? '保存中…' : '保存',
                    onPressed: _saving ? null : () => _save(all),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle(ToonPalette p) => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: p.ink2,
  );

  Future<void> _pickParent(List<Category> parents) async {
    final ToonPalette p = context.toon;
    // '' = 明确选了「无（一级分类）」；null = 用户直接关掉弹层（不改）
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.paper,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              title: const Text('无（一级分类）'),
              onTap: () => Navigator.of(sheetContext).pop(''),
            ),
            for (final Category c in parents)
              ListTile(
                leading: Icon(categoryIconData(c.icon, kind: c.kind)),
                title: Text(c.name),
                onTap: () => Navigator.of(sheetContext).pop(c.id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _parentId = picked.isEmpty ? null : picked);
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? p.brandTint : p.canvas2,
          borderRadius: BorderRadius.circular(Tok.rSm),
          border: Border.all(
            color: selected ? p.brandDeep : Colors.transparent,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          size: 21,
          color: selected ? p.brandInk : p.ink2,
        ),
      ),
    );
  }
}
