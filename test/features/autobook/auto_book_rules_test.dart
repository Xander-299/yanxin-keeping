/// 自动记账解析规则单测（F7.15 SPEC §3.4 / §3.5）—— 纯函数，零 IO。
///
/// 覆盖：包名白名单 / 忽略规则（逐词）/ 金额多级降级 / 方向判定 / 商户提取 /
/// 分享文本路径 / 坏输入不抛异常 / externalId 稳定性。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/autobook/data/auto_book_rules.dart';

const int _t = 1759200000000; // 2025-09-30 12:00:00 本地时区附近

RawNotification _wechat(
  String text, {
  String title = '微信支付',
  String bigText = '',
  String subText = '',
  int at = _t,
}) => RawNotification(
  pkg: 'com.tencent.mm',
  title: title,
  text: text,
  bigText: bigText,
  subText: subText,
  postTimeMs: at,
);

RawNotification _alipay(String text, {int at = _t}) => RawNotification(
  pkg: 'com.eg.android.AlipayGphone',
  title: '支付宝',
  text: text,
  bigText: '',
  subText: '',
  postTimeMs: at,
);

void main() {
  group('① 包名白名单', () {
    test('未支持的包名 → 丢弃（哪怕文案一模一样）', () {
      const RawNotification qq = RawNotification(
        pkg: 'com.tencent.mobileqq',
        title: 'QQ',
        text: '已支付 12.00元',
        bigText: '',
        subText: '',
        postTimeMs: _t,
      );
      expect(parseNotification(qq), isNull);
    });

    test('微信 / 支付宝 → 各自的 source 取值', () {
      expect(parseNotification(_wechat('你已成功支付 12.00元'))!.source,
          'notify_wechat');
      expect(parseNotification(_alipay('付款成功 12.00元'))!.source,
          'notify_alipay');
    });
  });

  group('② 忽略规则（逐词验证，忽略优先于模板）', () {
    for (final String keyword in kAutoBookIgnoreKeywords) {
      test('硬忽略「$keyword」→ 丢弃（即使同时含「支付成功」和金额）', () {
        expect(parseNotification(_wechat('支付成功 12.00元 $keyword')), isNull);
      });
    }

    // 软忽略词**不得**独自否决一条真实回执（2026-10-08 真机排查）：
    // 支付宝付款通知的标题就是「交易提醒」，正文还带营销尾巴「…红包。」——
    // 它们原先在硬忽略表里 → 支付宝付款一笔都记不上，且全程静默。
    for (final String keyword in kAutoBookSoftIgnoreKeywords) {
      test('软忽略「$keyword」+ 强收支词 → 保留（不得静默漏记）', () {
        final row = parseNotification(_wechat('支付成功 12.00元 $keyword'));
        expect(row, isNotNull);
        expect(row!.amountCents, 1200);
      });
    }
  });

  group('②b 软忽略：营销词不误杀真实回执（2026-10-07 走查修复）', () {
    test('「你已付款成功，优惠 0.50元」→ 保留（原实现硬忽略会静默丢弃）', () {
      final row = parseNotification(_wechat('你已付款成功，优惠 0.50元'));
      expect(row, isNotNull);
      expect(row!.direction, 'expense');
    });

    test('「支付成功，立减 2 元」→ 保留', () {
      expect(parseNotification(_wechat('支付成功，立减 2 元')), isNotNull);
    });

    test('「满减」同理不误杀', () {
      expect(parseNotification(_wechat('付款成功，满减 3 元')), isNotNull);
    });

    test('纯营销（无支付回执词）仍丢弃：标题写「微信」避开标题里的「支付」二字', () {
      expect(
        parseNotification(_wechat('本周活动，最高立减 5 元', title: '微信')),
        isNull,
      );
    });

    test('硬忽略词不受软忽略改动影响（「即将」仍一票否决）', () {
      expect(
        parseNotification(_wechat('你有一张优惠券即将到期', title: '微信')),
        isNull,
      );
    });
  });

  group('②c 金额优先级：实付 > 优惠（同一条通知里有多个金额时）', () {
    test('「订单金额 13.00元，优惠 1.00元，实付 12.00元」→ 取实付 12.00', () {
      final row = parseNotification(
        _wechat('订单金额 13.00元，优惠 1.00元，实付 12.00元'),
      );
      expect(row, isNotNull);
      expect(row!.amountCents, 1200);
    });

    test('「付款成功，优惠 0.50元，实付 12.00元」→ 取实付，不取优惠', () {
      expect(
        parseNotification(_wechat('付款成功，优惠 0.50元，实付 12.00元'))!
            .amountCents,
        1200,
      );
    });

    test('只有优惠金额、没有实付时退化取它（总比不记好，用户可改）', () {
      expect(
        parseNotification(_wechat('付款成功，优惠 0.50元'))!.amountCents,
        50,
      );
    });
  });

  group('③ 金额 + 方向 + 商户', () {
    test('「¥12.30」无「元」字也能提', () {
      final row = parseNotification(_wechat('你已成功支付 ¥12.30'))!;
      expect(row.amountCents, 1230);
      expect(row.direction, 'expense');
    });

    test('「12.3元」一位小数按 12.30 处理（字符串转分，不碰浮点）', () {
      expect(parseNotification(_wechat('付款成功 12.3元'))!.amountCents, 1230);
    });

    test('千分位不截断（1,234.00元 → 123400 分）', () {
      expect(
        parseNotification(_wechat('你已成功支付 1,234.00元'))!.amountCents,
        123400,
      );
    });

    test('无金额 → 丢弃（不猜）', () {
      expect(parseNotification(_wechat('你已成功支付')), isNull);
    });

    test('金额为 0 → 丢弃', () {
      expect(parseNotification(_wechat('已支付 0.00元')), isNull);
    });

    test('方向：收款到账 / 到账 → income', () {
      expect(parseNotification(_wechat('收款到账 100.00元'))!.direction, 'income');
      expect(parseNotification(_alipay('你有一笔 88.00元 到账'))!.direction, 'income');
    });

    test('方向：支付成功 / 扣款 / 消费 → expense', () {
      expect(parseNotification(_wechat('支付成功 5.00元'))!.direction, 'expense');
      expect(parseNotification(_wechat('银行卡扣款 5.00元'))!.direction, 'expense');
      expect(parseNotification(_wechat('消费 5.00元'))!.direction, 'expense');
    });

    test('方向判不出来 → 丢弃', () {
      // ⚠️ title 也要避开关键词：标题多半就是「微信支付」，本身就含「支付」二字
      expect(
        parseNotification(
          _wechat('你的账户有一条新消息 3.00元', title: '微信'),
        ),
        isNull,
      );
    });

    test('商户提取：「向星巴克付款」', () {
      final row = parseNotification(_wechat('你已成功向星巴克付款 30.00元'))!;
      expect(row.counterparty, contains('星巴克'));
    });

    test('无商户名 → 退化为平台名（备注不能为空，用户至少要能认出是哪家）', () {
      expect(parseNotification(_wechat('你已成功支付 12.00元'))!.counterparty,
          '微信支付');
      expect(parseNotification(_alipay('付款成功 12.00元'))!.counterparty,
          '支付宝支付');
    });

    test('时间取通知 postTime，不解析文案里的时间', () {
      final row = parseNotification(_wechat('支付成功 12.00元', at: 1600000000000))!;
      expect(row.occurredAt, 1600000000000);
    });

    test('externalId：同输入稳定、postTime 变则不同', () {
      final a = parseNotification(_wechat('支付成功 12.00元'))!;
      final b = parseNotification(_wechat('支付成功 12.00元'))!;
      final c = parseNotification(_wechat('支付成功 12.00元', at: _t + 1000))!;
      expect(a.externalId, b.externalId);
      expect(a.externalId, isNot(c.externalId));
    });
  });

  group('RawNotification.tryParse（Kotlin 传回来的 JSON 行）', () {
    test('正常行可解析', () {
      final RawNotification? n = RawNotification.tryParse(
        '{"kind":"notification","pkg":"com.tencent.mm","title":"微信支付",'
        '"text":"支付成功 12.00元","bigText":"","subText":"","postTimeMs":$_t}',
      );
      expect(n, isNotNull);
      expect(n!.pkg, 'com.tencent.mm');
      expect(n.postTimeMs, _t);
    });

    test('坏行一律返回 null，不抛异常', () {
      expect(RawNotification.tryParse('not json'), isNull);
      expect(RawNotification.tryParse('[]'), isNull);
      expect(RawNotification.tryParse('{"kind":"share","text":"x"}'), isNull);
    });

    test('combined 会带上 bigText（展开态才有的正文常常更完整）', () {
      final RawNotification n = RawNotification.tryParse(
        '{"kind":"notification","pkg":"com.tencent.mm","title":"微信支付",'
        '"text":"","bigText":"你已成功支付 8.00元","subText":"","postTimeMs":$_t}',
      )!;
      expect(parseNotification(n)!.amountCents, 800);
    });
  });

  group('分享文本路径（零权限兜底）', () {
    test('解析成功且 source = share', () {
      final row = parseSharedText(
        const RawShare(text: '微信支付 你已成功支付 12.00元', postTimeMs: _t),
      )!;
      expect(row.source, 'share');
      expect(row.amountCents, 1200);
      expect(row.direction, 'expense');
    });

    test('忽略规则同样生效', () {
      expect(
        parseSharedText(const RawShare(text: '微信转账 50.00元', postTimeMs: _t)),
        isNull,
      );
    });

    test('RawShare.tryParse：空文本 / 坏行 → null', () {
      expect(RawShare.tryParse('{"kind":"share","text":"","postTimeMs":1}'), isNull);
      expect(RawShare.tryParse('{"kind":"share","text":"  ","postTimeMs":1}'), isNull);
      expect(RawShare.tryParse('nope'), isNull);
      expect(
        RawShare.tryParse('{"kind":"notification","pkg":"x"}'),
        isNull,
      );
    });
  });

  group('空输入 / 边界', () {
    test('三个正文位全空 → 丢弃', () {
      expect(
        parseNotification(
          const RawNotification(
            pkg: 'com.tencent.mm',
            title: '',
            text: '',
            bigText: '',
            subText: '',
            postTimeMs: _t,
          ),
        ),
        isNull,
      );
    });

    test('source 取值表包含三个自动记账来源（撤销按此过滤）', () {
      expect(kPackageSource.values.toSet(), <String>{
        'notify_wechat',
        'notify_alipay',
      });
      expect(kAutoBookSources, contains('share'));
      expect(kAutoBookSources, contains('notify_wechat'));
      expect(kAutoBookSources, contains('notify_alipay'));
    });
  });
}
