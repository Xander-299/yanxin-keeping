/// 截图识别的中间结果（F8.1）。
///
/// 为什么需要这一层：现有 `ParsedRow`（导入 / 自动记账共用）是"要么入账要么丢弃"的
/// 自动路径产物，**没有置信度概念**。截图识别必须能表达
/// 「金额可能是原价不是实付，请用户确认」—— 所以引入草稿层。
///
/// 草稿**只存在于内存**：确认后走 `TransactionRepository.importTransaction`
/// （source='screenshot'），不落任何新表（schema 仍是 v3）。
library;

/// 截图来源。
enum ReceiptPlatform { wechat, alipay, bank, order, unknown }

extension ReceiptPlatformX on ReceiptPlatform {
  String get label => switch (this) {
    ReceiptPlatform.wechat => '微信支付',
    ReceiptPlatform.alipay => '支付宝',
    ReceiptPlatform.bank => '银行卡',
    ReceiptPlatform.order => '购物订单',
    ReceiptPlatform.unknown => '未识别来源',
  };
}

/// 交易状态（决定「能不能记、按什么方向记」）。
enum ReceiptStatus { ok, refund, failed, cancelled, pending, unknown }

extension ReceiptStatusX on ReceiptStatus {
  String get label => switch (this) {
    ReceiptStatus.ok => '交易成功',
    ReceiptStatus.refund => '退款',
    ReceiptStatus.failed => '支付失败',
    ReceiptStatus.cancelled => '交易已取消',
    ReceiptStatus.pending => '待付款',
    ReceiptStatus.unknown => '状态不明',
  };
}

/// 单字段可信度。
///
/// 阈值不是拍脑袋定的：见 `test/features/receipt/receipt_parse_test.dart` 里
/// 每一条样本对应的期望值（改了规则就要同步改期望，别只改规则）。
enum FieldConfidence { high, medium, low, absent }

extension FieldConfidenceX on FieldConfidence {
  /// 需要用户在确认页多看一眼（低可信 / 没识别到）。
  bool get needsConfirm =>
      this == FieldConfidence.low || this == FieldConfidence.absent;

  String get label => switch (this) {
    FieldConfidence.high => '确定',
    FieldConfidence.medium => '较可信',
    FieldConfidence.low => '待确认',
    FieldConfidence.absent => '未识别',
  };
}

/// 识别过程中发现的"需要人看一眼"的问题。
enum ReceiptIssue {
  emptyText,
  missingAmount,
  multipleAmounts,
  discountedAmount,
  lowConfidenceAmount,
  missingTime,
  yearInferred,
  missingMerchant,
  paymentFailed,
  paymentCancelled,
  pendingPayment,
  refund,
  unknownPlatform,
  unknownDirection,
}

extension ReceiptIssueX on ReceiptIssue {
  /// **阻断入账**：这几种情况下确认页不允许直接保存（必须先改或换图）。
  bool get blocking => switch (this) {
    ReceiptIssue.emptyText ||
    ReceiptIssue.missingAmount ||
    ReceiptIssue.paymentFailed ||
    ReceiptIssue.paymentCancelled => true,
    _ => false,
  };

  /// 给用户看的一句话（说清"发生了什么 + 该怎么办"）。
  String get message => switch (this) {
    ReceiptIssue.emptyText => '这张图没读出文字，换一张更清晰的截图',
    ReceiptIssue.missingAmount => '没识别到金额，请手动填写',
    ReceiptIssue.multipleAmounts => '识别到多个金额，请确认哪一个是实付金额',
    ReceiptIssue.discountedAmount => '只识别到原价 / 优惠金额，请核对实付',
    ReceiptIssue.lowConfidenceAmount => '金额把握不大，请核对一下',
    ReceiptIssue.missingTime => '没识别到交易时间，已按今天填写',
    ReceiptIssue.yearInferred => '截图里没有年份，年份是按日期推算的',
    ReceiptIssue.missingMerchant => '没识别到商户名，可手动补一条备注',
    ReceiptIssue.paymentFailed => '这张图是支付失败，不能记账',
    ReceiptIssue.paymentCancelled => '这笔交易已取消，不能记账',
    ReceiptIssue.pendingPayment => '这笔还没付款，确认后再记',
    ReceiptIssue.refund => '这像是退款：可改为「收入」记账，或直接不记',
    ReceiptIssue.unknownPlatform => '没认出是哪个平台，字段请核对',
    ReceiptIssue.unknownDirection => '没判断出是支出还是收入，请选一下',
  };
}

