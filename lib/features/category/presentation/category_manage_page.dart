/// 分类管理：支出/收入分组 + 新建自定义分类 + 删除自定义分类。
///
/// 对应旧栈 `pages/category/manage.vue`。预置分类 is_preset=1 不可删（可改名）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/category_providers.dart';
import 'package:yanxin/core/providers/database.dart';
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
      appBar: AppBar(title: Text('分类管理 · ${bookAsync.value?.name ?? ''}')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'expense', label: Text('支出')),
                ButtonSegment<String>(value: 'income', label: Text('收入')),
              ],
              selected: <String>{_kind},
              onSelectionChanged: (Set<String> next) =>
                  setState(() => _kind = next.first),
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
                return ListView.separated(
                  itemCount: cats.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final c = cats[index];
                    final isPreset = c.isPreset == 1;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Text(
                          c.name.isEmpty ? '?' : c.name.substring(0, 1),
                        ),
                      ),
                      title: Text(c.name),
                      trailing: isPreset
                          ? null
                          : IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _delete(context, ref, c),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建分类',
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
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
