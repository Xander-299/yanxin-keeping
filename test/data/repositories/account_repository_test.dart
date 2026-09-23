/// 账户仓储单测（F7.7 C 批）：icon / color 落库与局部更新。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late AccountRepository repo;
  late String bookId;

  setUp(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    repo = AccountRepository(db);
    bookId = (await BookRepository(db).ensureDefaultBook()).id;
  });

  test('create 默认 icon / color 为空串（跟随类型）', () async {
    final a = await repo.create(bookId: bookId, name: '现金钱包');
    expect(a.icon, '');
    expect(a.color, '');
  });

  test('create 可带自选 icon / color，读回一致', () async {
    final a = await repo.create(
      bookId: bookId,
      name: '招行储蓄卡',
      icon: 'piggy',
      color: '#FF6B8A',
    );
    expect(a.icon, 'piggy');
    expect(a.color, '#FF6B8A');

    final read = await repo.getById(a.id);
    expect(read!.icon, 'piggy');
    expect(read.color, '#FF6B8A');
  });

  test('update 可单独改 icon / color，不碰其它字段', () async {
    final a = await repo.create(
      bookId: bookId,
      name: '支付宝',
      type: 'alipay',
      initialBalanceCents: 12345,
      icon: 'wallet',
      color: '#5A8DFF',
    );

    final updated = await repo.update(a.id, icon: 'yuan', color: '#FFB627');
    expect(updated.icon, 'yuan');
    expect(updated.color, '#FFB627');
    expect(updated.name, '支付宝');
    expect(updated.type, 'alipay');
    expect(updated.initialBalanceCents, 12345);

    // 传 null = 不动这一列
    final again = await repo.update(a.id, name: '支付宝2');
    expect(again.icon, 'yuan');
    expect(again.color, '#FFB627');
    expect(again.name, '支付宝2');
  });

  test('update 可把 icon / color 清回空串（恢复跟随类型）', () async {
    final a = await repo.create(
      bookId: bookId,
      name: '微信零钱',
      icon: 'phone',
      color: '#5FD068',
    );
    final cleared = await repo.update(a.id, icon: '', color: '');
    expect(cleared.icon, '');
    expect(cleared.color, '');
  });
}
