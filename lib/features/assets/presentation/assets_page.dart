/// 资产页：净资产卡 + 账户余额列表（底栏第 4 个 tab）。
///
/// 数据源全部真实（账户表 + 全量流水），口径见 `docs/SPEC-F7.5-assets.md` §3.2：
/// 余额 = 初始余额 + Σ收入 − Σ支出，transfer 不计。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/utils/money.dart';

import '../application/account_meta.dart';
import '../application/asset_aggregate.dart';
import '../application/assets_controller.dart';
import 'widgets/account_form_sheet.dart';

/// 资产页。
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AssetSummary> async = ref.watch(assetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新增账户',
            onPressed: () => showAccountFormSheet(context, ref),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('加载失败：$e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(assetsProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (AssetSummary summary) {
          if (summary.items.isEmpty) return _EmptyState(ref: ref);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              _NetWorthCard(summary: summary),
              const SizedBox(height: 12),
              for (final AssetItem item in summary.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AccountTile(item: item, ref: ref),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 净资产卡：大号金额 + 账户数。
class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.summary});

  final AssetSummary summary;

  @override
  Widget build(BuildContext context) {
    final bool negative = summary.netCents < 0;
    final Color color = negative ? const Color(0xFFFF6B6B) : const Color(0xFFFFAF38);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '净资产',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '¥ ${centsToYuan(summary.netCents, group: true)}',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${summary.count} 个账户 · 全时间累计',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 账户一行：图标 + 名称/类型 + 余额（+ 累计收支小字）。
class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.item, required this.ref});

  final AssetItem item;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final bool negative = item.balanceCents < 0;
    final Color balanceColor = negative
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFE8E8E8);
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showAccountFormSheet(context, ref, account: item.account),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFAF38).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  accountTypeIcon(item.account.type),
                  size: 20,
                  color: const Color(0xFFFFAF38),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${accountTypeLabel(item.account.type)} · '
                      '收 ${centsToYuan(item.incomeCents)} / '
                      '支 ${centsToYuan(item.expenseCents)}',
                      style: TextStyle(fontSize: 11, color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                centsToYuan(item.balanceCents, group: true),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: balanceColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态：一个账户都没有。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            const Text('还没有账户'),
            const SizedBox(height: 8),
            Text(
              '建一个账户（现金 / 储蓄卡 / 支付宝…），就能看到净资产分布',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => showAccountFormSheet(context, ref),
              child: const Text('新建账户'),
            ),
          ],
        ),
      ),
    );
  }
}
