/// 自动记账的解析规则（F7.15 SPEC §3.4 / §3.5）—— **纯函数，全部可单测**。
///
/// 输入是 Kotlin 侧落盘的原始通知（或分享文本），输出归一化的 `ParsedRow`
/// —— 与账单导入**共用同一条入账链路**（`importRows` + 指纹去重）。
///
/// 四层顺序（先命中先赢，与 `category_rules.dart` 同写法，不另发明 DSL）：
///   ⓪ 折叠前缀归一化（`[N条]…` 是**显示层前缀**，剥掉再解析 —— 它**不是**组摘要） →
///   ① 包名白名单（仅通知；分享文本跳过） → ② 忽略规则（非消费，命中即丢） → ③ 模板规则（方向 + 金额）
///
/// ⚠️ 规则**逐字对着真机通知**校准（样本见 `test/features/autobook/auto_book_real_samples_test.dart`）；
/// 改关键词前先看那里的真实文案，别按想象写。
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

/// 硬忽略关键词（包含匹配）：命中即丢，**优先于**模板规则（SPEC §3.5）。
///
/// 判据：这个词描述的是**另一类交易**（资金调度 / 退款 / 非消费凭证），
/// 只要出现就不可能是本 App 要记的「消费 / 收入」。
/// ⚠️ 这张表里的词只要出现就判非消费 —— 所以**只放「必然不是消费」的词**；
/// 凡是可能搭在真实回执里一起出现的营销词 / 提醒词（`优惠` `立减` `红包` `提醒` `即将` …）
/// 一律走 [kAutoBookSoftIgnoreKeywords]，见那里的说明与 2026-10-08 真机复盘。
const List<String> kAutoBookIgnoreKeywords = <String>[
  '转账',
  '退款',
  '已退款',
  '充值成功',
  '验证码',
  '月账单',
  '账单汇总',
  '还款',
];

/// 条件性忽略词：**只有整条文案看不出是支付时**才丢。
///
/// 起因（2026-10-07 走查）：真实支付回执常常长这样 ——
/// 「付款成功，优惠 0.50 元」「支付成功，立减 2 元」。这些都含营销词，
/// 但**是真实消费**。原实现把「优惠 / 立减 / 满减」放进硬忽略表 → 这类回执被静默丢弃，
/// 用户完全无从得知（表现为「自动记账不生效」）。
///
/// 第二轮修正（2026-10-08 真机排查 · Redmi K50）：把 `红包` / `提醒` / `领取` / `积分` / `即将`
/// 也从硬忽略表**降级**到这里 —— 真机上支付宝的付款通知标题就是「交易提醒」，
/// 正文还带营销尾巴「你有一笔0.01元的支出，领2元小荷包支付红包。」，
/// 两条都撞硬忽略 → 支付宝付款**一笔都记不上**，且全程静默。
///
/// 现在的判定：软忽略词命中 **且** [kAutoBookStrongPaymentKeywords] 一个都不中 → 丢弃。
/// 宁可多记一笔（用户可整批撤销），也不要静默漏记。
const List<String> kAutoBookSoftIgnoreKeywords = <String>[
  '优惠',
  '立减',
  '满减',
  '活动',
  '红包',
  '提醒',
  '领取',
  '积分',
  '即将',
];

/// 强收支词：出现即认定「这是一条支付 / 收款回执」，压过软忽略词。
///
/// ⚠️ **不要往里加 `支付` / `付款` 这种宽词** —— 微信支付通知的标题就是「微信支付」，
/// 加了之后任何微信营销通知（「周末活动，立减 5 元」）都会因为标题里的「支付」被放行并误记。
/// `支出` / `收入` 是支付宝交易提醒的实际措辞（「你有一笔0.01元的支出」/「…元的收入」），
/// 必须收进来；收入侧同理补 `已收款` / `成功收款`（`收款到账` 的「到账」已在表内）。
const List<String> kAutoBookStrongPaymentKeywords = <String>[
  '支付成功',
  '成功支付',
  '付款成功',
  '成功付款',
  '已支付',
  '已付款',
  '扣款',
  '消费',
  '支出',
  '收入',
  '到账',
  '实付',
  '已收款',
  '成功收款',
];

/// 保留关键词：用于确认这是**消费/收入**通知（方向判定也靠它）。
///
/// 收入先判（`到账` 类通知常同时含 `支付` 字样，如「收款到账」）。
const List<String> kAutoBookIncomeKeywords = <String>[
  '收款到账',
  '到账',
  '收款',
  '收入',
];

