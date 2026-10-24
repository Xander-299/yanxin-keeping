/// 真实截图回归（F8.1）：样本来自用户 2026-10-24 提供的微信账单详情 OCR 文本
/// （`[OCR]_true picture_20261024_0428.txt`，8 张，已脱敏：只保留商户名与单号结构）。
///
/// ⚠️ 改 `receipt_rules.dart` 之前先跑这个文件 —— 这 8 条是**真实版式**，
/// 合成样本里没有这些特征：金额独占一行且带负号（`-3.00`）、时间写成
/// `2026年10月24日 01:41:04`、商品行混着收银员编号、二维码付款用的是「转账单号」。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/receipt/application/receipt_draft.dart';
import 'package:yanxin/features/receipt/data/receipt_parse.dart';

/// 每个样本 = 一张截图 OCR 出来的行（文件名标题行是 OCR 工具加的，不属于截图内容）。
const List<List<String>> kRealSamples = <List<String>>[
  // ① 便利店
  <String>[
    '福伴生活(西环店)',
    '-3.00',
    '当前状态 支付成功',
    '支付时间 2026年10月24日 01:41:04',
    '商品 福伴生活(西环店)收银员:005-501',
    '支付方式 零钱',
    '交易单号 4200003233202610249981391262',
  ],
  // ② 外卖
  <String>[
    '美团',
    '-10.90',
    '当前状态 支付成功',
    '支付时间 2026年10月23日 18:37:47',
    '商品 潮汕原味汤粉王·隆江猪脚饭-美团App-261023111003000001302357894704972',
    '支付方式 零钱',
    '交易单号 4500000561202610236268096099',
  ],
  // ③ 零食集合店
  <String>[
    '零食有鸣',
    '-6.50',
    '当前状态 支付成功',
    '支付时间 2026年10月23日 13:12:11',
    '商品 广东省深圳市龙岗区布吉东心岭店零售商品',
    '支付方式 零钱',
    '交易单号 4200003230202610238622958591',
  ],
  // ④ 地铁
  <String>[
    '深圳市地铁相关运营主体',
    '-5.00',
    '当前状态 支付成功',
    '支付时间 2026年10月23日 13:02:53',
    '商品 深圳地铁',
    '支付方式 零钱',
    '交易单号 42000003180202610233800316455',
  ],
  // ⑤ 扫二维码付款（收款方昵称 + 转账单号 + 转账时间）
  <String>[
    '静',
    '-12.00',
    '扫二维码付款-给沙县小吃',
    '当前状态 支付成功',
    '收款方备注 二维码收款',
    '支付方式 零钱',
    '转账时间 2026年10月23日 11:55:55',
    '转账单号 100001073012026102301199726582599',
  ],
  // ⑥ 同一家便利店，另一天
  <String>[
    '福伴生活(西环店)',
    '-3.00',
    '当前状态 支付成功',
    '支付时间 2026年10月23日 01:08:04',
    '商品 福伴生活(西环店)收银员:005-501',
    '支付方式 零钱',
    '交易单号 4200003232202610235066756693',
  ],
  // ⑦ 民宿（走美团 App 下单）
  <String>[
    '美团',
    '-45.96',
    '当前状态 支付成功',
    '支付时间 2026年10月22日 14:15:35',
    '商品 深圳范哲青年民宿（长龙地铁站店）-美团App-261022111003000001302160104552972',
    '支付方式 零钱',
    '交易单号 4500000575202610225159521218',
  ],
  // ⑧ 零食集合店，另一天
  <String>[
    '零食有鸣',
    '-8.90',
    '当前状态 支付成功',
    '支付时间 2026年10月22日 14:05:17',
    '商品 广东省深圳市龙岗区布吉东心岭店零售商品',
    '支付方式 零钱',
    '交易单号 4200003150202610223147246797',
  ],
];

/// ⑨ **微信「交易详情」版式**——直接取自真机 ML Kit 的原始输出（含 OCR 错字），
/// 2026-10-24 20:03 的截图，用于钉住两个真实坑：
///   1. `商户` 标签会命中 `商户单号`（商户名变成「单号」）；
///   2. `交易单号` 与号码被 OCR 拆成**两行**。
const List<String> kTradeDetailOcrLines = <String>[
  '8:03',
  '146',
  '记账',
  '63',
  '美麵美团',
  '服务',
  '交易详信',
  '-22.98',
  '美团',
  '当前状态',
  '支付成功',
  '支付时间',
  '2026年10月24日 16:28:57',
  '商品',
  '深圳范哲青年民宿(长龙地铁站店)-美团',
  'App-26102411100300001302514666777972',
  '收单机构',
  '北京钱袋宝支付技术有限公司',
  '支付方式',
  '零钱',
  '交易单号',
  '4500000572202610243956424515',
  '商户单号',
  '20261024162843U05427452068903548',
  '交易服务',
  '@对订单有疑惑',
  '同发起群收款',
  '目在此商戶的交易',
  '目申请电子凭证',
  '本服务由财付通提供',
];

ReceiptDraft parseSample(List<String> lines) => parseReceipt(
  lines,
  nowMs: DateTime(2026, 10, 24, 4, 30).millisecondsSinceEpoch,
);

DateTime timeOf(ReceiptDraft d) =>
    DateTime.fromMillisecondsSinceEpoch(d.occurredAtMs.value!);

