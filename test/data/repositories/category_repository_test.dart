/// 分类仓储（schema v4）：预置补齐、两级、校验、排序、归档、迁移。
///
/// 对应任务书 §7「测试要求」里能在仓储层覆盖的部分；UI 层的选择器/编辑器另有 widget 测试。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;
  late TransactionRepository txRepo;
  late String bookId;
  late String accountId;

  setUp(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    final Book book = await BookRepository(db).create(name: 'x');
    bookId = book.id;
    repo = CategoryRepository(db);
    txRepo = TransactionRepository(db);
    accountId = (await AccountRepository(db).listByBook(bookId)).first.id;
  });

  Future<Category> mk(
    String name, {
    String kind = 'expense',
    String? parentId,
    String icon = '',
    String color = '',
  }) => repo.create(
    bookId: bookId,
    name: name,
    kind: kind,
    parentId: parentId,
    icon: icon,
    color: color,
  );

  Future<TxRow> addTx(
    String categoryId, {
    int cents = 1000,
    String note = '午饭',
    int? occurredAt,
  }) => txRepo.create(
    bookId: bookId,
    accountId: accountId,
    type: 'expense',
    amountCents: cents,
    occurredAt: occurredAt ?? DateTime(2026, 10, 5, 12).millisecondsSinceEpoch,
    categoryId: categoryId,
    note: note,
  );

  group('预置分类', () {
    test('新建账本：11 个支出 + 7 个收入，且带图标/颜色', () async {
      final List<Category> expense = await repo.listByBook(bookId, kind: 'expense');
      final List<Category> income = await repo.listByBook(bookId, kind: 'income');
      expect(expense.length, 11);
      expect(income.length, 7);
      expect(expense.every((Category c) => c.icon.isNotEmpty), isTrue);
      expect(expense.every((Category c) => c.color.startsWith('#')), isTrue);
      expect(expense.map((Category c) => c.name), contains('通讯'));
    });

    test('ensurePresets 幂等：重复调用不会多出分类', () async {
      final int before = (await repo.listByBook(bookId)).length;
      await repo.ensurePresets(bookId);
      await repo.ensurePresets(bookId);
      expect((await repo.listByBook(bookId)).length, before);
    });

    test('用户删掉的预置分类不会被补装复活（真机实测踩到的坑）', () async {
      final Category comm = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '通讯');
      await repo.deleteIfUnused(comm.id);

      await repo.ensurePresets(bookId);

      final List<Category> after = await repo.listByBook(bookId, kind: 'expense');
      expect(
        after.where((Category c) => c.name == '通讯'),
        isEmpty,
        reason: '软删的预置分类不该被 ensurePresets 重新插入',
      );
    });

    test('老账本：旧名字命中别名不重复插，且补齐图标、不改用户改过的名字', () async {
      // 模拟 v3 老账本：把「投资收益」改成旧名「理财」，并清空图标
      final Category invest = (await repo.listByBook(bookId, kind: 'income'))
          .firstWhere((Category c) => c.name == '投资收益');
      await repo.update(invest.id, name: '理财', icon: '');
      // 老库里根本没有「通讯」这一行 → 物理删掉（软删会被「不复活」规则挡住）
      final Category comm = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '通讯');
      await db.customStatement('DELETE FROM categories WHERE id = ?', <Object?>[comm.id]);

      await repo.ensurePresets(bookId);

      final List<Category> income = await repo.listByBook(bookId, kind: 'income');
      expect(
        income.where((Category c) => c.name == '理财').length,
        1,
        reason: '命中别名（理财）后不应再插一条「投资收益」',
      );
      expect(income.where((Category c) => c.name == '投资收益'), isEmpty);
      expect(
        income.firstWhere((Category c) => c.name == '理财').icon,
        'invest',
        reason: '只补空图标，名字保持用户改过的',
      );
      final List<Category> expense = await repo.listByBook(bookId, kind: 'expense');
      expect(expense.where((Category c) => c.name == '通讯').length, 1);
    });
  });

  group('两级结构', () {
    test('可以建二级分类，parentId 指向一级', () async {
      final Category food = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '餐饮');
      final Category breakfast = await mk('早餐', parentId: food.id);
      expect(breakfast.parentId, food.id);
      expect((await repo.childrenOf(food.id)).map((Category c) => c.name), contains('早餐'));
    });

    test('最多两级：给二级分类再挂子分类会抛错', () async {
      final Category food = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '餐饮');
      final Category breakfast = await mk('早餐', parentId: food.id);
      expect(
        () => mk('豆浆', parentId: breakfast.id),
        throwsA(isA<CategoryException>()),
      );
    });

    test('不能把分类挂到自己下面', () async {
      final Category food = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '餐饮');
      expect(() => repo.setParent(food.id, food.id), throwsA(isA<CategoryException>()));
    });

    test('子分类必须和父分类同属支出/收入', () async {
      final Category salary = (await repo.listByBook(bookId, kind: 'income'))
          .firstWhere((Category c) => c.name == '工资');
      expect(
        () => mk('早饭', kind: 'expense', parentId: salary.id),
        throwsA(isA<CategoryException>()),
      );
    });
  });

  group('名称校验', () {
    test('空名 / 纯空格抛错', () async {
      expect(() => mk(''), throwsA(isA<CategoryException>()));
      expect(() => mk('   '), throwsA(isA<CategoryException>()));
    });

    test('同一父级下重名抛错；不同父级可以同名', () async {
      final Category food = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '餐饮');
      final Category transport = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '交通');
      await mk('早餐', parentId: food.id);
      expect(() => mk('早餐', parentId: food.id), throwsA(isA<CategoryException>()));
      // 换一个父级就允许同名
      final Category other = await mk('早餐', parentId: transport.id);
      expect(other.name, '早餐');
    });

    test('名称自动去掉首尾空格', () async {
      final Category c = await mk('  夜宵  ');
      expect(c.name, '夜宵');
    });

    test('kind 非法抛错', () async {
      expect(
        () => mk('bad', kind: 'other'),
        throwsA(isA<CategoryException>()),
      );
    });
  });

  group('编辑与排序', () {
    test('改名 / 改图标 / 改颜色立即生效', () async {
      final Category c = await mk('打车', icon: 'taxi', color: '#5A8DFF');
      await repo.update(c.id, name: '网约车', icon: 'transport', color: '#FF8A3D');
      final Category fresh = (await repo.getById(c.id))!;
      expect(fresh.name, '网约车');
      expect(fresh.icon, 'transport');
      expect(fresh.color, '#FF8A3D');
    });

    test('reorder 持久化：重新查询顺序不变', () async {
      final List<Category> roots =
          (await repo.listByBook(bookId, kind: 'expense'))
              .where((Category c) => c.parentId == null)
              .toList()
            ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));
      final List<String> reversed =
          roots.reversed.map((Category c) => c.id).toList();
      await repo.reorder(reversed);

      final List<Category> after =
          (await repo.listByBook(bookId, kind: 'expense'))
              .where((Category c) => c.parentId == null)
              .toList()
            ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));
      expect(after.map((Category c) => c.id).toList(), reversed);
    });
  });

  group('删除 / 归档 / 迁移', () {
    test('没有被引用的分类可以删除', () async {
      final Category c = await mk('临时');
      await repo.deleteIfUnused(c.id);
      expect(await repo.getById(c.id), isNull);
    });

    test('被账单引用时不能直接删，报错里带笔数', () async {
      final Category c = await mk('临时');
      await addTx(c.id);
      await expectLater(
        repo.deleteIfUnused(c.id),
        throwsA(
          isA<CategoryException>().having(
            (CategoryException e) => e.message,
            'message',
            contains('1 笔账单'),
          ),
        ),
      );
    });

    test('归档后不在可用列表，但历史账单仍能按 id 解析到名字', () async {
      final Category c = await mk('旧分类', icon: 'other');
      final TxRow tx = await addTx(c.id);
      await repo.archive(c.id);

      final List<Category> active =
          await repo.listByBook(bookId, includeArchived: false);
      expect(active.any((Category x) => x.id == c.id), isFalse);

      // 历史账单仍挂着这个 id，且仓储能取到（改名/归档都不影响历史显示）
      final TxRow? fresh = await txRepo.getById(tx.id);
      expect(fresh!.categoryId, c.id);
      final Category? archived = await repo.getById(c.id);
      expect(archived!.name, '旧分类');
      expect(archived.icon, 'other');
    });

    test('归档父分类会连带归档子分类', () async {
      final Category food = (await repo.listByBook(bookId, kind: 'expense'))
          .firstWhere((Category c) => c.name == '餐饮');
      final Category breakfast = await mk('早餐', parentId: food.id);
      await repo.archive(food.id);
      expect((await repo.getById(breakfast.id))!.isArchived, 1);
    });

    test('迁移后删除：只改分类，金额/日期/备注/账户不变', () async {
      final Category from = await mk('旧分类');
      final Category to = await mk('新分类');
      final TxRow tx = await addTx(from.id, cents: 12345, note: '星巴克');

      await repo.migrateAndDelete(from.id, to.id);

      final TxRow fresh = (await txRepo.getById(tx.id))!;
      expect(fresh.categoryId, to.id);
      expect(fresh.amountCents, 12345);
      expect(fresh.note, '星巴克');
      expect(fresh.occurredAt, tx.occurredAt);
      expect(fresh.accountId, tx.accountId);
      expect(await repo.getById(from.id), isNull);
    });

    test('不能跨收支类型迁移', () async {
      final Category expense = await mk('临时');
      final Category salary = (await repo.listByBook(bookId, kind: 'income'))
          .firstWhere((Category c) => c.name == '工资');
      expect(
        () => repo.migrateAndDelete(expense.id, salary.id),
        throwsA(isA<CategoryException>()),
      );
    });

    test('有子分类时不能直接删（不留孤儿）', () async {
      final Category parent = await mk('父');
      await mk('子', parentId: parent.id);
      expect(
        () => repo.deleteIfUnused(parent.id),
        throwsA(isA<CategoryException>()),
      );
      // 子分类仍然挂在原父级，没有变成无主
      final Category? parentFresh = await repo.getById(parent.id);
      expect(parentFresh, isNotNull);
      final List<Category> kids = await repo.childrenOf(parent.id);
      expect(kids.single.parentId, parent.id);
    });
  });
}
