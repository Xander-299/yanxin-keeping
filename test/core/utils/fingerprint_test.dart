import 'package:flutter_test/flutter_test.dart';
import 'package:yanxin/core/utils/fingerprint.dart';

void main() {
  group('computeFingerprint', () {
    test('golden 向量：无 externalId（与旧栈 JS 逐字节一致）', () {
      // payload = 'alipay||12345|1700000000'
      expect(
        computeFingerprint(
          source: 'alipay',
          amountCents: 12345,
          occurredAt: 1700000000123,
        ),
        '8a54e5c68e6f1af48cb9453c5a03b5f5ad37c9ab',
      );
    });

    test('golden 向量：带 externalId', () {
      // payload = 'wechat|WX20240101|8880|1704067200'
      expect(
        computeFingerprint(
          source: 'wechat',
          externalId: 'WX20240101',
          amountCents: 8880,
          occurredAt: 1704067200000,
        ),
        '9dc8bb2ae4e190013615e91a8863a4f85bb295b3',
      );
    });

    test('同一秒内不同毫秒 → 同一指纹（秒级去重）', () {
      final a = computeFingerprint(
        source: 'alipay',
        amountCents: 12345,
        occurredAt: 1700000000000,
      );
      final b = computeFingerprint(
        source: 'alipay',
        amountCents: 12345,
        occurredAt: 1700000000999,
      );
      expect(a, b);
    });

    test('金额或跨秒变化 → 指纹不同', () {
      final base = computeFingerprint(
        source: 'alipay',
        amountCents: 12345,
        occurredAt: 1700000000000,
      );
      final otherAmount = computeFingerprint(
        source: 'alipay',
        amountCents: 12346,
        occurredAt: 1700000000000,
      );
      final otherSec = computeFingerprint(
        source: 'alipay',
        amountCents: 12345,
        occurredAt: 1700000001000,
      );
      expect(otherAmount, isNot(base));
      expect(otherSec, isNot(base));
    });

    test('externalId 缺失与空串等价', () {
      expect(
        computeFingerprint(source: 'alipay', amountCents: 1, occurredAt: 0),
        computeFingerprint(source: 'alipay', externalId: '', amountCents: 1, occurredAt: 0),
      );
    });
  });
}