void main() {
  group('8 张真实微信账单：通用字段', () {
    test('全部识别为微信支付 + 支付成功 + 支出', () {
      for (final List<String> sample in kRealSamples) {
        final ReceiptDraft d = parseSample(sample);
        expect(d.platform, ReceiptPlatform.wechat, reason: sample.first);
        expect(d.status, ReceiptStatus.ok, reason: sample.first);
        expect(d.direction.value, 'expense', reason: sample.first);
        // 金额独占一行 + 带符号 → 高可信
        expect(d.amountCents.confidence, FieldConfidence.high,
            reason: sample.first);
        expect(d.paymentType, 'wechat', reason: sample.first);
        expect(d.issues.contains(ReceiptIssue.missingAmount), isFalse,
            reason: sample.first);
        expect(d.canWrite, isTrue, reason: sample.first);
      }
    });

    test('金额与时间逐条对上（含 `2026年10月24日` 这种中文日期）', () {
      final List<int> amounts = <int>[
        300,
        1090,
        650,
        500,
        1200,
        300,
        4596,
        890,
      ];
      final List<DateTime> times = <DateTime>[
        DateTime(2026, 10, 24, 1, 41, 4),
        DateTime(2026, 10, 23, 18, 37, 47),
        DateTime(2026, 10, 23, 13, 12, 11),
        DateTime(2026, 10, 23, 13, 2, 53),
        DateTime(2026, 10, 23, 11, 55, 55),
        DateTime(2026, 10, 23, 1, 8, 4),
        DateTime(2026, 10, 22, 14, 15, 35),
        DateTime(2026, 10, 22, 14, 5, 17),
      ];
      for (var i = 0; i < kRealSamples.length; i++) {
        final ReceiptDraft d = parseSample(kRealSamples[i]);
        expect(d.amountCents.value, amounts[i], reason: '第 ${i + 1} 张金额');
        expect(timeOf(d), times[i], reason: '第 ${i + 1} 张时间');
      }
    });

    test('商户取"金额上一行"，不被"商品"行里的收银员编号带偏', () {
      expect(parseSample(kRealSamples[0]).merchant.value, '福伴生活(西环店)');
      expect(parseSample(kRealSamples[1]).merchant.value, '美团');
      expect(parseSample(kRealSamples[2]).merchant.value, '零食有鸣');
      expect(parseSample(kRealSamples[3]).merchant.value, '深圳市地铁相关运营主体');
      // 二维码付款：收款方是昵称（一个字也算合法商户名）
      expect(parseSample(kRealSamples[4]).merchant.value, '静');
      expect(parseSample(kRealSamples[0]).merchant.tag, '金额上一行');
    });

    test('交易单号 / 转账单号都能抓到（后者是二维码付款才有的）', () {
      expect(
        parseSample(kRealSamples[0]).orderNo,
        '4200003233202610249981391262',
      );
      expect(
        parseSample(kRealSamples[4]).orderNo,
        '100001073012026102301199726582599',
      );
    });
  });

  group('分类规则命中（真实商户名）', () {
    test('美团 → 餐饮', () {
      expect(parseSample(kRealSamples[1]).categoryName.value, '餐饮');
    });

    test('零食有鸣 → 购物（本轮新增的零食/生鲜规则）', () {
      expect(parseSample(kRealSamples[2]).categoryName.value, '购物');
    });

    test('深圳地铁 → 交通', () {
      expect(parseSample(kRealSamples[3]).categoryName.value, '交通');
    });

    test('没命中规则的商户落「其他」并标低可信（等用户改）', () {
      final ReceiptDraft d = parseSample(kRealSamples[0]);
      expect(d.categoryName.value, '其他');
      expect(d.categoryName.confidence, FieldConfidence.low);
    });
  });

  group('去重：同一张截图重复确认不会记两笔', () {
    test('同一段的文本指纹稳定', () {
      final String a = parseSample(kRealSamples[0]).textHash;
      final String b = parseSample(<String>[...kRealSamples[0], '']).textHash;
      expect(a, b);
    });

    test('不同截图指纹不同（同一商户同金额也不行）', () {
      final String a = parseSample(kRealSamples[0]).textHash;
      final String b = parseSample(kRealSamples[5]).textHash;
      expect(a, isNot(b));
      // 两张都是福伴生活 ¥3.00，靠时间与单号区分
      expect(
        parseSample(kRealSamples[0]).amountCents.value,
        parseSample(kRealSamples[5]).amountCents.value,
      );
    });
  });

  group('⑨ 微信「交易详情」版式（真机 ML Kit 原始输出）', () {
    test('金额 / 时间 / 方向 / 状态', () {
      final ReceiptDraft d = parseSample(kTradeDetailOcrLines);
      expect(d.platform, ReceiptPlatform.wechat);
      expect(d.status, ReceiptStatus.ok);
      expect(d.direction.value, 'expense');
      expect(d.amountCents.value, 2298);
      expect(d.amountCents.confidence, FieldConfidence.high);
      expect(
        DateTime.fromMillisecondsSinceEpoch(d.occurredAtMs.value!),
        DateTime(2026, 10, 24, 16, 28, 57),
      );
      expect(d.paymentType, 'wechat');
    });

    test('商户取"金额下一行"，不会被「商户单号」的「商户」骗走', () {
      final ReceiptDraft d = parseSample(kTradeDetailOcrLines);
      expect(d.merchant.value, '美团');
      expect(d.merchant.tag, '金额下一行');
      expect(d.categoryName.value, '餐饮');
    });

    test('交易单号与标签分两行时也能抓到', () {
      expect(parseSample(kTradeDetailOcrLines).orderNo,
          '4500000572202610243956424515');
    });

    test('可以直接记账（无阻断项）', () {
      final ReceiptDraft d = parseSample(kTradeDetailOcrLines);
      expect(d.canWrite, isTrue);
      expect(d.blockers, isEmpty);
    });
  });
}
