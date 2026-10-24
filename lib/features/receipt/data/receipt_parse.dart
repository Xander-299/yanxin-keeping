/// 截图 OCR 文本 → 记账草稿（F8.1）—— **纯函数，全部可单测**。
///
/// 输入是 OCR 出来的行文本（按"先上后右"排好序），输出 [ReceiptDraft]。
/// 三层识别的第二层就在这里：**规则优先，不确定就交用户确认**。
///
/// 铁律：
/// - 金额全程 `yuanToCents` 字符串转分，**禁止浮点**；
/// - 判定不出来就留 `absent` + 一条 issue，**绝不编造字段**；
/// - 规则表在 `receipt_rules.dart`，不要在这里塞关键词。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/import/data/bill_normalize.dart' show ParsedRow;
import 'package:yanxin/features/import/data/category_rules.dart'
    show CategorizeResult, categorizeRow;
import 'package:yanxin/features/receipt/application/receipt_draft.dart';
import 'package:yanxin/features/receipt/data/receipt_rules.dart';

/// 一条金额命中。
class _AmountHit {
  const _AmountHit({
    required this.cents,
    required this.anchorIndex,
    required this.tag,
    required this.discounted,
    this.signed = false,
  });

  final int cents;
  final int anchorIndex;
  final String tag;
  final bool discounted;

  /// 金额自带正负号（微信凭证写作 `-3.00`）—— 这既是方向线索，也说明它是个"真金额"。
  final bool signed;

  /// 排序权重：**非优惠行优先**，同档再按锚点顺序（越小越可信）。
  int get rank => (discounted ? 100 : 0) + anchorIndex;
}

/// 金额独占一行（可带正负号）：`12.00` / `-3.00` / `+5.00`。
///
/// 微信账单详情就是这种版式：**上一行是收款方、这一行是金额**。
final RegExp kStandaloneAmountLine = RegExp(r'^\s*([+-])?\d{1,7}\.\d{2}\s*$');

/// 把 OCR 原文行归一化：全角空格转半角、压缩连续空白、丢空行。
///
/// 不做"去标点"之类激进清洗 —— 金额 / 时间靠标点锚定，洗掉就识别不了了。
List<String> normalizeReceiptLines(List<String> raw) {
  final List<String> out = <String>[];
  for (final String line in raw) {
    final String s = line
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (s.isEmpty) continue;
    out.add(s);
  }
  return out;
}

/// 解析一次 OCR 结果。
///
/// [nowMs] 由调用方注入（便于测试"缺年份时按哪天推算"），不要在函数里取 `DateTime.now()`。
ReceiptDraft parseReceipt(List<String> rawLines, {required int nowMs}) {
  final List<String> lines = normalizeReceiptLines(rawLines);
  final String text = lines.join('\n');
  final String textHash = sha1.convert(utf8.encode(text)).toString();

  if (lines.isEmpty) {
    return ReceiptDraft(
      platform: ReceiptPlatform.unknown,
      status: ReceiptStatus.unknown,
      direction: const ReceiptField<String>.absent(),
      amountCents: const ReceiptField<int>.absent(),
      occurredAtMs: const ReceiptField<int>.absent(),
      merchant: const ReceiptField<String>.absent(),
      categoryName: const ReceiptField<String>.absent(),
      issues: const <ReceiptIssue>[ReceiptIssue.emptyText],
      textHash: textHash,
      rawText: text,
    );
  }

  final ReceiptPlatform platform = detectReceiptPlatform(text);
  final ReceiptStatus status = detectReceiptStatus(text);
  final ReceiptField<String> direction = _pickDirection(
    text: text,
    status: status,
    platform: platform,
    signDirection: _signDirectionOf(lines),
  );
  final _AmountPick amount = _pickAmount(lines);
  final _TimePick time = _pickTime(lines, nowMs: nowMs);
  final _MerchantPick merchant = _pickMerchant(lines, text);
  final String? orderNo = _pickOrderNo(lines);
  final String? paymentType = _pickPaymentType(lines, platform);
  final CategorizeResult category = _pickCategory(
    direction: direction.value ?? 'expense',
    merchant: merchant.merchant.value ?? '',
    product: merchant.product ?? '',
    amountCents: amount.field.value ?? 0,
    occurredAtMs: time.field.value ?? nowMs,
  );

  final List<ReceiptIssue> issues = _buildIssues(
    text: text,
    platform: platform,
    status: status,
    direction: direction,
    amount: amount,
    time: time,
    merchant: merchant.merchant,
  );

  return ReceiptDraft(
    platform: platform,
    status: status,
    direction: direction,
    amountCents: amount.field,
    occurredAtMs: time.field,
    merchant: merchant.merchant,
    categoryName: category.matched
        ? ReceiptField<String>(
            value: category.categoryName,
            confidence: FieldConfidence.medium,
            tag: '关键词',
          )
        : ReceiptField<String>(
            value: category.categoryName,
            confidence: FieldConfidence.low,
            tag: '默认',
          ),
    issues: issues,
    textHash: textHash,
    rawText: text,
    orderNo: orderNo,
    paymentType: paymentType,
  );
}

