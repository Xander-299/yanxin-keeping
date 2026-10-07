/// 自动记账的解析规则（F7.15 SPEC §3.4 / §3.5）—— **纯函数，全部可单测**。
///
/// 输入是 Kotlin 侧落盘的原始通知（或分享文本），输出归一化的 `ParsedRow`
/// —— 与账单导入**共用同一条入账链路**（`importRows` + 指纹去重）。
///
/// 三层顺序（先命中先赢，与 `category_rules.dart` 同写法，不另发明 DSL）：
///   ① 包名白名单（仅通知；分享文本跳过） → ② 忽略规则（非消费，命中即丢） → ③ 模板规则
///
/// 铁律（与导入链路一致）：金额全程 `yuanToCents` 字符串转分，**禁止浮点**。
/// 解析不出方向 / 金额 → 返回 null（**丢弃而不误记**）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/import/data/bill_normalize.dart' show ParsedRow;

/// 平台包名 → `transactions.source` 取值。
///
/// ⚠️ `source` 是 TEXT 无 CHECK 约束 → 取值域从预留的 `notification` 细化为下面三个，
/// **零迁移**（DB 仍 schemaVersion 3）。
const Map<String, String> kPackageSource = <String, String>{
  'com.tencent.mm': 'notify_wechat',
  'com.eg.android.AlipayGphone': 'notify_alipay',
};

/// source → 展示名（账户名 / 通知明细行）。
const Map<String, String> kSourceLabel = <String, String>{
  'notify_wechat': '微信',
  'notify_alipay': '支付宝',
  'share': '分享记账',
};

/// 自动记账产生的全部 source 取值（撤销时按此过滤）。
const List<String> kAutoBookSources = <String>[
  'notify_wechat',
  'notify_alipay',
  'share',
];

/// 忽略关键词（包含匹配）：命中即丢，**优先于**模板规则（SPEC §3.5）。
///
/// 都是「看着像支付、其实不是消费」的文案：转账 / 红包 / 退款 / 各类营销与提醒。
/// ⚠️ 这张表里的词只要出现就判非消费 —— 所以**只放「必然不是消费」的词**；
/// 可能出现在真实支付回执里的营销词（如「优惠」「立减」）走
/// [kAutoBookSoftIgnoreKeywords]，见那里的说明。
const List<String> kAutoBookIgnoreKeywords = <String>[
  '转账',
  '红包',
  '退款',
  '已退款',
  '充值成功',
  '验证码',
  '月账单',
  '账单汇总',
  '领取',
  '积分',
  '即将',
  '提醒',
];

/// 条件性忽略词：**只有整条文案看不出是支付时**才丢。
///
/// 起因（2026-10-07 走查）：真实支付回执常常长这样 ——
/// 「付款成功，优惠 0.50 元」「支付成功，立减 2 元」。这些都含营销词，
/// 但**是真实消费**。原实现把「优惠 / 立减 / 满减」放进硬忽略表 → 这类回执被静默丢弃，
/// 用户完全无从得知（表现为「自动记账不生效」）。
///
/// 现在的判定：软忽略词命中 **且** [kAutoBookStrongPaymentKeywords] 一个都不中 → 丢弃。
/// 宁可多记一笔（用户可整批撤销），也不要静默漏记。
const List<String> kAutoBookSoftIgnoreKeywords = <String>[
  '优惠',
  '立减',
  '满减',
  '活动',
];

/// 强支付词：出现即认定「这是一条支付回执」，压过软忽略词。
///
/// ⚠️ **不要往里加 `支付` / `付款` 这种宽词** —— 微信支付通知的标题就是「微信支付」，
/// 加了之后任何微信营销通知（「周末活动，立减 5 元」）都会因为标题里的「支付」被放行并误记。
const List<String> kAutoBookStrongPaymentKeywords = <String>[
  '支付成功',
  '成功支付',
  '付款成功',
  '成功付款',
  '已支付',
  '已付款',
  '扣款',
  '消费',
  '到账',
  '实付',
];

