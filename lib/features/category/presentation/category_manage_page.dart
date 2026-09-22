/// 分类管理：支出/收入分组 + 新建自定义分类 + 删除自定义分类。
///
/// 对应旧栈 `pages/category/manage.vue`。预置分类 is_preset=1 不可删（可改名）。
/// F7.6 P3 卡通化，对齐原型 `scrCategories`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import '../../shared/name_dialog.dart';

/// 分类管理页。
class CategoryManagePage extends ConsumerStatefulWidget {
  const CategoryManagePage({super.key});

  @override
  ConsumerState<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends ConsumerState<CategoryManagePage> {
  String _kind = 'expense';

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final bookAsync = ref.watch(currentBookProvider);

    return Scaffold(
      backgroundColor: Tok.paper,
      appBar: AppBar(
        title: Text('分类管理 · ${bookAsync.value?.name ?? ''}'),
        actions: <Widget>[
          ToonIconButton(
            icon: Icons.add,
            tooltip: '新建分类',
            onPressed: () => _create(context, ref),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Center(
              child: ToonSeg(
                labels: const <String>['支出', '收入'],
                index: _kind == 'expense' ? 0 : 1,
                onChanged: (int i) =>
                    setState(() => _kind = i == 0 ? 'expense' : 'income'),
              ),
            ),
          ),
          Expanded(
            child: categoriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace _) =>
                  Center(child: Text('加载失败：$e')),
              data: (List<Category> all) {
                final cats = all
                    .where((Category c) => c.kind == _kind)
                    .toList();
                if (cats.isEmpty) {
                  return const Center(child: Text('还没有分类'));
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ToonCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        clip: true,
                        child: Column(
                          children: <Widget>[
                            for (int i = 0; i < cats.length; i++)
                              _CatRow(
                                category: cats[i],
                                kind: _kind,
                                dashedTop: i > 0,
                                onDelete: () => _delete(context, ref, cats[i]),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Text(
                        '预置分类不可删除，可改名改图标；自定义分类可增 / 改 / 软删。',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tok.ink2,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showNameDialog(context, title: '新建分类');
    if (name == null || name.trim().isEmpty) return;
    final bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null) return;
    await ref
        .read(categoryRepositoryProvider)
        .create(bookId: bookId, name: name.trim(), kind: _kind);
    ref.invalidate(categoriesProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确定删除「${category.name}」？已记录的流水不受影响。'),
        actions: <Widget>[
          ToonButton(
            label: '取消',
            kind: ToonButtonKind.ghost,
            small: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ToonButton(
            label: '删除',
            kind: ToonButtonKind.danger,
            small: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      try {
        await ref.read(categoryRepositoryProvider).softDelete(category.id);
        ref.invalidate(categoriesProvider);
      } on StateError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }
}

/// 分类行：字母头像（支出红 / 收入绿）+ 名称 + 预置标记或删除按钮。
class _CatRow extends StatelessWidget {
  const _CatRow({
    required this.category,
    required this.kind,
    required this.dashedTop,
    required this.onDelete,
  });

  final Category category;
  final String kind;
  final bool dashedTop;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool income = kind == 'income';
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          ToonAvatar(
            text: category.name.isEmpty ? '?' : category.name.substring(0, 1),
            bg: income ? Tok.greenTint : Tok.redTint,
            fg: income ? Tok.green : Tok.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (category.isPreset == 1)
            const Text(
              '预置 · 不可删',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Tok.ink3,
              ),
            )
          else
            ToonIconButton(
              icon: Icons.delete_outline,
              tooltip: '删除',
              muted: true,
              size: 34,
              iconSize: 18,
              onPressed: onDelete,
            ),
        ],
      ),
    );

    if (!dashedTop) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[const ToonDashedLine(), row],
    );
  }
}
