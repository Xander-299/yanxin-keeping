/// 移植自旧栈 tests/bill-import/real-bills.test.js — 真实账单回归。
///
/// 覆盖两种「与旧样例不同」的真实格式：
/// - 微信 2025+ xlsx：时间列是 Excel 序列号、金额纯数字、状态含 已退款/已全额退款/已转账
/// - 支付宝「电子客户回单」CSV：GBK 编码、表头在元信息块后、订单号带尾部制表符
///
/// 真实账单含个人信息，只留在本机（.gitignore 排除 test/fixtures/*-real.*），
/// 文件不存在时整组跳过（与旧栈 skipIf 语义一致）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/import/data/bill_normalize.dart';
import 'package:yanxin/features/import/data/bill_parse.dart';

bool _hasWechat = false;
bool _hasAlipay = false;
BillParseResult? _wechatParsed;
BillParseResult? _alipayParsed;

void main() {
  // 真实件存在才解析（解析放组外会在 skip 时报错）
  final wechatFile = File('test/fixtures/wechat-sample-real.xlsx');
  final alipayFile = File('test/fixtures/alipay-sample-real.csv');
  _hasWechat = wechatFile.existsSync();
  _hasAlipay = alipayFile.existsSync();
  if (_hasWechat) {
    _wechatParsed = parseBillFileAuto(wechatFile.readAsBytesSync());
  }
  if (_hasAlipay) {
    _alipayParsed = parseBillFileAuto(alipayFile.readAsBytesSync());
  }

  group('Excel 序列号时间（parseTimeMs）', () {
    test('序列号按本地时区墙上时间换算', () {
      // 25569 = 1970-01-01（1900 日期系统），+0.5 天 = 12:00:00
      expect(parseTimeMs('25569.5'),
          DateTime(1970, 1, 1, 12).millisecondsSinceEpoch);
      expect(
        parseTimeMs('46126.51789351852'),
        DateTime(2026, 4, 14, 12, 25, 46).millisecondsSinceEpoch,
      );
    });

    test('31 位交易单号等长数字串不会被误判为时间', () {
      expect(parseTimeMs('4200003114202604146200908418'), isNull);
      expect(parseTimeMs('2026041411342001699'), isNull);
      expect(parseTimeMs(''), isNull);
    });
  });

  group('微信真实账单（xlsx，2025+ 导出格式）', () {
    test('识别为微信账单，统计与文件头「共335笔」一致', () {
      final parsed = _wechatParsed!;
      expect(parsed.source, 'wechat_csv');
      expect(parsed.stats.dataRows, 335); // 文件头声明 335 笔（12 收 + 323 支）
      expect(parsed.stats.imported, 327); // 8 条退款按 Q3 跳过
      expect(parsed.stats.skipped, 8);
      expect(parsed.stats.skipReasons['blacklisted'], 8);
      expect(parsed.stats.malformed, 0);
      expect(parsed.stats.unknownStatus, 0); // 已转账 已加入白名单
    }, skip: _hasWechat ? false : '缺少真实件 wechat-sample-real.xlsx');

    test('Excel 序列号时间列换算为正确的本地毫秒', () {
      final parsed = _wechatParsed!;
      // 序列号 46126.51789351852 = 2026-04-14 12:25:46（墙上时间）
      final row = parsed.rows.firstWhere(
        (r) => r.externalId == '4200003114202604146200908418',
      );
      expect(row.occurredAt,
          DateTime(2026, 4, 14, 12, 25, 46).millisecondsSinceEpoch);
      expect(row.amountCents, 1300); // 13 元（纯数字金额）
      expect(row.direction, 'expense');
      expect(row.counterparty, '汕头大学合作食堂');
    }, skip: _hasWechat ? false : '缺少真实件');

    test('交易单号 31 位数字不丢精度（不经过 float）', () {
      final ids = _wechatParsed!.rows.map((r) => r.externalId).toList();
      expect(ids, contains('4200003114202604146200908418'));
      expect(ids, contains('53010003254228202607162391541809'));
    }, skip: _hasWechat ? false : '缺少真实件');

    test('所有入账行金额为正整数分、时间合法', () {
      final minTime =
          DateTime(2020, 1, 1).millisecondsSinceEpoch;
      for (final r in _wechatParsed!.rows) {
        expect(r.amountCents, greaterThan(0));
        expect(r.occurredAt, greaterThan(minTime));
      }
    }, skip: _hasWechat ? false : '缺少真实件');
  });

  group('支付宝真实账单（电子客户回单 CSV，GBK）', () {
    test('识别为支付宝账单，统计与文件头「共32笔」一致', () {
      final parsed = _alipayParsed!;
      expect(parsed.source, 'alipay_csv');
      expect(parsed.stats.dataRows, 32);
      expect(parsed.stats.imported, 28); // 3 条不计收支 + 1 条退款成功 跳过
      expect(parsed.stats.skipReasons['neutral'], 3);
      expect(parsed.stats.skipReasons['blacklisted'], 1);
      expect(parsed.stats.malformed, 0);
      expect(parsed.stats.unknownStatus, 0); // 等待确认收货 已加入白名单
    }, skip: _hasAlipay ? false : '缺少真实件 alipay-sample-real.csv');

    test('GBK 解码中文不乱码，订单号尾部制表符被 trim', () {
      final row = _alipayParsed!.rows.first;
      expect(row.externalId, '2026071622001446161451749699');
      expect(row.product, '校园一卡通尾号(1682)充值');
      expect(row.counterparty, 'stu***@stu.edu.cn');
      expect(row.method, '中国银行储蓄卡(0217)');
      expect(row.amountCents, 2100);
      expect(row.direction, 'expense');
    }, skip: _hasAlipay ? false : '缺少真实件');
  });
}