// ────────────────────────────── 平台 / 状态 / 方向 ──────────────────────────────

/// 平台判定（顺序即优先级：微信 / 支付宝先于"银行卡"，
/// 因为支付宝页面里常出现「储蓄卡」「尾号」这些支付方式词）。
ReceiptPlatform detectReceiptPlatform(String text) {
  if (_containsAny(text, kWechatSignals)) return ReceiptPlatform.wechat;
  if (_containsAny(text, kAlipaySignals)) return ReceiptPlatform.alipay;
  if (_containsAny(text, kBankSignals)) return ReceiptPlatform.bank;
  if (_containsAny(text, kOrderSignals)) return ReceiptPlatform.order;
  return ReceiptPlatform.unknown;
}

/// 状态判定（失败 > 取消 > 退款 > 待付款 > 成功）。
ReceiptStatus detectReceiptStatus(String text) {
  if (_containsAny(text, kFailedWords)) return ReceiptStatus.failed;
  if (_containsAny(text, kCancelledWords)) return ReceiptStatus.cancelled;
  if (_containsAny(text, kRefundWords)) return ReceiptStatus.refund;
  if (_containsAny(text, kPendingWords)) return ReceiptStatus.pending;
  if (_containsAny(text, kOkWords)) return ReceiptStatus.ok;
  return ReceiptStatus.unknown;
}

/// 从"带符号的金额独占行"判断方向（微信凭证：`-3.00` 支出 / `+3.00` 收入）。
///
/// 作为方向判定的**兜底**：有些凭证只写金额和商户，没有任何"支付成功"字样。
String? _signDirectionOf(List<String> lines) {
  for (final String line in lines) {
    final RegExpMatch? m = kStandaloneAmountLine.firstMatch(line);
    if (m == null) continue;
    final String? sign = m.group(1);
    if (sign == '-') return 'expense';
    if (sign == '+') return 'income';
  }
  return null;
}

ReceiptField<String> _pickDirection({
  required String text,
  required ReceiptStatus status,
  required ReceiptPlatform platform,
  String? signDirection,
}) {
  // 退款 → 钱回来了：建议记收入（用户仍可改成支出）
  if (status == ReceiptStatus.refund) {
    return const ReceiptField<String>(
      value: 'income',
      confidence: FieldConfidence.medium,
      tag: '退款',
    );
  }
  // 先判收入：「收款到账」同时含「支付」，顺序错了会把收款记成支出
  if (_containsAny(text, kIncomeWords)) {
    return const ReceiptField<String>(
      value: 'income',
      confidence: FieldConfidence.high,
      tag: '收入词',
    );
  }
  if (_containsAny(text, kExpenseWords)) {
    return const ReceiptField<String>(
      value: 'expense',
      confidence: FieldConfidence.high,
      tag: '支出词',
    );
  }
  // 金额的符号（`-3.00` / `+3.00`）比平台猜测可靠
  if (signDirection != null) {
    return ReceiptField<String>(
      value: signDirection,
      confidence: FieldConfidence.medium,
      tag: '金额符号',
    );
  }
  // 电商订单页往往只写"合计 / 待发货"，没有"支付成功"字样
  if (platform == ReceiptPlatform.order) {
    return const ReceiptField<String>(
      value: 'expense',
      confidence: FieldConfidence.medium,
      tag: '订单',
    );
  }
  return const ReceiptField<String>.absent();
}

// ────────────────────────────── 金额 ──────────────────────────────

class _AmountPick {
  const _AmountPick({required this.field, required this.onlyDiscounted});

