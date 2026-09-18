/// 首页左侧抽屉：账本列表（当前高亮，点击切换）+ 右下角「管理账本」。
///
/// 视觉对齐页面原型 `.drawer`：白底 + 右侧描边 + 圆角 + 选中行品牌浅底。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

/// 账本抽屉。
class BookDrawer extends ConsumerWidget {
  const BookDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(bookListProvider);
    final activeId = ref.watch(activeBookIdProvider).value;

    return Drawer(
      backgroundColor: Tok.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(Tok.rXl)),
        side: BorderSide(color: Tok.ink, width: Tok.bw),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
              child: Text(
                '我的账本',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
            ),
            Expanded(
              child: booksAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace _) => Center(child: Text('加载失败：$e')),
                data: (List<Book> books) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: <Widget>[
                    for (final Book b in books)
                      _BookRow(
                        name: b.name,
                        selected: b.id == activeId,
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: ToonDashedLine(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
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
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('管理账本'),
                    style: TextButton.styleFrom(
                      foregroundColor: Tok.ink2,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
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

/// 账本行（原型 `.book-row`）。
class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 2,
      dy: 2,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Tok.brandTint : null,
          borderRadius: BorderRadius.circular(Tok.rMd),
          border: Border.all(
            color: selected ? Tok.ink : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected ? Tok.hard(d: 2.5) : null,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.menu_book_rounded, size: 20, color: Tok.ink2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, size: 20, color: Tok.brandDeep),
          ],
        ),
      ),
    );
  }
}