/// 保留关键词：用于确认这是**消费/收入**通知（方向判定也靠它）。
const List<String> kAutoBookIncomeKeywords = <String>[
  '收款到账',
  '到账',
  '收款',
  '收入',
];

const List<String> kAutoBookExpenseKeywords = <String>[
  '支付成功',
  '付款成功',
  '已支付',
  '扣款',
  '消费',
  '支付',
  '付款',
];

/// Kotlin 侧落盘的一条原始通知。
class RawNotification {
  const RawNotification({
    required this.pkg,
    required this.title,
    required this.text,
    required this.bigText,
    required this.subText,
    required this.postTimeMs,
  });

  final String pkg;
  final String title;
  final String text;
  final String bigText;
  final String subText;
  final int postTimeMs;

  /// 解析 Kotlin 传回来的 JSON 行；结构不对返回 null（调用方按坏行丢弃）。
  static RawNotification? tryParse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, Object?> map = decoded.cast<String, Object?>();
      if (map['kind'] != 'notification') return null;
      return RawNotification(
        pkg: (map['pkg'] as String?) ?? '',
        title: (map['title'] as String?) ?? '',
        text: (map['text'] as String?) ?? '',
        bigText: (map['bigText'] as String?) ?? '',
        subText: (map['subText'] as String?) ?? '',
        postTimeMs: _asInt(map['postTimeMs']),
      );
    } catch (_) {
      return null;
    }
  }

  /// 全部文案位拼成一段（解析用）。`bigText` 常在展开态才有，放最前命中率最高。
  String get combined => <String>[title, text, bigText, subText]
      .where((String s) => s.isNotEmpty)
      .join(' ');

  /// 指纹用的稳定标识（不用系统通知 id —— 它不稳定）。
  String get externalId => sha1
      .convert(utf8.encode('$pkg|$title|$text|${postTimeMs ~/ 1000}'))
      .toString();
}

/// Kotlin 侧落盘的一条分享文本。
class RawShare {
  const RawShare({required this.text, required this.postTimeMs});

  final String text;
  final int postTimeMs;

  static RawShare? tryParse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, Object?> map = decoded.cast<String, Object?>();
      if (map['kind'] != 'share') return null;
      final String text = (map['text'] as String?) ?? '';
      if (text.trim().isEmpty) return null;
      return RawShare(text: text, postTimeMs: _asInt(map['postTimeMs']));
    } catch (_) {
      return null;
    }
  }

  String get externalId => sha1
      .convert(utf8.encode('share|$text|${postTimeMs ~/ 1000}'))
      .toString();
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// 金额提取（多级降级，先命中先赢）——SPEC §3.4。
///
/// ⚠️ **顺序即优先级，不能随便调**：真实回执常同时出现多个金额，例如
/// 「订单金额 13.00元，优惠 1.00元，实付 12.00元」。若直接抓第一个数字，
/// 记进去的就是**优惠金额** —— 比不记账更糟（用户看到的是错数）。
/// 所以先用「实付 / 支付 / 付款」类词锚定，再退化为符号 / 裸金额。
final List<RegExp> _amountPatterns = <RegExp>[
  // ① 实付类（明确指向实际支出）
  RegExp(r'(?:实付|实际支付|支付金额|付款金额|扣款金额)\D{0,4}?(\d+(?:\.\d{1,2})?)\s*元'),
  // ② 支付动作紧邻的金额
  RegExp(r'(?:支付|付款|扣款|消费|已付)\D{0,6}?(\d+(?:\.\d{1,2})?)\s*元'),
  // ③ 货币符号
  RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)'),
  // ④ 裸「N 元」/「N.NN」
  RegExp(r'(\d+(?:\.\d{1,2})?)\s*元'),
  RegExp(r'(\d+\.\d{2})'),
];

/// 商户名提取（顺序即优先级；**允许全部不中** —— 多数通知不含商户名）。
final List<RegExp> _counterpartyPatterns = <RegExp>[
  RegExp(r'向(.{1,24}?)付款'),
  RegExp(r'收款方[:：]\s*(.{1,24})'),
  RegExp(r'付款给(.{1,24}?)'),
  RegExp(r'在(.{1,24}?)(?:消费|支付)'),
];