  final ReceiptField<int> field;

  /// 命中的金额**全是**原价 / 优惠（没有一个是实付）。
  final bool onlyDiscounted;
}

_AmountPick _pickAmount(List<String> lines) {
  final Map<int, _AmountHit> byCents = <int, _AmountHit>{};
  var sawDiscounted = false;
  var sawActualPay = false;

  for (final String line in lines) {
    final bool discounted = _containsAny(line, kDiscountWords);
    for (int i = 0; i < kAmountAnchors.length; i++) {
      final AmountAnchor anchor = kAmountAnchors[i];
      final RegExpMatch? m = anchor.pattern.firstMatch(line);
      if (m == null) continue;
      // 防御：锚点表里每个 pattern 都必须有捕获组（group 1 = 金额原文）。
      // 漏了组会抛 RangeError —— 真实样本第一次跑就踩到了（`独立行` 曾漏写括号）。
      if (m.groupCount < 1) continue;
      final String? raw = m.group(1);
      if (raw == null) continue;
      final int? cents = _centsOf(raw);
      if (cents == null || cents <= 0) continue;
      // ⚠️ 优惠词要**贴着金额**才算（「优惠 ¥1.00」），不能整行命中就判 ——
      // 支付宝真实文案「你有一笔12.00元的支出，领2元小荷包支付红包」整行含「红包」，
      // 按整行判会把真金额也标成优惠，于是"主金额"没了。
      final bool hitDiscounted =
          discounted && _isDiscountAdjacent(line, m);
      final _AmountHit hit = _AmountHit(
        cents: cents,
        anchorIndex: i,
        tag: anchor.tag,
        discounted: hitDiscounted,
        signed: raw.trimLeft().startsWith('-') || raw.trimLeft().startsWith('+'),
      );
      if (hitDiscounted) sawDiscounted = true;
      if (anchor.actualPay && !hitDiscounted) sawActualPay = true;
      final _AmountHit? prev = byCents[cents];
      if (prev == null || hit.rank < prev.rank) byCents[cents] = hit;
    }
  }

  if (byCents.isEmpty) {
    return const _AmountPick(
      field: ReceiptField<int>.absent(),
      onlyDiscounted: false,
    );
  }

  final List<_AmountHit> ordered = byCents.values.toList()
    ..sort((_AmountHit a, _AmountHit b) => a.rank.compareTo(b.rank));

  // 原价 / 优惠行上的金额只当"备选"，不参与"谁是实付"的判断 ——
  // 否则「订单金额 13.00 / 优惠 1.00 / 实付 12.00」会变成三个平级候选，用户得自己挑。
  final List<_AmountHit> meaningful = ordered
      .where((_AmountHit h) => !h.discounted)
      .toList(growable: false);
  final List<_AmountHit> pool = meaningful.isEmpty ? ordered : meaningful;
  final _AmountHit primary = pool.first;
  final List<int> candidates = <int>[
    for (final _AmountHit h in pool.skip(1)) h.cents,
  ];

  final FieldConfidence confidence;
  if (pool.length > 1) {
    // 多个可信金额 → 该记哪个必须让用户选
    confidence = FieldConfidence.low;
  } else if (meaningful.isEmpty) {
    // 只认到原价 / 优惠（没有实付）：宁可让用户确认
    confidence = FieldConfidence.low;
  } else if (primary.signed) {
    // 微信账单详情：金额独占一行且带正负号 —— 这是最干净的形态
    confidence = FieldConfidence.high;
  } else if (primary.anchorIndex <= 2) {
    // 实付 / 退款金额 / 动作前 = 明确的"真金额"
    confidence = FieldConfidence.high;
  } else {
    confidence = FieldConfidence.medium;
  }

  return _AmountPick(
    field: ReceiptField<int>(
      value: primary.cents,
      confidence: confidence,
      candidates: candidates,
      tag: primary.tag,
    ),
    onlyDiscounted: sawDiscounted && !sawActualPay,
  );
}

/// `'1,234.00'` / `'-12.00'` → 整数分（退款金额取绝对值，方向由 status 决定）。
int? _centsOf(String raw) {
  final String s = raw.replaceAll(',', '').replaceFirst('-', '').trim();
  if (s.isEmpty) return null;
  try {
    return yuanToCents(s);
  } on FormatException {
    return null;
  }
}

