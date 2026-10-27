/// 「问账本」的会话状态与编排（M1：**没有模型也能用**）。
///
/// 一条问题的完整链路：
/// ```
/// 文本 → parseFinanceIntent（纯函数，选区间与口径）
///      → 仓储取数（listByRange / getForMonth，drift 仍是唯一数据源）
///      → buildFinanceAnswer（纯函数，复用 summarize / categoryBreakdown / buildBudgetView）
///      → 追加到会话
/// ```
/// 刻意**没有**的东西（M1 的边界）：
/// - 没有模型、没有联网、没有任何"猜"的分支：不认识的问题直接说不认识；
/// - 不缓存财务数字（每次现查），避免「记完一笔再问还是旧数」这类过期快照；
/// - 不把问题或金额写日志（金融隐私，见 HANDOFF 不变量）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../data/providers/book_providers.dart';
import '../../../data/providers/category_providers.dart';
import '../../../data/providers/database.dart';
import 'finance_answer.dart';
import 'finance_intent.dart';

/// 会话里的一轮：用户问 + 系统答（或错误）。
class AssistantTurn {
  const AssistantTurn({
    required this.question,
    this.answer,
    this.error,
    this.pending = false,
  });

  final String question;
  final FinanceAnswer? answer;
  final String? error;

  /// 正在查询（UI 显示"查账本中…"）。
  final bool pending;
}

/// 会话快照。
class AssistantState {
  const AssistantState({this.turns = const <AssistantTurn>[], this.busy = false});

  final List<AssistantTurn> turns;

  /// 有请求在飞：期间拒绝新问题（避免并发查同一段流水）。
  final bool busy;

  AssistantState copyWith({List<AssistantTurn>? turns, bool? busy}) => AssistantState(
    turns: turns ?? this.turns,
    busy: busy ?? this.busy,
  );
}

/// 会话状态。
final assistantProvider = NotifierProvider<AssistantController, AssistantState>(
  AssistantController.new,
);

class AssistantController extends Notifier<AssistantState> {
  @override
  AssistantState build() => const AssistantState();

  /// 问一句。[nowMs] 仅供测试固定"现在"（生产走真实时钟）。
  Future<void> ask(String raw, {int? nowMs}) async {
    final String question = raw.trim();
    if (question.isEmpty || state.busy) return;

    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final List<AssistantTurn> withQuestion = <AssistantTurn>[
      ...state.turns,
      AssistantTurn(question: question, pending: true),
    ];
    state = AssistantState(turns: withQuestion, busy: true);

    try {
      final FinanceAnswer answer = await _answerFor(question, now);
      _settle(AssistantTurn(question: question, answer: answer));
    } catch (_) {
      // 不把异常原文抛给用户（可能含 SQL / 路径），也不打日志
      _settle(AssistantTurn(question: question, error: '查询失败了，稍后再试一次。'));
    }
  }

  /// 清空会话。
  void clear() {
    state = const AssistantState();
  }

  // ────────────────────────────── 内部 ──────────────────────────────

  Future<FinanceAnswer> _answerFor(String question, int now) async {
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
      nowMs: now,
    );

    // 纯算术 / 不认识 → 不需要任何账本数据
    final Period? window = windowOf(intent);
    if (window == null) {
      return buildFinanceAnswer(intent, FinanceData(nowMs: now));
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
        budgetCents: budget,
        nowMs: now,
      ),
    );
  }

  void _settle(AssistantTurn turn) {
    final List<AssistantTurn> turns = <AssistantTurn>[...state.turns];
    if (turns.isNotEmpty) turns.removeLast(); // 去掉 pending 占位
    turns.add(turn);
    state = AssistantState(turns: turns, busy: false);
  }
}
