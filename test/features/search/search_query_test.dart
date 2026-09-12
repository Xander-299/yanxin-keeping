/// 搜索匹配纯函数测试：备注 / 分类名 / 金额三类命中的口径。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/features/search/application/search_query.dart';

/// 造一笔流水，只关心匹配用到的三个字段。
TxRow _tx({
  String note = '',
  int amountCents = 100,
  String? categoryId = 'c1',
  String type = 'expense',
}) => TxRow(
  id: 't1',
  bookId: 'b1',
  accountId: 'a1',
  type: type,
  amountCents: amountCents,
  occurredAt: 0,
  createdAt: 0,
  updatedAt: 0,
  categoryId: categoryId,
  note: note,
  source: 'manual',
  dirty: 1,
);

bool _hit({
  required String query,
  String note = '',
  int amountCents = 100,
  String categoryName = '餐饮',
}) => matchesQuery(
  tx: _tx(note: note, amountCents: amountCents),
  categoryName: categoryName,
  query: query,
);

void main() {
  group('normalizeQuery', () {
    test('去首尾空白、去金额符号与千分位、英文转小写', () {
      expect(normalizeQuery('  午餐 '), '午餐');
      expect(normalizeQuery('¥88.88'), '88.88');
      expect(normalizeQuery('￥1,234.56'), '1234.56');
      expect(normalizeQuery('Lunch'), 'lunch');
      expect(normalizeQuery('1，234'), '1234');
    });

    test('超长关键词截断到上限，避免超长串进匹配', () {
      final long = 'a' * 200;
      expect(normalizeQuery(long).length, kSearchKeywordMaxLength);
    });
  });

  group('备注命中', () {
    test('子串包含（中文）', () {
      expect(_hit(query: '午餐', note: '和同事吃午餐'), isTrue);
      expect(_hit(query: '午餐', note: '晚餐'), isFalse);
    });

    test('大小写不敏感（英文）', () {
      expect(_hit(query: 'lunch', note: 'Lunch with team'), isTrue);
      expect(_hit(query: 'LUNCH', note: 'lunch'), isTrue);
    });

    test('前后空白不影响', () {
      expect(_hit(query: '  午餐  ', note: '午餐'), isTrue);
    });
  });

  group('分类名命中', () {
    test('按解析出的分类名做子串匹配', () {
      expect(_hit(query: '餐饮', categoryName: '餐饮'), isTrue);
      expect(_hit(query: '饮', categoryName: '餐饮'), isTrue);
      expect(_hit(query: '交通', categoryName: '餐饮'), isFalse);
    });

    test('未分类也参与匹配', () {
      expect(_hit(query: '未分类', categoryName: '未分类'), isTrue);
    });
  });

  group('金额命中（「元.分」文本子串）', () {
    test('查 88 命中 88.00 / 188.00 / 88.88 / 8.88', () {
      expect(_hit(query: '88', amountCents: 8800), isTrue);
      expect(_hit(query: '88', amountCents: 18800), isTrue);
      expect(_hit(query: '88', amountCents: 8888), isTrue);
      expect(_hit(query: '88', amountCents: 888), isTrue);
    });

    test('带小数点的查询不会漏掉尾随 0', () {
      expect(_hit(query: '88.8', amountCents: 8880), isTrue); // 88.80
      expect(_hit(query: '88.8', amountCents: 8888), isTrue); // 88.88
      expect(_hit(query: '88.8', amountCents: 8800), isFalse); // 88.00
    });

    test('跨小数点的子串同样命中（0.5 → 10.50）', () {
      expect(_hit(query: '0.5', amountCents: 1050), isTrue);
      expect(_hit(query: '0.5', amountCents: 50), isTrue); // 0.50
    });

    test('小数金额的前导 0 不丢：查 0.05 命中 5 分', () {
      expect(_hit(query: '0.05', amountCents: 5), isTrue);
      expect(_hit(query: '0.05', amountCents: 105), isFalse); // 1.05
    });

    test('金额符号与千分位在查询里被忽略', () {
      expect(_hit(query: '¥1,234.56', amountCents: 123456), isTrue);
    });

    test('不匹配的金额不命中', () {
      expect(_hit(query: '99', amountCents: 100), isFalse); // 1.00
      expect(_hit(query: '88.9', amountCents: 8888), isFalse); // 88.88
    });
  });

  group('组合与边界', () {
    test('三类字段取并集：备注 / 分类 / 金额命中任一即可', () {
      expect(_hit(query: '午餐', note: '和同事吃午餐', amountCents: 999), isTrue);
      expect(_hit(query: '餐饮', note: '无关键词', amountCents: 999), isTrue);
      expect(_hit(query: '999', note: '无关键词', amountCents: 99900), isTrue);
      expect(
        _hit(query: '打车', note: '无关键词', amountCents: 999, categoryName: '餐饮'),
        isFalse,
      );
    });

    test('纯文本查询不会走金额分支', () {
      // 「午餐」不含数字，即使金额文本里有字符也不该命中
      expect(_hit(query: '午餐', note: '', amountCents: 8800), isFalse);
    });

    test('空 / 纯空白查询恒为 false（未输入时显示引导，不显示全部流水）', () {
      expect(_hit(query: '', note: '午餐', amountCents: 8800), isFalse);
      expect(_hit(query: '   ', note: '午餐', amountCents: 8800), isFalse);
      expect(_hit(query: '¥', note: '午餐', amountCents: 8800), isFalse);
    });

    test('中文与数字混合查询走文本匹配', () {
      expect(_hit(query: '午餐88', note: '午餐88元'), isTrue);
      expect(_hit(query: '午餐88', note: '午餐'), isFalse);
    });
  });

  group('filterTx', () {
    test('空关键词返回空列表（不返回全量）', () {
      final items = <TxRow>[_tx(note: '午餐'), _tx(note: '晚餐')];
      expect(
        filterTx(items: items, categoryNameOf: (_) => '餐饮', query: '  '),
        isEmpty,
      );
    });

    test('保持入参顺序，分类名由回调解出', () {
      final items = <TxRow>[
        _tx(note: '午餐'),
        _tx(note: '打车', categoryId: 'c2'),
        _tx(note: '咖啡'),
      ];
      String nameOf(String? id) => id == 'c2' ? '交通' : '餐饮';

      final hit = filterTx(
        items: items,
        categoryNameOf: nameOf,
        query: '交通',
      );
      expect(hit.map((t) => t.note), <String>['打车']);

      final both = filterTx(items: items, categoryNameOf: nameOf, query: '餐');
      expect(both.map((t) => t.note), <String>['午餐', '咖啡']);
    });
  });

  group('parsePlan（F7.5 类型指令）', () {
    test('单个类型词 → 只筛类型，无剩余关键词', () {
      final p = parsePlan('仅支出');
      expect(p.type, 'expense');
      expect(p.text, isEmpty);
      expect(p.isEmpty, isFalse); // 有类型条件 → 不是引导态
      expect(p.typeWord, '仅支出');
    });

    test('三个类型词各自映射到 Transactions.type', () {
      expect(parsePlan('仅支出').type, 'expense');
      expect(parsePlan('仅收入').type, 'income');
      expect(parsePlan('转账').type, 'transfer');
    });

    test('类型词 + 关键词：类型生效，关键词剥离后保留', () {
      final p = parsePlan('仅支出 午餐');
      expect(p.type, 'expense');
      expect(p.text, '午餐');
    });

    test('多个类型词以「最后出现」的为准，且全部被剥离（Q2）', () {
      final p = parsePlan('仅支出 转账');
      expect(p.type, 'transfer');
      expect(p.text, isEmpty);
    });

    test('类型词必须独立成词：转账手续费不被误判成指令', () {
      final p = parsePlan('转账手续费');
      expect(p.type, isNull);
      expect(p.text, '转账手续费');
    });

    test('空 / 纯空白 / 只有金额符号 → isEmpty（显示引导态）', () {
      expect(parsePlan('').isEmpty, isTrue);
      expect(parsePlan('   ').isEmpty, isTrue);
      expect(parsePlan(' ¥ ').isEmpty, isTrue);
    });

    test('普通关键词不受影响', () {
      final p = parsePlan('午餐');
      expect(p.type, isNull);
      expect(p.text, '午餐');
      expect(p.typeWord, isNull);
    });

    test('stripTypeWords 保留原文，不 normalize 掉 ¥ / 千分位', () {
      expect(stripTypeWords('仅支出 ¥200'), '¥200');
      expect(stripTypeWords('仅收入 1,234.56'), '1,234.56');
      expect(stripTypeWords('仅支出'), isEmpty);
    });
  });

  group('filterTx 类型筛选（F7.5）', () {
    /// 三种类型各一笔，备注互不相同。
    List<TxRow> threeTypes() => <TxRow>[
      _tx(note: '午餐'),
      _tx(note: '工资', type: 'income'),
      _tx(note: '转存', type: 'transfer'),
    ];

    test('只输类型词 → 返回该类型全部流水（不再走文本匹配）', () {
      String nameOf(String? _) => '餐饮';
      expect(
        filterTx(items: threeTypes(), categoryNameOf: nameOf, query: '仅支出')
            .map((t) => t.note),
        <String>['午餐'],
      );
      expect(
        filterTx(items: threeTypes(), categoryNameOf: nameOf, query: '仅收入')
            .map((t) => t.note),
        <String>['工资'],
      );
      expect(
        filterTx(items: threeTypes(), categoryNameOf: nameOf, query: '转账')
            .map((t) => t.note),
        <String>['转存'],
      );
    });

    test('类型词 + 关键词 = 交集（先筛类型，再走原口径）', () {
      final items = <TxRow>[
        _tx(note: '午餐'),
        _tx(note: '打车'),
        _tx(note: '午餐补贴', type: 'income'),
      ];
      final hit = filterTx(
        items: items,
        categoryNameOf: (_) => '餐饮',
        query: '仅支出 午餐',
      );
      // 打车被关键词排除，午餐补贴被类型排除
      expect(hit.map((t) => t.note), <String>['午餐']);
    });

    test('该类型没有数据 → 空列表（如转账）', () {
      expect(
        filterTx(
          items: <TxRow>[_tx(note: '午餐')],
          categoryNameOf: (_) => '餐饮',
          query: '转账',
        ),
        isEmpty,
      );
    });
  });
}