/// 优惠词是否"贴着"这笔金额（金额**前** 8 字内）。
///
/// 只看"金额之前"是有意为之：真实文案里优惠/原价标签永远在前（「优惠 ¥1.00」「原价 13.00」），
/// 而营销尾巴总在后（「…支付红包」）。双向窗口会把
/// 「你有一笔12.00元的支出，领2元小荷包支付红包」里的**真金额**也标成优惠 ——
/// 那样"主金额"就没了（2026-10-24 写测试时抓到的）。
bool _isDiscountAdjacent(String line, Match match) {
  for (final String word in kDiscountWords) {
    int idx = line.indexOf(word);
    while (idx >= 0) {
      final int wordEnd = idx + word.length;
      if (wordEnd <= match.start && match.start - wordEnd <= 8) return true;
      idx = line.indexOf(word, idx + 1);
    }
  }
  return false;
}

// ────────────────────────────── 时间 ──────────────────────────────

class _TimePick {
  const _TimePick({required this.field, required this.yearInferred});

  final ReceiptField<int> field;
  final bool yearInferred;
}

_TimePick _pickTime(List<String> lines, {required int nowMs}) {
  // 出现过"像日期但日期非法"的行（2026-02-30 这类 OCR 错读）→ 不再退到"只有时分"，
  // 否则会拿一个错日期 + 今天的时间写进账本，比留空更糟。
  var sawInvalidDate = false;

  // ① 完整年月日 + 时分（可带秒）
  for (final String line in lines) {
    final RegExpMatch? m = kDateTimePattern.firstMatch(line);
    if (m == null) continue;
    final int? ms = _buildMs(
      year: int.tryParse(m.group(1) ?? ''),
      month: int.tryParse(m.group(2) ?? ''),
      day: int.tryParse(m.group(3) ?? ''),
      hour: int.tryParse(m.group(4) ?? ''),
      minute: int.tryParse(m.group(5) ?? ''),
      second: int.tryParse(m.group(6) ?? '0'),
    );
    if (ms == null) {
      sawInvalidDate = true;
      continue;
    }
    return _TimePick(
      field: ReceiptField<int>(
        value: ms,
        confidence: FieldConfidence.high,
        tag: '日期时间',
      ),
      yearInferred: false,
    );
  }

  // ② 只有年月日 → 中午 12:00（避免落进次日 0 点边界，与 SPEC 里"日期无时间"的处理一致）
  for (final String line in lines) {
    final RegExpMatch? m = kDatePattern.firstMatch(line);
    if (m == null) continue;
    final int? ms = _buildMs(
      year: int.tryParse(m.group(1) ?? ''),
      month: int.tryParse(m.group(2) ?? ''),
      day: int.tryParse(m.group(3) ?? ''),
      hour: 12,
      minute: 0,
      second: 0,
    );
    if (ms == null) {
      sawInvalidDate = true;
      continue;
    }
    return _TimePick(
      field: ReceiptField<int>(
        value: ms,
        confidence: FieldConfidence.medium,
        tag: '日期',
      ),
      yearInferred: false,
    );
  }

  // ③ 月-日 + 时分（**年份缺失**）：按"不晚于今天"推年份
  for (final String line in lines) {
    final RegExpMatch? m = kMonthDayTimePattern.firstMatch(line);
    if (m == null) continue;
    final int? month = int.tryParse(m.group(1) ?? '');
    final int? day = int.tryParse(m.group(2) ?? '');
    final int? hour = int.tryParse(m.group(3) ?? '');
    final int? minute = int.tryParse(m.group(4) ?? '');
    if (month == null || day == null || hour == null || minute == null) continue;
    final int? ms = _inferYearMs(
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: 0,
      nowMs: nowMs,
    );
    if (ms == null) {
      sawInvalidDate = true;
      continue;
    }
    return _TimePick(
      field: ReceiptField<int>(
        value: ms,
        confidence: FieldConfidence.medium,
        tag: '月日（年份推算）',
      ),
      yearInferred: true,
    );
  }

  if (sawInvalidDate) {
    return const _TimePick(field: ReceiptField<int>.absent(), yearInferred: false);
  }

  // ④ 只有时分 → 今天；这条最容易错，标 low 让用户看一眼
  for (final String line in lines) {
    final RegExpMatch? m = kTimeOnlyPattern.firstMatch(line);
    if (m == null) continue;
    final int? hour = int.tryParse(m.group(1) ?? '');
    final int? minute = int.tryParse(m.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) continue;
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    final DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
      int.tryParse(m.group(3) ?? '0') ?? 0,
    );
    return _TimePick(
      field: ReceiptField<int>(
        value: candidate.millisecondsSinceEpoch,
        confidence: FieldConfidence.low,
        tag: '时分（按今天）',
      ),
      yearInferred: false,
    );
  }

  return const _TimePick(field: ReceiptField<int>.absent(), yearInferred: false);
}

