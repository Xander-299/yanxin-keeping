/// 分类管理（schema v4）：支出/收入 Tab、两级树、图标/颜色、排序、归档、迁移删除。
///
/// 交互取舍：
/// - **排序用「上移 / 下移」**而不是拖拽 —— 两级树里嵌套拖拽的落点很容易跨层级
///   （任务书也明确允许用上移/下移兜底），误操作代价比"炫"更重要；
/// - 删除**永远先看引用**：没账单才真删；有账单给「归档」或「迁移到别的分类」两条路，
///   绝不让历史账单丢分类；
/// - 归档分区默认折叠，恢复/彻底删除都在这里。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/constants/category_icons.dart';
import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/data/providers/book_providers.dart';
import 'package:yanxin/data/providers/category_providers.dart';
import 'package:yanxin/data/repositories/category_repository.dart';

import '../application/category_actions.dart';
import 'widgets/category_editor.dart';

/// 分类管理页。
class CategoryManagePage extends ConsumerStatefulWidget {
  const CategoryManagePage({super.key});

  @override
  ConsumerState<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends ConsumerState<CategoryManagePage> {
  String _kind = 'expense';
  bool _showArchived = false;

  CategoryActions get _actions => ref.read(categoryActionsProvider);

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final AsyncValue<List<Category>> async = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '新建分类',
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
        data: (List<Category> all) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Center(
                child: ToonSeg(
                  labels: const <String>['支出', '收入'],
                  index: _kind == 'expense' ? 0 : 1,
                  onChanged: (int i) => setState(
                    () => _kind = i == 0 ? 'expense' : 'income',
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(all)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<Category> all) {
    final ToonPalette p = context.toon;
    final List<Category> mine = all
        .where((Category c) => c.kind == _kind)
        .toList();
    final List<Category> active = mine
        .where((Category c) => c.isArchived == 0)
        .toList();
    final List<Category> roots = active
        .where((Category c) => c.parentId == null)
        .toList()
      ..sort(_bySort);
    final List<Category> archived = mine
        .where((Category c) => c.isArchived == 1)
        .toList()
      ..sort(_bySort);

    if (roots.isEmpty && archived.isEmpty) {
      return _EmptyState(onCreate: _create);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: <Widget>[
        for (final Category root in roots) ...<Widget>[
          _CategoryGroup(
            root: root,
            children: active.where((Category c) => c.parentId == root.id).toList()
              ..sort(_bySort),
            onEdit: _edit,
            onAddChild: (Category c) => _create(parentId: c.id),
            onMove: (Category c, int delta) => _move(c, roots, active, delta),
            onArchive: _archive,
            onDelete: (Category c) => _remove(c, all),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        ToonButton(
          block: true,
          kind: ToonButtonKind.ghost,
          icon: Icons.add_rounded,
          label: '新建${_kind == 'expense' ? '支出' : '收入'}分类',
          onPressed: _create,
        ),
        if (archived.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Divider(color: p.line),
          InkWell(
            onTap: () => setState(() => _showArchived = !_showArchived),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: <Widget>[
                  Text(
                    '已归档（${archived.length}）',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.ink2,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showArchived
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: p.ink3,
                  ),
                ],
              ),
            ),
          ),
          if (_showArchived)
            for (final Category c in archived)
              _ArchivedRow(
                category: c,
                onRestore: () => _restore(c),
                onDelete: () => _remove(c, all),
              ),
          if (_showArchived)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '归档的分类不会出现在新建账单里，历史账单照常显示。',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.ink3,
                ),
              ),
            ),
        ],
      ],
    );
  }

  int _bySort(Category a, Category b) {
    final int byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
  }

  // ────────────────────────────── 操作 ──────────────────────────────

