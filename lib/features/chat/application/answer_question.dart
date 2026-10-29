/// 把一句中文问题变成一条回答（聊天与旧「问账本」共用的一段编排）。
///
/// 为什么单独抽出来：文字问答的链路（解析意图 → 查账本 → 套模板）**不该绑在某个页面/控制器上**；
/// 现在它同时服务聊天页，将来接本地模型时也只需要在这里多一步「把事实清单交给模型」。
///
/// 口径（与 `docs/spec/SPEC-local-assistant.md` §4 一致）：
/// - 金额只来自既有纯函数，不在这里算新数；
/// - 区间半开 `[start, end)`，`nowMs` 显式传入（可测）；
/// - 纯算术 / 不认识的问题**不去查库**。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../data/providers/book_providers.dart';
import '../../../data/providers/category_providers.dart';
import '../../../data/providers/database.dart';
import '../../assistant/application/finance_answer.dart';
import '../../assistant/application/finance_intent.dart';

/// 回答一个问题。
Future<FinanceAnswer> answerQuestion(
  Ref ref,
  String question, {
  required int nowMs,
}) async {
  final String? bookId = await ref.read(activeBookIdProvider.future);
  if (bookId == null) throw StateError('账本未就绪');

  final List<Category> categories = await ref.read(categoriesProvider.future);
  final FinanceIntent intent = parseFinanceIntent(
    question,
    expenseCategories: <String>[
      for (final Category c in categories)
        if (c.kind == 'expense') c.name,
    ],
    incomeCategories: <String>[
      for (final Category c in categories)
        if (c.kind == 'income') c.name,
    ],
    nowMs: nowMs,
  );

  final Period? window = windowOf(intent);
  if (window == null) {
    return buildFinanceAnswer(intent, FinanceData(nowMs: nowMs));
  }

  final List<TxRow> rows = await ref
      .read(transactionRepositoryProvider)
      .listByRange(bookId, window.startMs, window.endMs);

  int? budget;
  if (intent is BudgetIntent && intent.period.isWholeMonth) {
    final BudgetRow? row = await ref
        .read(budgetRepositoryProvider)
        .getForMonth(bookId, intent.period.year!, intent.period.month!);
    budget = row?.amountCents;
  }

  return buildFinanceAnswer(
    intent,
    FinanceData(
      rows: rows,
      categoryNames: <String, String>{
        for (final Category c in categories) c.id: c.name,
      },
      // 二级 → 父级：问「餐饮」时要把「早餐 / 午餐」的账单也算进去（FR-CAT-03）。
      categoryParents: <String, String>{
        for (final Category c in categories)
          if (c.parentId != null) c.id: c.parentId!,
      },
      budgetCents: budget,
      nowMs: nowMs,
    ),
  );
}