int? _buildMs({
  required int? year,
  required int? month,
  required int? day,
  required int? hour,
  required int? minute,
  required int? second,
}) {
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour == null || hour < 0 || hour > 23) return null;
  if (minute == null || minute < 0 || minute > 59) return null;
  if (second != null && (second < 0 || second > 59)) return null;
  final DateTime dt = DateTime(year, month, day, hour, minute, second ?? 0);
  // 2 月 30 日这类不存在的日期，DateTime 会顺延 —— 顺延了就说明识别错了
  if (dt.month != month || dt.day != day) return null;
  return dt.millisecondsSinceEpoch;
}

/// 缺年份时按「不晚于今天」推断：今年若已过去就用今年，否则用去年。
///
/// 日期非法（2 月 30 日 / 13 月这类 OCR 错读）返回 null —— **不猜**。
int? _inferYearMs({
  required int month,
  required int day,
  required int hour,
  required int minute,
  required int second,
  required int nowMs,
}) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  DateTime candidate = DateTime(now.year, month, day, hour, minute, second);
  if (candidate.month != month || candidate.day != day) return null;
  // 超过今天 1 天以上 → 只能是去年的（截图不会是未来交易）
  if (candidate.millisecondsSinceEpoch >
      nowMs + const Duration(days: 1).inMilliseconds) {
    candidate = DateTime(now.year - 1, month, day, hour, minute, second);
  }
  return candidate.millisecondsSinceEpoch;
}

// ────────────────────────────── 商户 / 商品 ──────────────────────────────

class _MerchantPick {
  const _MerchantPick({required this.merchant, this.product});

  final ReceiptField<String> merchant;
  final String? product;
}

_MerchantPick _pickMerchant(List<String> lines, String text) {
  // ① 标签式：**标签必须出现在行首**（凭证版式是「标签  值」）。
  //    ⚠️ 不锚行首会踩坑：`商户` 会命中 `商户单号`，于是商户名变成「单号」
  //    （2026-10-24 真实截图抓到的）。
  for (final String line in lines) {
    for (final String label in kMerchantLabels) {
      final int idx = line.indexOf(label);
      if (idx != 0) continue;
      final String value = _cutAtStopWord(
        _cleanValue(line.substring(label.length)),
      );
      // 复合标签（`商户单号` / `商户名称` 被 OCR 拆开时）→ 不是商户名
      if (_startsWithCompoundSuffix(value)) continue;
      if (_isPlausibleMerchant(value)) {
        return _MerchantPick(
          merchant: ReceiptField<String>(
            value: value,
            confidence: FieldConfidence.high,
            tag: label,
          ),
          product: _pickProduct(lines),
        );
      }
    }
  }

  // ② 金额邻行：两种真实版式都要覆盖
  //    - 微信「账单详情」：商户在金额**上面**（`福伴生活(西环店)` / `-3.00` / `当前状态…`）
  //    - 微信「交易详情」：商户在金额**下面**（`-22.98` / `美团` / `当前状态…`）
  //    先看下面（更靠近金额、误命中少），不行再看上面。
  final int amountLineIndex = lines.indexWhere(
    kStandaloneAmountLine.hasMatch,
  );
  if (amountLineIndex >= 0) {
    final List<({int index, String tag})> neighbours =
        <({int index, String tag})>[
          if (amountLineIndex + 1 < lines.length)
            (index: amountLineIndex + 1, tag: '金额下一行'),
          if (amountLineIndex > 0) (index: amountLineIndex - 1, tag: '金额上一行'),
        ];
    for (final ({int index, String tag}) n in neighbours) {
      final String candidate = lines[n.index];
      if (_looksLikeAction(candidate)) continue;
      if (!_isPlausibleMerchant(candidate)) continue;
      return _MerchantPick(
        merchant: ReceiptField<String>(
          value: candidate,
          confidence: FieldConfidence.high,
          tag: n.tag,
        ),
        product: _pickProduct(lines),
      );
    }
  }

  // ③ 商品 / 订单标题（电商截图常见）
  for (final String label in kProductLabels) {
    for (final String line in lines) {
      final int idx = line.indexOf(label);
      if (idx < 0) continue;
      final String value = _cutAtStopWord(
        _cleanValue(line.substring(idx + label.length)),
      );
      if (!_isPlausibleMerchant(value)) continue;
      return _MerchantPick(
        merchant: ReceiptField<String>(
          value: value,
          confidence: FieldConfidence.medium,
          tag: label,
        ),
        product: value,
      );
    }
  }

  for (final RegExp pattern in kMerchantPatterns) {
    final RegExpMatch? m = pattern.firstMatch(text);
    final String value = _cleanValue(m?.group(1) ?? '');
    if (_isPlausibleMerchant(value)) {
      return _MerchantPick(
        merchant: ReceiptField<String>(
          value: value,
          confidence: FieldConfidence.medium,
          tag: '句式',
        ),
        product: _pickProduct(lines),
      );
    }
  }

  return _MerchantPick(
    merchant: const ReceiptField<String>.absent(),
    product: _pickProduct(lines),
  );
}

