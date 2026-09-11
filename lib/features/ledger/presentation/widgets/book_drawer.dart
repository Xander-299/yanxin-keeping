/// 首页左侧抽屉：账本列表（当前高亮，点击切换）+ 右下角「管理账本」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';

/// 账本抽屉。
class BookDrawer extends ConsumerWidget {
  const BookDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(bookListProvider);
    final activeId = ref.watch(activeBookIdProvider).value;

    return Drawer(
      backgroundColor: const Color(0xFF161618),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '我的账本',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: booksAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
                data: (List<Book> books) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: <Widget>[
                    for (final Book b in books)
                      ListTile(
                        leading: const Icon(Icons.menu_book_rounded),
                        title: Text(b.name),
                        selected: b.id == activeId,
                        selectedTileColor: Colors.white10,
                        trailing: b.id == activeId
                            ? const Icon(
                                Icons.check_rounded,
                                color: Color(0xFFFFAF38),
                              )
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () async {
                          Navigator.pop(context); // 先收抽屉
                          await ref
                              .read(activeBookIdProvider.notifier)
                              .select(b.id);
                          // ledgerProvider / categoriesProvider watch 了
                          // activeBookIdProvider，切换后自动重建
                        },
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: <Widget>[
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push<bool?>('/books').then((bool? changed) {
                        if (changed ?? false) ref.invalidate(bookListProvider);
                      });
                    },
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('管理账本'),
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
