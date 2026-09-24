/// 搜索页状态：一次载入当前账本**全部**未删流水 + 分类名表 + 账户名表，之后在内存里过滤。
///
/// 对应 `docs/SPEC-F7.4-search.md` §3.1：个人记账即使含导入账单也是万级行，
/// 进页一次性读齐（一次查询）后逐键内存过滤，输入手感即时、无需防抖。
/// F7.7 D 批追加账户名表：账户名也要能搜到流水（如搜「招行」「支付宝」）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers/book_providers.dart';
import '../../../core/providers/data_epoch.dart';
import '../../../core/providers/database.dart';

/// 搜索页数据快照。
class SearchState {
  const SearchState({
    required this.bookId,
    required this.items,
    required this.categoryNames,
    required this.accountNames,
  });

  /// 当前账本 id（刷新时用）。
  final String bookId;

  /// 该账本全部未删流水（发生时间倒序）。
  final List<TxRow> items;

  /// 分类 id → 名称。
  final Map<String, String> categoryNames;

  /// 账户 id → 名称（F7.7 D 批：账户名参与关键词匹配）。
  final Map<String, String> accountNames;

  /// 分类名解析：id 为空或查不到统一回退「未分类」。
  String nameOf(String? categoryId) =>
      (categoryId == null ? null : categoryNames[categoryId]) ?? '未分类';

  /// 账户名解析：查不到回退空串（**不**回退占位词，避免占位词把每笔流水都「搜中」）。
  String nameOfAccount(String accountId) => accountNames[accountId] ?? '';
}

final searchProvider =
    AsyncNotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends AsyncNotifier<SearchState> {
  @override
  Future<SearchState> build() async {
    // 接上「写操作版本号」：本 provider 是**常驻**的（非 autoDispose），浮层关掉再打开
    // 不会重建 —— 不 watch 它就会出现「刚加完账户 / 刚记一笔，回搜索却搜不到」
    // （F7.7 D 批真机走查抓到：新账户名与新流水都不在快照里，重启 App 才出现）。
    // 所有写操作成功后都会 bump，这里 watch 一下即自动作废重取，无需在 N 处补 refresh。
    ref.watch(dataEpochProvider);

    final bookId = await ref.watch(activeBookIdProvider.future);
    if (bookId == null) {
      throw StateError('当前账本未就绪');
    }
    return _load(bookId);
  }

  Future<SearchState> _load(String bookId) async {
    final items = await ref.read(transactionRepositoryProvider).listByBook(
      bookId,
    );
    final categories = await ref
        .read(categoryRepositoryProvider)
        .listByBook(bookId);
    final accounts = await ref.read(accountRepositoryProvider).listByBook(bookId);
    return SearchState(
      bookId: bookId,
      items: items,
      categoryNames: <String, String>{
        for (final Category c in categories) c.id: c.name,
      },
      accountNames: <String, String>{
        for (final Account a in accounts) a.id: a.name,
      },
    );
  }

  /// 重新载入（搜索页里删除 / 编辑完流水后调用）。
  Future<void> refresh() async {
    final current = state.value ?? await future;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(current.bookId));
  }
}