String? _pickProduct(List<String> lines) {
  for (final String label in kProductLabels) {
    for (final String line in lines) {
      final int idx = line.indexOf(label);
      if (idx < 0) continue;
      final String value = _cutAtStopWord(
        _cleanValue(line.substring(idx + label.length)),
      );
      if (_isPlausibleMerchant(value)) return value;
    }
  }
  return null;
}

/// 去掉标签后面的分隔符。
String _cleanValue(String raw) {
  return raw
      .replaceFirst(RegExp(r'^[\s:：\-—·|、.]+'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

/// OCR 常把"商户 星巴克 金额 12.00"合成一行 → 在下一个标签处截断。
String _cutAtStopWord(String value) {
  var cut = value.length;
  for (final String word in kMerchantStopWords) {
    final int idx = value.indexOf(word);
    if (idx >= 0 && idx < cut) cut = idx;
  }
  return value.substring(0, cut).trim();
}

/// `商户单号` / `商户名称` 这类**复合标签**被 OCR 拆成两行时，剩下的半截不是商户名。
bool _startsWithCompoundSuffix(String value) {
  const List<String> suffixes = <String>[
    '单号',
    '编号',
    '名称',
    '全称',
    '简称',
    '备注',
    '类型',
    '状态',
  ];
  for (final String s in suffixes) {
    if (value.startsWith(s)) return true;
  }
  return false;
}

/// 「扫码付款 / 付款给 X / 二维码收款」这类**动作行**不是商户名（值里带商户）。
bool _looksLikeAction(String value) {
  const List<String> words = <String>[
    '扫码',
    '付款给',
    '付款-',
    '付款－',
    '收款方备注',
    '二维码',
    '转账单号',
  ];
  for (final String w in words) {
    if (value.contains(w)) return true;
  }
  return false;
}

bool _isPlausibleMerchant(String value) {
  // 允许单字商户（微信二维码付款的收款方昵称就有一个字的，如「静」），
  // 但空串 / 超长不算。
  if (value.isEmpty || value.length > 40) return false;
  // 纯数字 / 纯符号：不是商户名
  if (RegExp(r'^[\d\s.,:/：\-+]+$').hasMatch(value)) return false;
  // 只剩一个标签词（"商户 商户"这类 OCR 重叠）
  if (kMerchantStopWords.contains(value)) return false;
  if (kMerchantLabels.contains(value)) return false;
  // 带这些词的整行是"状态 / 时间 / 单号"行，不是商户（微信凭证里它们紧跟在金额后面）
  for (final String word in kMerchantStopWords) {
    if (value.contains(word)) return false;
  }
  if (value.contains('支付时间') || value.contains('交易时间')) return false;
  return true;
}

// ────────────────────────────── 订单号 / 支付方式 ──────────────────────────────

String? _pickOrderNo(List<String> lines) {
  for (final String label in kOrderNoLabels) {
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final int idx = line.indexOf(label);
      if (idx < 0) continue;
      final String rest = line.substring(idx + label.length);
      // 号码可能跟标签同一行，也可能在**下一行**（微信「交易详情」就是这样：
      // `交易单号` / `4500000572202610243956424515` 被 OCR 拆成两行）→ 2026-10-24 真实样本
      final RegExpMatch? m =
          kOrderNoValue.firstMatch(rest) ??
          (i + 1 < lines.length ? kOrderNoValue.firstMatch(lines[i + 1]) : null);
      final String? value = m?.group(0);
      // 长度 < 8 的多半是"订单号：1"这类噪声，不收
      if (value != null && value.length >= 8) return value;
    }
  }
  return null;
}

String? _pickPaymentType(List<String> lines, ReceiptPlatform platform) {
  // 只在带「支付方式 / 付款方式 …」标签的行里找，避免把「账户余额」当成「余额」支付方式
  for (final String line in lines) {
    final bool labelled = kPaymentMethodLabels.any(line.contains);
    if (!labelled) continue;
    for (final ({String type, List<String> words}) rule in kPaymentTypeRules) {
      for (final String word in rule.words) {
        if (line.contains(word)) return rule.type;
      }
    }
  }
  return switch (platform) {
    ReceiptPlatform.wechat => 'wechat',
    ReceiptPlatform.alipay => 'alipay',
    _ => null,
  };
}

// ────────────────────────────── 分类预填 ──────────────────────────────

/// 复用导入链路的分类规则（`category_rules.dart`）：拼一个最小 `ParsedRow` 喂进去，
/// **不复制**那张 33 条规则表。
CategorizeResult _pickCategory({
  required String direction,
  required String merchant,
  required String product,
  required int amountCents,
  required int occurredAtMs,
}) {
  final ParsedRow probe = ParsedRow(
    source: 'screenshot',
    externalId: '',
    occurredAt: occurredAtMs,
    amountCents: amountCents > 0 ? amountCents : 1,
    direction: direction,
    counterparty: merchant,
    product: product,
    method: '',
    status: '',
    unknownStatus: false,
    rawIndex: 0,
  );
  return categorizeRow(probe);
}

// ────────────────────────────── 问题清单 ──────────────────────────────

List<ReceiptIssue> _buildIssues({
  required String text,
  required ReceiptPlatform platform,
  required ReceiptStatus status,
  required ReceiptField<String> direction,
  required _AmountPick amount,
  required _TimePick time,
  required ReceiptField<String> merchant,
}) {
  final List<ReceiptIssue> issues = <ReceiptIssue>[];

  if (status == ReceiptStatus.failed) issues.add(ReceiptIssue.paymentFailed);
  if (status == ReceiptStatus.cancelled) {
    issues.add(ReceiptIssue.paymentCancelled);
  }
  if (status == ReceiptStatus.refund) issues.add(ReceiptIssue.refund);
  if (status == ReceiptStatus.pending) issues.add(ReceiptIssue.pendingPayment);
  if (platform == ReceiptPlatform.unknown) {
    issues.add(ReceiptIssue.unknownPlatform);
  }
  if (direction.isEmpty) issues.add(ReceiptIssue.unknownDirection);

  if (amount.field.isEmpty) {
    issues.add(ReceiptIssue.missingAmount);
  } else if (amount.field.candidates.isNotEmpty) {
    issues.add(ReceiptIssue.multipleAmounts);
  } else if (amount.onlyDiscounted) {
    issues.add(ReceiptIssue.discountedAmount);
  } else if (amount.field.confidence == FieldConfidence.low) {
    issues.add(ReceiptIssue.lowConfidenceAmount);
  }

  if (time.field.isEmpty) {
    issues.add(ReceiptIssue.missingTime);
  } else if (time.yearInferred) {
    issues.add(ReceiptIssue.yearInferred);
  }

  if (merchant.isEmpty) issues.add(ReceiptIssue.missingMerchant);

  // 兜底：整页没有一行像样的中文 / 数字（糊图）—— 按"没读出文字"处理
  if (RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]').hasMatch(text) == false) {
    issues.add(ReceiptIssue.emptyText);
  }

  return issues;
}

// ────────────────────────────── 小工具 ──────────────────────────────

bool _containsAny(String text, List<String> words) {
  for (final String w in words) {
    if (text.contains(w)) return true;
  }
  return false;
}
