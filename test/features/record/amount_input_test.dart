import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/record/application/amount_input.dart';

void main() {
  group('applyAmountKey', () {
    test('前导 0 被替换', () {
      expect(applyAmountKey('', '0'), '0');
      expect(applyAmountKey('0', '5'), '5');
      expect(applyAmountKey('0', '0'), '0');
    });

    test('小数点只出现一次，空输入补 0', () {
      expect(applyAmountKey('', '.'), '0.');
      expect(applyAmountKey('12', '.'), '12.');
      expect(applyAmountKey('12.', '.'), '12.');
    });

    test('小数最多两位', () {
      expect(applyAmountKey('1.2', '3'), '1.23');
      expect(applyAmountKey('1.23', '4'), '1.23');
    });

    test('整数位最多 9 位', () {
      expect(applyAmountKey('12345678', '9'), '123456789');
      expect(applyAmountKey('123456789', '0'), '123456789');
    });

    test('退格', () {
      expect(applyAmountKey('12.3', amountKeyDelete), '12.');
      expect(applyAmountKey('', amountKeyDelete), '');
    });

    test('非法键原样返回', () {
      expect(applyAmountKey('12', 'a'), '12');
      expect(applyAmountKey('12', '..'), '12');
    });
  });

  group('isParsableAmount', () {
    test('合法 / 非法', () {
      expect(isParsableAmount('12'), isTrue);
      expect(isParsableAmount('12.3'), isTrue);
      expect(isParsableAmount('12.34'), isTrue);
      expect(isParsableAmount(''), isFalse);
      expect(isParsableAmount('12.'), isFalse);
      expect(isParsableAmount('.5'), isFalse);
      expect(isParsableAmount('12.345'), isFalse);
    });
  });
}
