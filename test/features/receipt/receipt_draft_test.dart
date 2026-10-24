/// 草稿模型测试（F8.1）：可信度口径、阻断规则、候选去重。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/receipt/application/receipt_draft.dart';

ReceiptDraft draftWith({
  ReceiptField<int> amount = const ReceiptField<int>.absent(),
  ReceiptField<String> direction = const ReceiptField<String>.absent(),
  List<ReceiptIssue> issues = const <ReceiptIssue>[],
}) {
  return ReceiptDraft(
    platform: ReceiptPlatform.wechat,
    status: ReceiptStatus.ok,
    direction: direction,
    amountCents: amount,
    occurredAtMs: const ReceiptField<int>.absent(),
    merchant: const ReceiptField<String>.absent(),
    categoryName: const ReceiptField<String>.absent(),
    issues: issues,
    textHash: 'h',
    rawText: 'x',
  );
}

void main() {
  group('可信度', () {
    test('low / absent 需要用户确认，high / medium 不需要', () {
      expect(FieldConfidence.high.needsConfirm, isFalse);
      expect(FieldConfidence.medium.needsConfirm, isFalse);
      expect(FieldConfidence.low.needsConfirm, isTrue);
      expect(FieldConfidence.absent.needsConfirm, isTrue);
    });

    test('absent 构造器一身空', () {
      const ReceiptField<int> f = ReceiptField<int>.absent();
      expect(f.value, isNull);
      expect(f.isEmpty, isTrue);
      expect(f.candidates, isEmpty);
      expect(f.confidence, FieldConfidence.absent);
    });
  });

  group('阻断规则', () {
    test('只有没金额 / 支付失败 / 已取消 / 空文本算阻断', () {
      const Set<ReceiptIssue> blocking = <ReceiptIssue>{
        ReceiptIssue.missingAmount,
        ReceiptIssue.paymentFailed,
        ReceiptIssue.paymentCancelled,
        ReceiptIssue.emptyText,
      };
      for (final ReceiptIssue issue in ReceiptIssue.values) {
        expect(issue.blocking, blocking.contains(issue), reason: issue.name);
      }
    });

    test('有阻断项时 canWrite=false', () {
      final ReceiptDraft d = draftWith(
        amount: const ReceiptField<int>(
          value: 1200,
          confidence: FieldConfidence.high,
        ),
        issues: <ReceiptIssue>[ReceiptIssue.paymentFailed],
      );
      expect(d.canWrite, isFalse);
      expect(d.blockers, <ReceiptIssue>[ReceiptIssue.paymentFailed]);
      expect(d.warnings, isEmpty);
    });

    test('只有提醒项时仍可写入', () {
      final ReceiptDraft d = draftWith(
        amount: const ReceiptField<int>(
          value: 1200,
          confidence: FieldConfidence.low,
        ),
        issues: <ReceiptIssue>[
          ReceiptIssue.multipleAmounts,
          ReceiptIssue.missingMerchant,
        ],
      );
      expect(d.canWrite, isTrue);
      expect(d.blockers, isEmpty);
      expect(d.warnings.length, 2);
    });

    test('金额为 0 也写不了（不会产生 0 元账单）', () {
      final ReceiptDraft d = draftWith(
        amount: const ReceiptField<int>(value: 0),
      );
      expect(d.canWrite, isFalse);
    });
  });

  group('金额候选', () {
    test('当前值在最前，候选去重且丢掉非正数', () {
      final ReceiptDraft d = draftWith(
        amount: const ReceiptField<int>(
          value: 1200,
          confidence: FieldConfidence.low,
          candidates: <int>[1300, 1200, 0, -100, 1300],
        ),
      );
      expect(d.amountChoices, <int>[1200, 1300]);
    });

    test('没有主金额时只用候选', () {
      final ReceiptDraft d = draftWith(
        amount: const ReceiptField<int>(candidates: <int>[500, 900]),
      );
      expect(d.amountChoices, <int>[500, 900]);
    });
  });

  group('问题文案', () {
    test('每条问题都有面向用户的说明（不留空话）', () {
      for (final ReceiptIssue issue in ReceiptIssue.values) {
        expect(issue.message.trim(), isNotEmpty, reason: issue.name);
        expect(issue.message.length, greaterThan(4), reason: issue.name);
      }
    });
  });
}
