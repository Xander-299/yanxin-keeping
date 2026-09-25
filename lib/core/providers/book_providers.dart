/// 账本相关的应用状态：当前账本 id（持久化）+ 当前账本 + 账本列表。
///
/// 对应旧栈 `stores/book.js`（BUG-016 的修复点：当前账本 id 落库，杀进程不丢）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'database.dart';

/// 当前账本 id。首次启动没有值时建默认账本并落库。
final activeBookIdProvider = AsyncNotifierProvider<ActiveBookIdController, String?>(
  ActiveBookIdController.new,
);

class ActiveBookIdController extends AsyncNotifier<String?> {
  /// 本次 build 时「库里**还完全没有**主账本记录」→ 这份 App 数据是本机第一次使用。
  ///
  /// 用途：新手引导（F7.14）**只在全新安装**时自动弹 —— 老用户（含从旧包覆盖安装上来的）
  /// 不弹。`active_book_id` 自 F1 起每次冷启动都会落库，老用户必有值，是「是否新装」的唯一真源。
  ///
  /// ⚠️ 判据是「读到的瞬间 `getActiveBookId()` 返回 null」，**不是**「本次走了
  /// `ensureDefaultBook` 分支」—— 后者在「当前账本被软删」等边缘情况也会命中
  /// （那时 `active_book_id` 其实有值），会把老用户误判成新装。
  bool isFreshInstall = false;

  @override
  Future<String?> build() async {
    final repo = ref.watch(bookRepositoryProvider);
    final stored = await repo.getActiveBookId();
    isFreshInstall = stored == null;
    if (stored != null) {
      final book = await repo.getById(stored);
      if (book != null) return stored;
    }
    final book = await repo.ensureDefaultBook();
    await repo.setActiveBookId(book.id);
    return book.id;
  }

  /// 切换当前账本（持久化）。
  Future<void> select(String id) async {
    await ref.read(bookRepositoryProvider).setActiveBookId(id);
    state = AsyncData(id);
  }
}

/// 当前账本对象。切换账本时自动刷新。
final currentBookProvider = FutureProvider<Book?>((ref) async {
  final id = await ref.watch(activeBookIdProvider.future);
  if (id == null) return null;
  return ref.watch(bookRepositoryProvider).getById(id);
});

/// 全部未删除账本。
final bookListProvider = FutureProvider<List<Book>>(
  (ref) => ref.watch(bookRepositoryProvider).listAll(),
);
