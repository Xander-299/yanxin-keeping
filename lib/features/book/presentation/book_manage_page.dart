/// 账本管理：列表 + 新建 + 切换。
///
/// 对应旧栈 `pages/book/manage.vue`。切换写 `active_book_id`（落库，杀进程不丢）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/database.dart';
import '../../shared/name_dialog.dart';

/// 账本管理页。返回 true 表示切换过账本（首页需要刷新）。
class BookManagePage extends ConsumerWidget {
  const BookManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(bookListProvider);
    final activeId = ref.watch(activeBookIdProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('账本管理')),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
        data: (List<Book> books) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: books.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final book = books[index];
            final isActive = book.id == activeId;
            return ListTile(
              leading: const CircleAvatar(child: Text('📒')),
              title: Text(book.name),
              subtitle: Text('${book.currency} · ${book.type}'),
              trailing: isActive
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () async {
                await ref
                    .read(activeBookIdProvider.notifier)
                    .select(book.id);
                if (context.mounted) Navigator.of(context).pop(true);
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建账本',
        onPressed: () => _createBook(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createBook(BuildContext context, WidgetRef ref) async {
    final name = await showNameDialog(context, title: '新建账本');
    if (name == null || name.trim().isEmpty) return;
    final book = await ref
        .read(bookRepositoryProvider)
        .create(name: name.trim());
    await ref.read(activeBookIdProvider.notifier).select(book.id);
    ref.invalidate(bookListProvider);
    if (context.mounted) Navigator.of(context).pop(true);
  }
}
