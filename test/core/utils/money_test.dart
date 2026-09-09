import 'package:flutter_test/flutter_test.dart';
import 'package:yanxin/core/utils/money.dart';

void main() {
  group('yuanToCents', () {
    test('标准两位小数', () {
      expect(yuanToCents('12.34'), 1234);
    });
    test('带千分位', () {
      expect(yuanToCents('1,234.56'), 123456);
    });
    test('整数视为两位小数补零', () {
      expect(yuanToCents('12'), 1200);
      expect(yuanToCents('0'), 0);
    });
    test('0.1 + 0.2 以分计算恒为 30（无浮点误差）', () {
      final a = yuanToCents('0.1');
      final b = yuanToCents('0.2');
      expect(a, 10);
      expect(b, 20);
      expect(a + b, 30);
    });
    test('非法格式抛错', () {
      expect(() => yuanToCents(''), throwsA(isA<FormatException>()));
      expect(() => yuanToCents('abc'), throwsA(isA<FormatException>()));
      expect(() => yuanToCents('12.345'), throwsA(isA<FormatException>())); // 超过两位小数
      expect(() => yuanToCents('-5'), throwsA(isA<FormatException>())); // 负数不支持
      expect(() => yuanToCents('1.2.3'), throwsA(isA<FormatException>()));
    });
  });

  group('centsToYuan', () {
    test('整数分转元字符串', () {
      expect(centsToYuan(1234), '12.34');
      expect(centsToYuan(0), '0.00');
      expect(centsToYuan(30), '0.30');
    });
    test('千分位', () {
      expect(centsToYuan(123456789, group: true), '1,234,567.89');
    });
    test('负数保留负号', () {
      expect(centsToYuan(-30), '-0.30');
    });
  });

  group('sumCents', () {
    test('整数分相加', () {
      expect(sumCents([10, 20, 5]), 35);
      expect(sumCents([]), 0);
    });
  });

  group('absCents', () {
    test('取绝对值', () {
      expect(absCents(-1234), 1234);
      expect(absCents(1234), 1234);
    });
  });
}