/// 解析一条通知；丢弃返回 null。
ParsedRow? parseNotification(RawNotification n) {
  final String? source = kPackageSource[n.pkg];
  if (source == null) return null; // ① 包名白名单
  final String text = n.combined;
  if (text.trim().isEmpty) return null;
  if (_isIgnored(text)) return null; // ② 忽略规则
  final String? direction = _directionOf(text); // ③ 模板规则
  if (direction == null) return null;
  final int? amountCents = _amountCentsOf(text);
  if (amountCents == null || amountCents <= 0) return null;

  final String merchant = _counterpartyOf(text);
  return ParsedRow(
    source: source,
    externalId: n.externalId,
    occurredAt: n.postTimeMs > 0 ? n.postTimeMs : DateTime.now().millisecondsSinceEpoch,
    amountCents: amountCents,
    direction: direction,
    // 商户名提取不到时退化为主通道名（保证流水备注不为空，用户至少能认出是微信还是支付宝）
    counterparty: merchant.isNotEmpty ? merchant : '${kSourceLabel[source]}支付',
    product: '',
    method: '',
    status: '通知',
    unknownStatus: false,
    rawIndex: 0,
  );
}

/// 解析一条分享文本（零权限兜底路径）；丢弃返回 null。
ParsedRow? parseSharedText(RawShare share) {
  final String text = share.text;
  if (text.trim().isEmpty) return null;
  if (_isIgnored(text)) return null;
  final String? direction = _directionOf(text);
  if (direction == null) return null;
  final int? amountCents = _amountCentsOf(text);
  if (amountCents == null || amountCents <= 0) return null;
  final String merchant = _counterpartyOf(text);
  return ParsedRow(
    source: 'share',
    externalId: share.externalId,
    occurredAt: share.postTimeMs > 0
        ? share.postTimeMs
        : DateTime.now().millisecondsSinceEpoch,
    amountCents: amountCents,
    direction: direction,
    counterparty: merchant.isNotEmpty ? merchant : '分享记账',
    product: '',
    method: '',
    status: '分享',
    unknownStatus: false,
    rawIndex: 0,
  );
}

bool _isIgnored(String text) {
  for (final String k in kAutoBookIgnoreKeywords) {
    if (text.contains(k)) return true;
  }
  // 软忽略：营销词单独出现才丢；有强支付词（真实回执）则放行
  var hasSoft = false;
  for (final String k in kAutoBookSoftIgnoreKeywords) {
    if (text.contains(k)) {
      hasSoft = true;
      break;
    }
  }
  if (hasSoft && !_hasStrongPayment(text)) return true;
  return false;
}

bool _hasStrongPayment(String text) {
  for (final String k in kAutoBookStrongPaymentKeywords) {
    if (text.contains(k)) return true;
  }
  return false;
}

String? _directionOf(String text) {
  // 先判收入：「到账」类通知常同时含「支付」字样（如「收款到账」）
  for (final String k in kAutoBookIncomeKeywords) {
    if (text.contains(k)) return 'income';
  }
  for (final String k in kAutoBookExpenseKeywords) {
    if (text.contains(k)) return 'expense';
  }
  return null;
}

int? _amountCentsOf(String text) {
  // 千分位先去干净：'1,234.00元' 不能只匹配到 '234.00'
  final String s = text.replaceAll(',', '');
  for (final RegExp p in _amountPatterns) {
    final RegExpMatch? m = p.firstMatch(s);
    final String? raw = m?.group(1);
    if (raw == null || raw.isEmpty) continue;
    try {
      return yuanToCents(raw);
    } on FormatException {
      continue;
    }
  }
  return null;
}

String _counterpartyOf(String text) {
  for (final RegExp p in _counterpartyPatterns) {
    final String? g = p.firstMatch(text)?.group(1)?.trim();
    if (g != null && g.isNotEmpty) return g;
  }
  return '';
}
