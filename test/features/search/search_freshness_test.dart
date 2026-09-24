/// 搜索快照新鲜度回归（F7.7 D 批真机走查抓到的真 bug）。
///
/// 背景：`searchProvider` 是**常驻** provider（非 autoDispose，浮层关掉再打开不重建），
/// 原先没有任何失效信号 → 「刚加完账户 / 刚记一笔」后回搜索是**搜不到**的
/// （实测表现：搜新账户名、搜新流水金额都命中不到，杀进程重启 App 才出现）。
/// 修法：`build()` 里 `ref.watch(dataEpochProvider)` —— 项目既有的「写操作版本号」，
/// 所有写操作成功后都会 bump（`record_page` / `assets_controller` / `import_page` …）。
///
/// 本用例把「不 watch 就会失败」这件事钉死：bump 之后必须拿到新快照。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/search/application/search_controller.dart';
import 'package:yanxin/features/search/application/search_query.dart';

import '../../helpers/test_database.dart';

void main() {
  test('写操作 bump 后搜索快照自动作废：新账户名 / 新流水都能搜到', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final book = await BookRepository(db).ensureDefaultBook();

    // Riverpod 3 未公开导出 Override 类型 → 不能写 <Override>[...] 注解
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // ① 第一次取快照（此刻库里还没有任何流水）
    final SearchState first = await container.read(searchProvider.future);
    expect(first.items, isEmpty);
    expect(first.nameOfAccount('nobody'), '');

    // ② 像用户那样：新增账户 + 记一笔
    final Account account = await AccountRepository(
      db,
    ).create(bookId: book.id, name: 'QABank');
    final List<Category> categories = await CategoryRepository(
      db,
    ).listByBook(book.id);
    await TransactionRepository(db).create(
      bookId: book.id,
      accountId: account.id,
      type: 'expense',
      amountCents: 5000,
      occurredAt: DateTime(2026, 9, 24, 10).millisecondsSinceEpoch,
      categoryId: categories.first.id,
    );

    // ③ 写操作成功后 bump（既有约定，见 `data_epoch.dart`）
    container.read(dataEpochProvider.notifier).bump();

    // ④ 再读必须拿到新数据；没有 watch dataEpoch 时这里会拿到旧快照 → 断言失败
    final SearchState next = await container.read(searchProvider.future);
    expect(next.items, hasLength(1));
    expect(next.nameOfAccount(account.id), 'QABank');

    // 账户名命中口径（D 批新增）：分类名 / 备注 / 金额都匹配不到 qabank
    expect(
      filterTx(
        items: next.items,
        categoryNameOf: next.nameOf,
        accountNameOf: next.nameOfAccount,
        query: 'QABank',
      ),
      hasLength(1),
    );
    // 金额口径也走通了（说明 items 真的换了新快照，不是只换了账户表）
    expect(
      filterTx(
        items: next.items,
        categoryNameOf: next.nameOf,
        accountNameOf: next.nameOfAccount,
        query: '50',
      ),
      hasLength(1),
    );
  });
}
