/// 截图 OCR 文本 → 草稿的规则测试（F8.1）。
///
/// 样本都是**脱敏后的真实句式**（微信支付 / 支付宝交易提醒 / 银行短信 / 电商订单），
/// 改规则前先看这里的期望值 —— 每条断言都在说明"为什么这么判"。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/receipt/application/receipt_draft.dart';
import 'package:yanxin/features/receipt/data/receipt_parse.dart';

/// 固定"现在"，让"年份推断"这类规则可复现。
int nowMs([int year = 2026, int month = 10, int day = 24]) =>
    DateTime(year, month, day, 3, 0).millisecondsSinceEpoch;

ReceiptDraft parse(List<String> lines, {int? now}) =>
    parseReceipt(lines, nowMs: now ?? nowMs());

void main() {
  group('微信支付凭证', () {
    final List<String> lines = <String>[
      '微信支付',
      '支付成功',
      '商户全称：星巴克咖啡',
      '商品说明：大杯拿铁',
      '支付金额 ¥36.00',
      '支付方式 零钱',
      '支付时间 2026-10-23 14:05:33',
      '交易单号 4200001234202610231234567890',
    ];

    test('平台 / 状态 / 方向', () {
      final ReceiptDraft d = parse(lines);
      expect(d.platform, ReceiptPlatform.wechat);
      expect(d.status, ReceiptStatus.ok);
      expect(d.direction.value, 'expense');
      expect(d.direction.confidence, FieldConfidence.high);
    });

    test('金额取"支付金额"、高可信、无候选', () {
      final ReceiptDraft d = parse(lines);
      expect(d.amountCents.value, 3600);
      expect(d.amountCents.confidence, FieldConfidence.high);
      expect(d.amountCents.tag, '实付');
      expect(d.amountCents.candidates, isEmpty);
      expect(d.amountChoices, <int>[3600]);
    });

    test('时间取到秒、无需推断', () {
      final ReceiptDraft d = parse(lines);
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(
        d.occurredAtMs.value!,
      );
      expect(t, DateTime(2026, 10, 23, 14, 5, 33));
      expect(d.issues.contains(ReceiptIssue.yearInferred), isFalse);
    });

    test('商户取标签值、分类规则命中餐饮、订单号可去重', () {
      final ReceiptDraft d = parse(lines);
      expect(d.merchant.value, '星巴克咖啡');
      expect(d.merchant.confidence, FieldConfidence.high);
      // 「星巴克」命中 category_rules 的餐饮规则
      expect(d.categoryName.value, '餐饮');
      expect(d.categoryName.tag, '关键词');
      expect(d.orderNo, '4200001234202610231234567890');
      expect(d.paymentType, 'wechat');
    });

    test('字段齐全时没有遗留问题', () {
      final ReceiptDraft d = parse(lines);
      expect(d.issues, isEmpty);
      expect(d.canWrite, isTrue);
    });
  });

  group('支付宝交易提醒（金额在动作词前 + 营销尾巴）', () {
    final List<String> lines = <String>[
      '支付宝',
      '交易提醒',
      '你有一笔12.00元的支出，领2元小荷包支付红包。',
      '2026-10-23 12:00',
    ];

    test('取"12.00元的支出"，不把营销里的 2 元当主金额', () {
      final ReceiptDraft d = parse(lines);
      expect(d.platform, ReceiptPlatform.alipay);
      expect(d.amountCents.value, 1200);
      expect(d.amountCents.candidates, isEmpty);
      expect(d.amountCents.confidence, FieldConfidence.high);
    });

    test('方向=支出；商户缺失时给提醒但不阻断', () {
      final ReceiptDraft d = parse(lines);
      expect(d.direction.value, 'expense');
      expect(d.merchant.isEmpty, isTrue);
      expect(d.issues.contains(ReceiptIssue.missingMerchant), isTrue);
      expect(d.canWrite, isTrue);
    });
  });

  group('银行短信（缺年份）', () {
    final List<String> lines = <String>[
      '【招商银行】您尾号8888的储蓄卡于10月23日14:05消费12.00元，余额1,234.56元。',
    ];

    test('平台=银行卡，金额=12.00（不取余额）', () {
      final ReceiptDraft d = parse(lines);
      expect(d.platform, ReceiptPlatform.bank);
      expect(d.amountCents.value, 1200);
      // 只命中「N 元」这一档 → 中等可信
      expect(d.amountCents.confidence, FieldConfidence.medium);
    });

    test('年份按"不晚于今天"推断，并给出提示', () {
      final ReceiptDraft d = parse(lines);
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(
        d.occurredAtMs.value!,
      );
      expect(t, DateTime(2026, 10, 23, 14, 5));
      expect(d.issues.contains(ReceiptIssue.yearInferred), isTrue);
    });
  });

  group('退款', () {
    final List<String> lines = <String>[
      '微信支付',
      '退款成功',
      '退款金额 ¥12.00',
      '商户全称：美团',
      '2026-10-23 09:12',
    ];

    test('状态=退款，方向建议记收入', () {
      final ReceiptDraft d = parse(lines);
      expect(d.status, ReceiptStatus.refund);
      expect(d.direction.value, 'income');
      expect(d.direction.confidence, FieldConfidence.medium);
      expect(d.amountCents.value, 1200);
      expect(d.issues.contains(ReceiptIssue.refund), isTrue);
    });
  });

  group('支付失败 / 已取消', () {
    test('支付失败 → 阻断保存', () {
      final ReceiptDraft d = parse(<String>[
        '微信支付',
        '支付失败',
        '商户全称：某某商店',
        '金额 ¥5.00',
        '2026-10-23 10:00',
      ]);
      expect(d.status, ReceiptStatus.failed);
      expect(d.issues.contains(ReceiptIssue.paymentFailed), isTrue);
      expect(d.canWrite, isFalse);
    });

    test('交易已取消 → 阻断保存（与"失败"分开报原因）', () {
      final ReceiptDraft d = parse(<String>[
        '支付宝',
        '交易关闭',
        '订单金额 ¥88.00',
      ]);
      expect(d.status, ReceiptStatus.cancelled);
      expect(d.issues.contains(ReceiptIssue.paymentCancelled), isTrue);
      expect(d.canWrite, isFalse);
    });
  });

  group('原价 / 优惠 / 实付 三个金额', () {
    final List<String> lines = <String>[
      '支付宝',
      '支付成功',
      '订单金额 ¥13.00',
      '优惠 ¥1.00',
      '实付 ¥12.00',
    ];

    test('主金额取实付，原价留作候选，标记待确认', () {
      final ReceiptDraft d = parse(lines);
      expect(d.amountCents.value, 1200);
      expect(d.amountCents.candidates, <int>[1300]);
      expect(d.amountCents.confidence, FieldConfidence.low);
      expect(d.issues.contains(ReceiptIssue.multipleAmounts), isTrue);
      expect(d.canWrite, isTrue);
    });
  });

  group('购物订单', () {
    final List<String> lines = <String>[
      '订单详情',
      '订单号 2026102312345678',
      '店铺名称：某某旗舰店',
      '商品：蓝牙耳机',
      '合计 ¥199.00',
      '待发货',
    ];

    test('平台=订单，方向按支出、取"合计"', () {
      final ReceiptDraft d = parse(lines);
      expect(d.platform, ReceiptPlatform.order);
      expect(d.status, ReceiptStatus.ok);
      expect(d.direction.value, 'expense');
      expect(d.amountCents.value, 19900);
      expect(d.merchant.value, '某某旗舰店');
      expect(d.categoryName.value, '购物');
      expect(d.orderNo, '2026102312345678');
    });

    test('没有时间 → 提醒补填（不阻断）', () {
      final ReceiptDraft d = parse(lines);
      expect(d.occurredAtMs.isEmpty, isTrue);
      expect(d.issues.contains(ReceiptIssue.missingTime), isTrue);
      expect(d.canWrite, isTrue);
    });
  });

  group('多金额 / 糊图 / 空文本', () {
    test('两个等宽金额 → 全部作为候选、待确认', () {
      final ReceiptDraft d = parse(<String>['¥9.90', '¥19.90']);
      expect(d.amountCents.value, 990);
      expect(d.amountCents.candidates, <int>[1990]);
      expect(d.amountCents.confidence, FieldConfidence.low);
    });

    test('没有任何可读字符 → 阻断（提示换一张）', () {
      final ReceiptDraft d = parse(<String>['~ ~', '—— ——']);
      expect(d.issues.contains(ReceiptIssue.emptyText), isTrue);
      expect(d.canWrite, isFalse);
    });

    test('空行列表 → 空草稿', () {
      final ReceiptDraft d = parse(const <String>[]);
      expect(d.rawText, '');
      expect(d.issues, <ReceiptIssue>[ReceiptIssue.emptyText]);
      expect(d.canWrite, isFalse);
    });

    test('没识别到金额 → 阻断，且不编造 0 元', () {
      final ReceiptDraft d = parse(<String>['微信支付', '支付成功', '商户全称：某店']);
      expect(d.amountCents.value, isNull);
      expect(d.issues.contains(ReceiptIssue.missingAmount), isTrue);
      expect(d.canWrite, isFalse);
    });
  });

  group('时间推断边界', () {
    test('12-31 在次年 1 月看 → 归到上一年', () {
      final ReceiptDraft d = parse(
        <String>['微信支付', '支付成功', '12-31 23:10', '¥8.80'],
        now: nowMs(2026, 1, 5),
      );
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(
        d.occurredAtMs.value!,
      );
      expect(t, DateTime(2025, 12, 31, 23, 10));
      expect(d.issues.contains(ReceiptIssue.yearInferred), isTrue);
    });

    test('同一年内的月日不再回退一年', () {
      final ReceiptDraft d = parse(
        <String>['微信支付', '支付成功', '10-20 09:30', '¥8.80'],
        now: nowMs(2026, 10, 24),
      );
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(
        d.occurredAtMs.value!,
      );
      expect(t.year, 2026);
    });

    test('不存在的日期（2 月 30 日）不采信', () {
      final ReceiptDraft d = parse(<String>['微信支付', '2026-02-30 10:00', '¥8.80']);
      expect(d.occurredAtMs.isEmpty, isTrue);
      expect(d.issues.contains(ReceiptIssue.missingTime), isTrue);
    });
  });

  group('文本归一化 / 指纹', () {
    test('全角空格与连续空白被压缩、空行被丢弃', () {
      expect(
        normalizeReceiptLines(<String>['  微信支付 ', '\u3000', 'a   b']),
        <String>['微信支付', 'a b'],
      );
    });

    test('同一张图两次识别 → 文本指纹一致（去重的前提）', () {
      final ReceiptDraft a = parse(<String>['微信支付', ' ¥8.80 ']);
      final ReceiptDraft b = parse(<String>['微信支付  ', '¥8.80']);
      expect(a.textHash, b.textHash);
      expect(a.textHash.length, 40);
    });
  });
}
