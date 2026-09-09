/// 移植自旧栈 tests/bill-import/decode.test.js。
///
/// UTF-8（BOM 优先）→ 出现无法解码 → 回退 GBK → 都失败明确报错。
/// 注意：gbk_codec 对未知序列不产 U+FFFD，改用重编码回环校验。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/import/data/bill_decode.dart';

void main() {
  List<int> utf8Bytes(String s) => utf8.encode(s);
  // GBK 已知对照：中=0xD6 0xD0，文=0xCE 0xC4（GBK 常用字区）
  const gbkZhongwen = <int>[0xd6, 0xd0, 0xce, 0xc4];

  test('UTF-8 无 BOM 正常解码', () {
    final r = decodeBillBytes(utf8Bytes('交易时间,金额(元)'));
    expect(r.encoding, 'utf-8');
    expect(r.text, '交易时间,金额(元)');
  });

  test('UTF-8 带 BOM 自动剥离', () {
    final withBom = <int>[0xef, 0xbb, 0xbf, ...utf8Bytes('微信支付账单明细')];
    final r = decodeBillBytes(withBom);
    expect(r.encoding, 'utf-8');
    expect(r.text.startsWith('\uFEFF'), isFalse);
    expect(r.text, '微信支付账单明细');
  });

  test('GBK 字节回退解码不乱码', () {
    final r = decodeBillBytes(gbkZhongwen);
    expect(r.encoding, 'gbk');
    expect(r.text, '中文');
  });

  test('混合内容：GBK 中文 + ASCII 数字/逗号', () {
    final bytes = <int>[0xd6, 0xd0, 0xce, 0xc4, ...utf8Bytes('12.30,ok')];
    final r = decodeBillBytes(bytes);
    expect(r.encoding, 'gbk');
    expect(r.text, '中文12.30,ok');
  });

  test('UTF-8 与 GBK 都失败 → 抛「无法识别的文件编码」', () {
    // 0x81 + 0x2C：UTF-8 非法；GBK trail 字节合法域是 0x40-0xFE，0x2C 非法
    expect(
      () => decodeBillBytes(<int>[0x81, 0x2c, 0x81, 0x2c]),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('无法识别的文件编码'),
      )),
    );
  });

  test('空字节返回空串（utf-8）', () {
    final r = decodeBillBytes(<int>[]);
    expect(r.text, '');
    expect(r.encoding, 'utf-8');
  });
}
