/// 资产页状态：当前账本的账户 + 全量流水 → `AssetSummary`。
///
/// 与首页 / 日历 / 统计**不共享月份**（资产是存量，全时间累计）。
/// watch `dataEpochProvider`：任何写操作 bump 后自动重算，不用在每个写操作处手工 refresh。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/providers/database.dart';

import 'asset_aggregate.dart';

/// 资产页 controller。
final assetsProvider = AsyncNotifierProvider<AssetsController, AssetSummary>(
  AssetsController.new,
);

class AssetsController extends AsyncNotifier<AssetSummary> {
  @override
  Future<AssetSummary> build() async {
    // 必须放在第一个 await 之前：写操作 bump 时才会重建
    ref.watch(dataEpochProvider);
    final String? bookId = await ref.watch(activeBookIdProvider.future);
    if (bookId == null) {
      throw StateError('当前账本未就绪');
    }
    final accounts = await ref.read(accountRepositoryProvider).listByBook(bookId);
    final txs = await ref.read(transactionRepositoryProvider).listByBook(bookId);
    return buildAssetSummary(accounts, txs);
  }

  /// 新增账户。返回新建的账户。[icon] / [color] 为自选装饰（'' = 跟随类型）。
  Future<Account> addAccount({
    required String name,
    required String type,
    required int initialBalanceCents,
    String icon = '',
    String color = '',
  }) async {
    final String? bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null) {
      throw StateError('当前账本未就绪');
    }
    final List<Account> existing = await ref
        .read(accountRepositoryProvider)
        .listByBook(bookId);
    final Account created = await ref.read(accountRepositoryProvider).create(
      bookId: bookId,
      name: name,
      type: type,
      initialBalanceCents: initialBalanceCents,
      sortOrder: existing.length,
      icon: icon,
      color: color,
    );
    _bump();
    return created;
  }

  /// 编辑账户（改名 / 改类型 / 改初始余额 / 改图标颜色）。
  Future<void> updateAccount(
    String id, {
    required String name,
    required String type,
    required int initialBalanceCents,
    String? icon,
    String? color,
  }) async {
    await ref.read(accountRepositoryProvider).update(
      id,
      name: name,
      type: type,
      initialBalanceCents: initialBalanceCents,
      icon: icon,
      color: color,
    );
    _bump();
  }

  /// 软删账户。调用方负责先校验「账户下无流水」。
  Future<void> deleteAccount(String id) async {
    final int changed = await ref.read(accountRepositoryProvider).softDelete(id);
    if (changed == 0) {
      throw StateError('账户不存在或已删除：$id');
    }
    _bump();
  }

  /// 取当前快照里某账户的流水笔数（删除前拦截用）；未就绪时返回 0。
  int txCountOf(String accountId) =>
      state.value?.itemOf(accountId)?.txCount ?? 0;

  void _bump() => ref.read(dataEpochProvider.notifier).bump();
}
