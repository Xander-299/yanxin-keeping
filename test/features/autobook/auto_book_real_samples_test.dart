/// 自动记账解析规则的**真机回归样本**（F7.15 真机排查 · 2026-10-08）。
///
/// 所有 `title` / `text` **逐字抄自真机通知**（Redmi K50 / Android 14 / HyperOS V816），
/// 抓取方式 = `tool/watch_notifications.py`（轮询 `dumpsys notification --noredact`）。
/// 原始落盘：`.workbuddy/qa-f715-real/watched.jsonl`。
///
/// 存在的意义：此前 `auto_book_rules_test.dart` 里的文案全是**推测**的（「你已成功支付 12.00元」），
/// 与真机实际文案不匹配 —— 真机付款后「抓得到、识别不了」正是这么来的：
/// 支付宝真实付款通知的标题就是「交易提醒」，正文里还带营销词「红包」，
/// 两条都撞上当时的**硬忽略**表 → 静默丢弃。
///
/// ⚠️ 新增/修改规则时，这里必须是**真机抓的原文**，不要手写想象的文案。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/autobook/data/auto_book_rules.dart';

const int _t = 1759930000000; // 2026-10-08 前后，仅用于指纹稳定性

RawNotification _wechat(String title, String text, {int at = _t}) =>
    RawNotification(
      pkg: 'com.tencent.mm',
      title: title,
      text: text,
      bigText: '',
      subText: '',
      postTimeMs: at,
    );

RawNotification _alipay(String title, String text, {int at = _t}) =>
    RawNotification(
      pkg: 'com.eg.android.AlipayGphone',
      title: title,
      text: text,
      bigText: '',
      subText: '',
      postTimeMs: at,
    );

