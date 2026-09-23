/// 资产聚合纯函数测试（SPEC-F7.5-b §6）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/features/assets/application/asset_aggregate.dart';

Account _account(
  String id, {
  int initialCents = 0,
  String type = 'cash',
  String name = '账户',
}) {
  final int now = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  return Account(
    id: id,
    bookId: 'b1',
    name: name,
    type: type,
    initialBalanceCents: initialCents,
    sortOrder: 0,
    icon: '',
    color: '',
    createdAt: now,
    updatedAt: now,
    dirty: 1,
  );
}

TxRow _tx({
  required String accountId,
  required String type,
  required int cents,
  String id = 't1',
}) {
  final int at = DateTime(2026, 9, 10, 12).millisecondsSinceEpoch;
  return TxRow(
    id: id,
    bookId: 'b1',
    accountId: accountId,
    categoryId: null,
    type: type,
    amountCents: cents,
    note: '',
    occurredAt: at,
    source: 'manual',
    createdAt: at,
    updatedAt: at,
    dirty: 1,
  );
}

void main() {
  group('buildAssetSummary', () {
    test('收入进账：初始 100 元 + 收入 50 元 = 150 元', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 10000)],
        <TxRow>[_tx(accountId: 'a1', type: 'income', cents: 5000)],
      );

      expect(summary.items.single.balanceCents, 15000);
      expect(summary.items.single.incomeCents, 5000);
      expect(summary.items.single.expenseCents, 0);
    });

    test('支出出账：初始 100 元 − 支出 30 元 = 70 元', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 10000)],
        <TxRow>[_tx(accountId: 'a1', type: 'expense', cents: 3000)],
      );

      expect(summary.items.single.balanceCents, 7000);
      expect(summary.items.single.expenseCents, 3000);
    });

    test('transfer 不计入任何账户', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 10000)],
        <TxRow>[
          _tx(accountId: 'a1', type: 'transfer', cents: 8888, id: 't1'),
        ],
      );

      expect(summary.items.single.balanceCents, 10000);
      expect(summary.items.single.txCount, 0);
    });

    test('多账户互不串账', () {
      final summary = buildAssetSummary(
        <Account>[
          _account('a1', initialCents: 1000, name: '现金'),
          _account('a2', initialCents: 2000, name: '银行卡'),
        ],
        <TxRow>[
          _tx(accountId: 'a1', type: 'expense', cents: 100, id: 't1'),
          _tx(accountId: 'a2', type: 'income', cents: 500, id: 't2'),
        ],
      );

      expect(summary.itemOf('a1')!.balanceCents, 900);
      expect(summary.itemOf('a2')!.balanceCents, 2500);
    });

    test('净资产 = 各账户余额之和（含负余额账户）', () {
      final summary = buildAssetSummary(
        <Account>[
          _account('a1', initialCents: 10000),
          _account('a2', initialCents: 0, type: 'credit'),
        ],
        <TxRow>[_tx(accountId: 'a2', type: 'expense', cents: 3000)],
      );

      expect(summary.count, 2);
      expect(summary.itemOf('a2')!.balanceCents, -3000);
      expect(summary.netCents, 7000);
    });

    test('净资和为负时 netCents < 0', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 0)],
        <TxRow>[_tx(accountId: 'a1', type: 'expense', cents: 500)],
      );

      expect(summary.netCents, -500);
    });

    test('账户无流水时余额 = 初始余额', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 12345)],
        <TxRow>[],
      );

      expect(summary.items.single.balanceCents, 12345);
      expect(summary.items.single.txCount, 0);
    });

    test('空账户列表 → 净资产 0、items 空', () {
      final summary = buildAssetSummary(<Account>[], <TxRow>[]);

      expect(summary.items, isEmpty);
      expect(summary.netCents, 0);
      expect(summary.count, 0);
    });

    test('恒等式：初始 + 收入 − 支出 == 余额', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 10000)],
        <TxRow>[
          _tx(accountId: 'a1', type: 'income', cents: 20000, id: 't1'),
          _tx(accountId: 'a1', type: 'expense', cents: 7500, id: 't2'),
          _tx(accountId: 'a1', type: 'income', cents: 250, id: 't3'),
        ],
      );

      final AssetItem item = summary.items.single;
      expect(item.incomeCents, 20250);
      expect(item.expenseCents, 7500);
      expect(item.balanceCents, 22750);
      expect(item.txCount, 3);
      expect(item.isConsistent, isTrue);
    });

    test('账户 id 匹配不上的流水被忽略', () {
      final summary = buildAssetSummary(
        <Account>[_account('a1', initialCents: 100)],
        <TxRow>[_tx(accountId: 'ghost', type: 'expense', cents: 999)],
      );

      expect(summary.items.single.balanceCents, 100);
      expect(summary.netCents, 100);
    });
  });
}