  Future<void> _create({String? parentId}) async {
    final String? bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null || !mounted) return;
    await showCategoryEditor(
      context,
      bookId: bookId,
      kind: _kind,
      initialParentId: parentId,
    );
  }

  Future<void> _edit(Category category) async {
    final String? bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null || !mounted) return;
    await showCategoryEditor(
      context,
      bookId: bookId,
      kind: _kind,
      editing: category,
    );
  }

  /// 同级上移 / 下移（[delta] = -1 / +1）。
  Future<void> _move(
    Category category,
    List<Category> roots,
    List<Category> active,
    int delta,
  ) async {
    final List<Category> siblings = category.parentId == null
        ? roots
        : (active.where((Category c) => c.parentId == category.parentId).toList()
            ..sort(_bySort));
    final int index = siblings.indexWhere((Category c) => c.id == category.id);
    final int target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;
    final List<Category> next = <Category>[...siblings];
    final Category moved = next.removeAt(index);
    next.insert(target, moved);
    await _actions.reorder(next.map((Category c) => c.id).toList());
  }

  Future<void> _archive(Category category) async {
    final int used = await _actions.countTransactions(category.id);
    if (!mounted) return;
    final bool ok = await _confirm(
      title: '归档「${category.name}」？',
      message: used > 0
          ? '它下面有 $used 笔账单，归档后不会再出现在新建账单里，历史账单照常显示。'
          : '归档后不会再出现在新建账单里，可以随时恢复。',
      confirmLabel: '归档',
    );
    if (!ok) return;
    await _actions.archive(category.id);
    if (mounted) _toast('已归档「${category.name}」');
  }

  Future<void> _restore(Category category) async {
    await _actions.unarchive(category.id);
    if (mounted) _toast('已恢复「${category.name}」');
  }

  /// 删除：先看引用与子分类，决定「直接删 / 归档 / 迁移后删」。
  Future<void> _remove(Category category, List<Category> all) async {
    final int used = await _actions.countTransactions(category.id);
    final int kids = all
        .where((Category c) => c.parentId == category.id && c.deletedAt == null)
        .length;
    if (!mounted) return;

    if (used == 0 && kids == 0) {
      final bool ok = await _confirm(
        title: '删除「${category.name}」？',
        message: '它下面没有账单，删除后不可恢复。',
        confirmLabel: '删除',
        danger: true,
      );
      if (!ok) return;
      try {
        await _actions.deleteIfUnused(category.id);
        if (mounted) _toast('已删除「${category.name}」');
      } on CategoryException catch (e) {
        if (mounted) _toast(e.message);
      }
      return;
    }

    // 有引用 / 有子分类：给「归档」或「迁移后删」两条路
    final _RemoveChoice? choice = await showDialog<_RemoveChoice>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('「${category.name}」还在使用'),
        content: Text(
          <String>[
            if (used > 0) '有 $used 笔账单挂在它（含子分类）下面',
            if (kids > 0) '还有 $kids 个子分类',
            '直接删除会让这些账单失去分类，请选择处理方式。',
          ].join('；'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_RemoveChoice.migrate),
            child: const Text('迁移账单后删除'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_RemoveChoice.archive),
            child: const Text('归档（保留历史）'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _RemoveChoice.archive) {
      await _actions.archive(category.id);
      if (mounted) _toast('已归档「${category.name}」');
      return;
    }
    await _migrateAndDelete(category, all);
  }

  Future<void> _migrateAndDelete(Category category, List<Category> all) async {
    final List<String> blocked = <String>[
      category.id,
      for (final Category c in all)
        if (c.parentId == category.id) c.id,
    ];
    final List<Category> targets = all
        .where(
          (Category c) =>
              c.kind == category.kind &&
              c.isArchived == 0 &&
              c.deletedAt == null &&
              !blocked.contains(c.id),
        )
        .toList()
      ..sort(_bySort);
    if (targets.isEmpty) {
      _toast('没有可迁移的目标分类，请先新建一个');
      return;
    }
    final Category? target = await showModalBottomSheet<Category>(
      context: context,
      backgroundColor: context.toon.paper,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '把账单迁到哪个分类？',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final Category c in targets)
              ListTile(
                leading: Icon(categoryIconData(c.icon, kind: c.kind)),
                title: Text(c.name),
                onTap: () => Navigator.of(sheetContext).pop(c),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    try {
      final int moved = await _actions.migrateAndDelete(category.id, target.id);
      if (mounted) _toast('已把 $moved 笔账单迁到「${target.name}」并删除原分类');
    } on CategoryException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: context.toon.redTint,
                    foregroundColor: context.toon.redInk,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _RemoveChoice { archive, migrate }

// ────────────────────────────── 列表行 ──────────────────────────────

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.root,
    required this.children,
    required this.onEdit,
    required this.onAddChild,
    required this.onMove,
    required this.onArchive,
    required this.onDelete,
  });

  final Category root;
  final List<Category> children;
  final void Function(Category) onEdit;
  final void Function(Category) onAddChild;
  final void Function(Category, int) onMove;
  final void Function(Category) onArchive;
  final void Function(Category) onDelete;

  @override
  Widget build(BuildContext context) {
    return ToonCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        children: <Widget>[
          _CategoryTile(
            category: root,
            subtitle: children.isEmpty ? null : '${children.length} 个二级分类',
            onEdit: () => onEdit(root),
            onAddChild: () => onAddChild(root),
            onMoveUp: () => onMove(root, -1),
            onMoveDown: () => onMove(root, 1),
            onArchive: () => onArchive(root),
            onDelete: () => onDelete(root),
          ),
          for (final Category child in children)
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: _CategoryTile(
                category: child,
                dense: true,
                onEdit: () => onEdit(child),
                onMoveUp: () => onMove(child, -1),
                onMoveDown: () => onMove(child, 1),
                onArchive: () => onArchive(child),
                onDelete: () => onDelete(child),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onArchive,
    required this.onDelete,
    this.onAddChild,
    this.subtitle,
    this.dense = false,
  });

  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onAddChild;
  final String? subtitle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Color bg = categoryColor(p, category.color, kind: category.kind);
    final Color fg = categoryOnColor(p, category.color, kind: category.kind);
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(Tok.rSm),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: dense ? 8 : 10,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: dense ? 30 : 38,
              height: dense ? 30 : 38,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(dense ? Tok.rSm : Tok.rMd),
              ),
              child: Icon(
                categoryIconData(category.icon, kind: category.kind),
                size: dense ? 17 : 20,
                color: fg,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: dense ? 14 : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (category.isPreset == 1) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: p.canvas2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '预置',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: p.ink3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: p.ink3,
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: Icon(Icons.more_horiz_rounded, size: 20, color: p.ink3),
              onSelected: (String value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                  case 'child':
                    onAddChild?.call();
                  case 'up':
                    onMoveUp();
                  case 'down':
                    onMoveDown();
                  case 'archive':
                    onArchive();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                if (onAddChild != null)
                  const PopupMenuItem<String>(
                    value: 'child',
                    child: Text('添加子分类'),
                  ),
                const PopupMenuItem<String>(value: 'up', child: Text('上移')),
                const PopupMenuItem<String>(value: 'down', child: Text('下移')),
                const PopupMenuItem<String>(value: 'archive', child: Text('归档')),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(
                    '删除',
                    style: TextStyle(color: p.redInk),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({
    required this.category,
    required this.onRestore,
    required this.onDelete,
  });

  final Category category;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: p.ink3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.ink2,
              ),
            ),
          ),
          TextButton(
            onPressed: onRestore,
            child: const Text('恢复'),
          ),
          TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(foregroundColor: p.redInk),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.category_outlined, size: 48, color: p.ink3),
            const SizedBox(height: 12),
            Text(
              '还没有分类',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '先建一个常用的支出分类，记账时就能直接选。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.ink2),
            ),
            const SizedBox(height: 16),
            ToonButton(
              icon: Icons.add_rounded,
              label: '新建分类',
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}
