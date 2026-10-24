/// 截图草稿 → 正式账单（F8.1）—— **唯一写库入口**。
///
/// 复用导入 / 自动记账同一条链路：`TransactionRepository.importTransaction`
/// （`source='screenshot'`、`externalId=OCR 文本指纹`）→ 指纹部分唯一索引天然幂等，
/// 同一张截图重复确认不会记两笔（`ImportDuplicate` 会被翻译成"这笔之前记过了"）。
///
/// ⚠️ 这里**不接受** OCR 原文、不打印金额 —— 只有用户在确认页点过之后才会被调用。
library;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/import/application/bill_importer.dart'
    show BillCategoryMaps;

/// 写库结果。
sealed class ReceiptWriteResult {
  const ReceiptWriteResult();
}

/// 新记了一笔。
final class ReceiptWritten extends ReceiptWriteResult {
  const ReceiptWritten(this.tx);

  final TxRow tx;
}

/// 指纹命中已有流水：**没写**，返回那一笔。
final class ReceiptDuplicate extends ReceiptWriteResult {
  const ReceiptDuplicate(this.existing);

  final TxRow existing;
}

/// 写失败（参数非法 / 分类不存在 / 数据库异常）。
final class ReceiptWriteFailed extends ReceiptWriteResult {
  const ReceiptWriteFailed(this.message);

  final String message;
}

/// 把分类名解析成 id（`(kind, name)` 二元组 —— 同一账本里「其他」有两个）。
///
/// 规则与 `bill_importer.dart` 的 `importRows` 一致：先精确命中，再退「其他 / 未分类」，
/// 最后退该方向第一个分类；都没有则返回 null（调用方拦下并提示"先去建分类"）。
String? resolveReceiptCategoryId(
  BillCategoryMaps maps,
  String type,
  String name,
) {
  final Map<String, String> map = type == 'income' ? maps.income : maps.expense;
  final String? exact = map[name];
  if (exact != null) return exact;
  const List<String> fallbackNames = <String>['其他', '其他支出', '未分类'];
  for (final String n in fallbackNames) {
    final String? id = map[n];
    if (id != null) return id;
  }
  return map.isEmpty ? null : map.values.first;
}

/// 写入一笔截图账。
///
/// 入参全部来自**用户在确认页看到并确认过的值**（不是 OCR 原始输出）。
Future<ReceiptWriteResult> writeReceipt(
  TransactionRepository repo, {
  required String bookId,
  required String accountId,
  required String type,
  required int amountCents,
  required int occurredAtMs,
  required String categoryId,
  required String note,
  required String textHash,
}) async {
  if (amountCents <= 0) {
    return const ReceiptWriteFailed('金额必须大于 0');
  }
  if (type != 'expense' && type != 'income') {
    return ReceiptWriteFailed('收支类型不合法：$type');
  }
  if (categoryId.isEmpty) {
    return const ReceiptWriteFailed('还没有可用分类，请先到「分类管理」添加');
  }
  try {
    final ImportResult result = await repo.importTransaction(
      bookId: bookId,
      accountId: accountId,
      type: type,
      amountCents: amountCents,
      occurredAt: occurredAtMs,
      categoryId: categoryId,
      note: note,
      source: 'screenshot',
      externalId: textHash,
    );
    return switch (result) {
      ImportOk(tx: final TxRow tx) => ReceiptWritten(tx),
      ImportDuplicate(existingTx: final TxRow tx) => ReceiptDuplicate(tx),
    };
  } catch (e) {
    return ReceiptWriteFailed(e.toString());
  }
}

/// 找"疑似同一笔"的已有流水（**只提示，不阻断**）。
///
/// 判据（Prompt §4：不能仅凭金额相同就判重复）：
/// 同一账本 + 同方向 + 金额相同 + 发生时间在 ±15 分钟内。
/// 时间窗是**必要的**：同金额的日常消费（每天一杯咖啡）很常见，只看金额会天天误报。
Future<List<TxRow>> findSimilarReceipts(
  TransactionRepository repo, {
  required String bookId,
  required String type,
  required int amountCents,
  required int occurredAtMs,
  int windowMs = 15 * 60 * 1000,
  int limit = 3,
}) async {
  if (amountCents <= 0) return const <TxRow>[];
  final List<TxRow> rows = await repo.listByRange(
    bookId,
    occurredAtMs - windowMs,
    occurredAtMs + windowMs + 1,
  );
  final List<TxRow> out = <TxRow>[];
  for (final TxRow row in rows) {
    if (row.type != type) continue;
    if (row.amountCents != amountCents) continue;
    out.add(row);
    if (out.length >= limit) break;
  }
  return out;
}