/// 支出侧方向词。`支出` 来自支付宝交易提醒的真实措辞（2026-10-08 真机抓取）。
const List<String> kAutoBookExpenseKeywords = <String>[
  '支付成功',
  '付款成功',
  '已支付',
  '扣款',
  '消费',
  '支出',
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
  ///
  /// 三个正文位都先剥掉显示层的折叠前缀（[_foldPrefixPattern]）再拼 ——
  /// 否则 `[3条]微信支付: 已支付¥0.03` 的前缀会留在最前面。
  String get combined => <String>[title, _stripFoldPrefix(text), _stripFoldPrefix(bigText), subText]
      .where((String s) => s.isNotEmpty)
      .join(' ');

  /// 指纹用的稳定标识（不用系统通知 id —— 它不稳定）。
  ///
  /// ⚠️ 用**归一化后**的正文：同一条通知的折条数会变（`[2条]…` → `[3条]…`），
  /// 若指纹带上原始前缀，同一条通知会被算成两笔 → **重复入账**。
  String get externalId => sha1
      .convert(utf8.encode('$pkg|$title|${_stripFoldPrefix(text)}|${postTimeMs ~/ 1000}'))
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
  RegExp(r'(?:实付|实际支付|支付金额|付款金额|扣款金额|支出金额)\D{0,4}?(\d+(?:\.\d{1,2})?)\s*元'),
  // ② 金额在动作词**之前**（支付宝交易提醒的典型句式：「你有一笔0.01元的支出」）
  //    ⚠️ 必须排在「裸 N 元」之前：同一条里营销语可能带着更靠前的金额
  //    （「…0.01元的支出，领2元小荷包支付红包」→ 裸匹配会先抓到营销的 2 元）
  RegExp(r'(\d+(?:\.\d{1,2})?)\s*元\s*的?\s*(?:支出|消费|收入|付款|支付|收款)'),
  // ③ 支付动作紧邻的金额
  RegExp(r'(?:支付|付款|扣款|消费|支出|已付)\D{0,6}?(\d+(?:\.\d{1,2})?)\s*元'),
  // ④ 货币符号
  RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)'),
  // ⑤ 裸「N 元」/「N.NN」
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
  // ⓪ 折叠前缀已在 `combined` / `externalId` 里归一化（见 [RawNotification.combined]）。
  //    ⚠️ 这里**刻意不再按 `[N条]` 丢弃** —— 取证与理由见 [_foldPrefixPattern]。
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

/// 显示层的**折叠前缀**：`[N条]`（MIUI 把同应用的未读通知折叠展示时加在正文最前面）。
///
/// ⚠️⚠️ **它不是「组摘要」** —— 这是 2026-10-08 事故排查（Redmi K50 / HyperOS）的取证结论，
/// 推翻 F7.15 `e4e53b4` 时的判断：
///
/// | 证据 | 值 | 含义 |
/// |---|---|---|
/// | `dumpsys notification` 的 `Group summaries:` 段 | **没有 `com.tencent.mm`** | 系统没把它登记为组摘要 |
/// | `flags` | `0x11`（不含 `FLAG_GROUP_SUMMARY=0x200`） | 系统标志说它不是摘要 |
/// | `groupKey` | `0|com.tencent.mm|-656511598|…`（**等于自己的 key**） | 压根没进任何分组 |
/// | `tickerText` | `微信支付: 已支付¥0.03`（**无前缀**） | 前缀是显示层加的，不是原文 |
///
/// 当时的反例（`[2条]微信支付: 已支付¥0.01` + `[2条]微信支付: 个人收款码到账¥0.01`）
/// 被当成了「摘要 + 子通知」，其实那是**两笔不同交易**（一笔支出、一笔收款），各自独立。
///
/// 后果：旧实现 `if (^\[\d+条\] → return null)` 把这唯一载体**静默丢弃** →
/// 微信支付一笔都记不上（用户报「识别不到微信支付」）。
///
/// 现在只做**归一化**（剥前缀再解析），并且 `externalId` 也用归一化后的正文 ——
/// 同一条通知的折条数变化（`[2条]` → `[3条]`）不会变成两笔。
/// 真正需要丢弃的组摘要由 Kotlin 侧按 `FLAG_GROUP_SUMMARY` / `EXTRA_IS_GROUP_SUMMARY`
/// **权威判定**（`AutoBookListenerService.handle`），根本到不了这里。
final RegExp _foldPrefixPattern = RegExp(r'^\s*\[\d+条\]\s*');

/// 剥掉显示层折叠前缀（`[3条]微信支付: …` → `微信支付: …`）；无前缀时原样返回。
String _stripFoldPrefix(String s) => s.replaceFirst(_foldPrefixPattern, '');

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
