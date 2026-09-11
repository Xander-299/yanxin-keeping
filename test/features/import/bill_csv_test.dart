/// 移植自旧栈 tests/bill-import/csv.test.js。
///
/// 必须状态机实现：引号包裹、字段内逗号/换行、CRLF/LF、"" 转义。
/// 语法层不校验列数——字段数不齐原样保留，由上层 profile 校验必需列。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/import/data/bill_csv.dart';

void main() {
  group('parseCsvRows 基础语法', () {
    test('简单逗号分隔', () {
      expect(parseCsvRows('a,b,c'), [
        ['a', 'b', 'c'],
      ]);
    });

    test('CRLF 与 LF 混用作行分隔', () {
      expect(parseCsvRows('a,b\r\nc,d\ne,f'), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
      ]);
    });

    test('尾随换行不产生空行', () {
      expect(parseCsvRows('a,b\n'), [
        ['a', 'b'],
      ]);
      expect(parseCsvRows('a,b\r\n'), [
        ['a', 'b'],
      ]);
    });

    test('行间空行跳过（微信账单中部有空行）', () {
      expect(parseCsvRows('a,b\n\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('字段数不齐原样保留（列校验是上层职责）', () {
      expect(parseCsvRows('a,b\nc'), [
        ['a', 'b'],
        ['c'],
      ]);
    });
  });

  group('parseCsvRows 引号处理', () {
    test('引号内逗号不错位', () {
      expect(parseCsvRows('a,"b,c",d'), [
        ['a', 'b,c', 'd'],
      ]);
    });

    test('引号内换行保留在字段内', () {
      expect(parseCsvRows('a,"line1\nline2",b'), [
        ['a', 'line1\nline2', 'b'],
      ]);
    });

    test('引号内 CRLF 保留', () {
      expect(parseCsvRows('a,"x\r\ny",b'), [
        ['a', 'x\r\ny', 'b'],
      ]);
    });

    test('"" 转义为单个引号', () {
      expect(parseCsvRows('"say ""hi""",b'), [
        ['say "hi"', 'b'],
      ]);
    });

    test('引号包裹的纯逗号字段', () {
      expect(parseCsvRows('",",","'), [
        [',', ','],
      ]);
    });

    test('引号后紧跟内容（容错：贪婪到收尾引号后取到下一个分隔符）', () {
      // 严格 RFC 会算错位；账单不会出现，容错解析为普通字段
      expect(parseCsvRows('"a"b,c'), [
        ['ab', 'c'],
      ]);
    });

    test('未闭合引号：容忍到行/文件尾', () {
      expect(parseCsvRows('a,"unclosed'), [
        ['a', 'unclosed'],
      ]);
    });
  });

  group('parseCsvRows 真实账单片段', () {
    test('微信样式：备注含逗号与引号', () {
      const csv =
          '交易时间,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,备注\n'
          '2026-09-01 12:30:00,"美团平台商户","外卖订单（满减,含配送费）",支出,"¥12.30",零钱,支付成功,10001,"客户留言：""快点"""';
      final rows = parseCsvRows(csv);
      expect(rows, hasLength(2));
      expect(rows[1][2], '外卖订单（满减,含配送费）');
      expect(rows[1][4], '¥12.30');
      expect(rows[1][8], '客户留言："快点"');
    });
  });
}
