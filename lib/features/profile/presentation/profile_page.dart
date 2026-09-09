/// 「我的」页：占位骨架 + 分类管理入口（分类功能已实现，需要可达入口）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/providers/book_providers.dart';

/// 我的。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(currentBookProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFF2A2A2E),
                  child: Text('颜', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('颜芯记账用户', style: TextStyle(fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                      '当前账本：${bookAsync.value?.name ?? '…'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _EntryTile(
              icon: Icons.category_rounded,
              title: '分类管理',
              onTap: () => context.push('/categories'),
            ),
            _EntryTile(
              icon: Icons.file_download_rounded,
              title: '导入账单',
              onTap: () => context.push('/import'),
            ),
            const _EntryTile(
              icon: Icons.construction_rounded,
              title: '数据导出（建设中）',
            ),
            const _EntryTile(
              icon: Icons.construction_rounded,
              title: '设置（建设中）',
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
        enabled: onTap != null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