/// 一个字段：值 + 可信度 + 其它候选（用户可在确认页一键切换）。
class ReceiptField<T> {
  const ReceiptField({
    this.value,
    this.confidence = FieldConfidence.absent,
    List<T>? candidates,
    this.tag = '',
  }) : candidates = candidates ?? const <Never>[];

  const ReceiptField.absent()
    : value = null,
      confidence = FieldConfidence.absent,
      candidates = const <Never>[],
      tag = '';

  final T? value;
  final FieldConfidence confidence;

  /// 候选值（金额 / 时间会命中多个时全部保留，顺序 = 规则优先级）。
  final List<T> candidates;

  /// 命中的规则名（"实付" / "¥" / "独立行" …），只用于确认页的"识别依据"。
  final String tag;

  bool get isEmpty => value == null;
}

/// 一次截图识别的完整草稿。
class ReceiptDraft {
  const ReceiptDraft({
    required this.platform,
    required this.status,
    required this.direction,
    required this.amountCents,
    required this.occurredAtMs,
    required this.merchant,
    required this.categoryName,
    required this.issues,
    required this.textHash,
    required this.rawText,
    this.orderNo,
    this.paymentType,
    this.ocrElapsedMs = 0,
  });

  final ReceiptPlatform platform;
  final ReceiptStatus status;

  /// `expense` | `income`（未被识别时 `confidence = absent`，确认页默认支出）。
  final ReceiptField<String> direction;

  /// 金额（**正整数分**，与全项目一致）。
  final ReceiptField<int> amountCents;

  /// 交易时间（毫秒 epoch，本地时区）。
  final ReceiptField<int> occurredAtMs;

  final ReceiptField<String> merchant;

  /// 预填分类名（来自 `categorizeRow`，用户可改）。
  final ReceiptField<String> categoryName;

  /// 订单号 / 交易号（存在时拼进指纹，让"同一张图"与"同一笔交易"都能去重）。
  final String? orderNo;

  /// 支付方式推断出的账户类型（`accounts.type`；null = 没推断出来）。
  final String? paymentType;

  final List<ReceiptIssue> issues;

  /// 归一化 OCR 文本的 sha1（去重用的 `externalId`）。
  final String textHash;

  /// 归一化后的 OCR 文本（**只在确认页展示，不落库、不打日志**）。
  final String rawText;

  final int ocrElapsedMs;

  /// 阻断性问题（有则不允许保存）。
  List<ReceiptIssue> get blockers =>
      issues.where((ReceiptIssue i) => i.blocking).toList(growable: false);

  /// 提醒性问题（可保存，但要让人看见）。
  List<ReceiptIssue> get warnings =>
      issues.where((ReceiptIssue i) => !i.blocking).toList(growable: false);

  bool get canWrite =>
      blockers.isEmpty && (amountCents.value ?? 0) > 0;

  /// 金额候选（去重后、按规则优先级；含当前值）。
  List<int> get amountChoices {
    final List<int> out = <int>[];
    final int? current = amountCents.value;
    if (current != null && current > 0) out.add(current);
    for (final int c in amountCents.candidates) {
      if (c > 0 && !out.contains(c)) out.add(c);
    }
    return out;
  }

  /// 交易时间的推算是"年份不明"还是"完全没有"。
  bool get hasTime => occurredAtMs.value != null;
}
