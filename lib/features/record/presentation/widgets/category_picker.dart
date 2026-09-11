/// 分类选择底部弹层（按 kind 过滤的宫格）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/db/database.dart';

/// 打开分类选择器，返回选中的分类（取消返回 null）。
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => _CategoryGrid(categories: categories),
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GridView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemCount: categories.length,
        itemBuilder: (BuildContext context, int index) {
          final c = categories[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).pop(c),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    c.name.isEmpty ? '?' : c.name.substring(0, 1),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