void main() {
  group('真机样本 · 微信（可识别的）', () {
    test('① 子通知「已支付¥0.10」→ expense ¥0.10', () {
      final row = parseNotification(_wechat('微信支付', '已支付¥0.10'));
      expect(row, isNotNull);
      expect(row!.direction, 'expense');
      expect(row.amountCents, 10);
      expect(row.source, 'notify_wechat');
    });

    test('② 子通知「个人收款码到账¥0.01」→ income ¥0.01', () {
      final row = parseNotification(_wechat('微信支付', '个人收款码到账¥0.01'));
      expect(row, isNotNull);
      expect(row!.direction, 'income');
      expect(row.amountCents, 1);
    });

    test('③ 千分位金额「已支付¥1,234.50」→ 123450 分', () {
      final row = parseNotification(_wechat('微信支付', '已支付¥1,234.50'));
      expect(row, isNotNull);
      expect(row!.amountCents, 123450);
    });
  });

  group('真机样本 · 折叠前缀 `[N条]` 必须归一化后照常记账（2026-10-08 事故回归守卫）', () {
    // ⚠️ 旧实现把 `[N条]` 当「组摘要」直接丢弃 → 微信支付**静默漏记**（用户报「识别不到微信支付」）。
    // 真机取证（`dumpsys notification` 的 `Group summaries:` 段里**没有** com.tencent.mm、
    // `flags=0x11` 不含 `FLAG_GROUP_SUMMARY`、`groupKey == 自己的 key`、`tickerText` 无前缀）
    // 证明 `[N条]` 只是**显示层的折叠前缀**，整条通知就是那笔支付本身。
    // 真正需要丢弃的组摘要由 Kotlin 按 `FLAG_GROUP_SUMMARY` 权威判定，到不了这一层。
    test('事故原文「[3条]微信支付: 已支付¥0.03」→ expense ¥0.03（曾被误杀）', () {
      final row = parseNotification(_wechat('微信支付', '[3条]微信支付: 已支付¥0.03'));
      expect(row, isNotNull, reason: '这是 2026-10-08 漏记的那笔，不得再被 [N条] 规则丢弃');
      expect(row!.direction, 'expense');
      expect(row.amountCents, 3);
      expect(row.source, 'notify_wechat');
    });

    test('「[2条]微信支付: 已支付¥0.01」→ expense ¥0.01', () {
      final row = parseNotification(_wechat('微信支付', '[2条]微信支付: 已支付¥0.01'));
      expect(row, isNotNull);
      expect(row!.direction, 'expense');
      expect(row.amountCents, 1);
    });

    test('「[2条]微信支付: 个人收款码到账¥0.01」→ income ¥0.01（与上一条是两笔不同交易）', () {
      final row = parseNotification(_wechat('微信支付', '[2条]微信支付: 个人收款码到账¥0.01'));
      expect(row, isNotNull);
      expect(row!.direction, 'income', reason: '当年被当成「同笔的摘要」，其实是独立的一笔收款');
      expect(row.amountCents, 1);
    });

    test('「[10条]…」金额不受条数影响 → ¥9.90', () {
      final row = parseNotification(_wechat('微信支付', '[10条]微信支付: 已支付¥9.90'));
      expect(row, isNotNull);
      expect(row!.amountCents, 990, reason: '前缀里的 10 不得被当成金额');
    });

    test('折条数变化（[2条] → [3条]）不改变指纹 → 同一条通知不会重复入账', () {
      final a = _wechat('微信支付', '[2条]微信支付: 已支付¥0.01');
      final b = _wechat('微信支付', '[3条]微信支付: 已支付¥0.01');
      expect(a.externalId, b.externalId);
    });
  });

  group('真机样本 · 支付宝（本次「识别不了」的元凶）', () {
    test('④「交易提醒 / 你有一笔0.01元的支出，领2元小荷包支付红包。」→ expense ¥0.01', () {
      final row = parseNotification(
        _alipay('交易提醒', '你有一笔0.01元的支出，领2元小荷包支付红包。'),
      );
      expect(row, isNotNull, reason: '标题「交易提醒」+ 正文营销词「红包」不得再触发硬忽略');
      expect(row!.direction, 'expense');
      expect(row.amountCents, 1, reason: '取「支出」前那个金额，不要取营销语里的「2元」');
      expect(row.source, 'notify_alipay');
    });

    test('「交易提醒 / 你有一笔128.00元的支出」→ expense ¥128.00', () {
      final row = parseNotification(
        _alipay('交易提醒', '你有一笔128.00元的支出'),
      );
      expect(row, isNotNull);
      expect(row!.amountCents, 12800);
    });

    test('「交易提醒 / 你有一笔88.00元的收入」→ income ¥88.00', () {
      final row = parseNotification(
        _alipay('交易提醒', '你有一笔88.00元的收入'),
      );
      expect(row, isNotNull);
      expect(row!.direction, 'income');
      expect(row.amountCents, 8800);
    });

    test('⑤ 收款「你已成功收款0.01元（老顾客消费）」→ income ¥0.01', () {
      final row = parseNotification(
        _alipay(
          '你已成功收款0.01元（老顾客消费）',
          '已开通笔笔转入余额宝 经营码支持信用卡收钱>>',
        ),
      );
      expect(row, isNotNull);
      expect(row!.direction, 'income');
      expect(row.amountCents, 1);
    });
  });

  group('真机样本 · 非消费通知仍必须丢弃（不能为了认全而放宽）', () {
    test('⑥ 支付宝「新消息 / 你有一条新消息」→ 丢弃', () {
      expect(parseNotification(_alipay('新消息', '你有一条新消息')), isNull);
    });

    test('微信聊天消息「浩 / 过去了」→ 丢弃', () {
      expect(parseNotification(_wechat('浩', '过去了')), isNull);
    });

    test('转账仍然丢弃（硬忽略不可放宽）', () {
      expect(parseNotification(_wechat('微信支付', '已转账¥50.00')), isNull);
    });

    test('退款仍然丢弃', () {
      expect(
        parseNotification(_alipay('交易提醒', '你有一笔0.01元的退款')),
        isNull,
      );
    });

    test('纯营销（无任何支付/支出措辞）仍然丢弃', () {
      expect(
        parseNotification(_wechat('微信', '本周活动，最高立减 5 元，快来领取红包')),
        isNull,
      );
    });

    test('还款提醒（不是消费）仍然丢弃', () {
      expect(
        parseNotification(_alipay('还款提醒', '本期应还1,234.00元')),
        isNull,
      );
    });
  });
}
