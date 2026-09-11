import 'package:flutter_test/flutter_test.dart';
import 'package:yanxin/core/utils/id.dart';

void main() {
  group('uuidV4', () {
    test('生成合法 v4 UUID', () {
      final id = uuidV4();
      expect(id.length, 36);
      expect(isUuid(id), isTrue);
    });
    test('两次生成不同', () {
      expect(uuidV4(), isNot(uuidV4()));
    });
    test('isUuid 校验', () {
      expect(isUuid('not-a-uuid'), isFalse);
      expect(isUuid('123e4567-e89b-12d3-a456-426614174000'), isFalse); // v1，非 v4
      expect(isUuid(null), isFalse);
    });
  });
}
