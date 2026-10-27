/// 「问账本」页（M1）：一句话问，答案里的数字全部来自账本。
///
/// 三条产品口径（写死在这里，别改文案时忘了）：
/// 1. **本地计算 · 不上传**：没有网络调用，也没有模型 —— 现在就是规则 + 账本查询；
/// 2. **不装模型也能用**：示例问题点一下就能答，不需要任何下载；
/// 3. **不认识就说不认识**：答不上来时给「可以这样问」的示例，绝不编一个数。
///
/// 本地模型的「AI 解读」是后续版本的可选件（`docs/dev/llm-benchmark.md`）——
/// 到那时这里只是多一个开关，页面结构不用变。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

import '../application/assistant_controller.dart';
import '../application/finance_answer.dart';

/// 问账本。
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 会话一变就滚到底：回答卡片比问题高，不滚会看不到结论
    ref.listenManual<AssistantState>(assistantProvider, (
      AssistantState? _,
      AssistantState next,
    ) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _ask(String question) {
    if (question.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    _input.clear();
    ref.read(assistantProvider.notifier).ask(question);
  }

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final AssistantState state = ref.watch(assistantProvider);

    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        title: const Text('问账本'),
        actions: <Widget>[
          if (state.turns.isNotEmpty)
            IconButton(
              tooltip: '清空',
              onPressed: () => ref.read(assistantProvider.notifier).clear(),
              icon: Icon(Icons.refresh_rounded, color: p.ink2, size: 20),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: <Widget>[
                  if (state.turns.isEmpty)
                    _Welcome(onAsk: _ask)
                  else
                    for (final AssistantTurn turn in state.turns) ...<Widget>[
                      _QuestionBubble(text: turn.question),
                      const SizedBox(height: 8),
                      if (turn.pending)
                        const _PendingCard()
                      else if (turn.error != null)
                        _ErrorCard(message: turn.error!)
                      else if (turn.answer != null)
                        _AnswerCard(answer: turn.answer!, onAsk: _ask),
                      const SizedBox(height: 14),
                    ],
                ],
              ),
            ),
            _InputBar(
              controller: _input,
              busy: state.busy,
              onSubmit: () => _ask(_input.text),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────── 空态 / 引导 ──────────────────────────────

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAsk});

  final void Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ToonCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.brandTint,
                      borderRadius: BorderRadius.circular(13),
                      border: p.inkBorder(on: p.brandTint),
                      boxShadow: p.hard(d: 2),
                    ),
                    child: Icon(Icons.forum_outlined, size: 20, color: p.brandInk),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '一句话问自己的账本',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '数字由账本直接算出来，不联网、不上传。'
                '点下面的例子试试 —— 也可以自己打字问。',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String q in kExampleQuestions)
                    _SuggestionChip(label: q, onTap: () => onAsk(q)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _HintNote(
          text: '现在用的是「规则 + 账本计算」：算得准，但不会聊天。'
              '本地模型的 AI 解读是后续可选安装的能力，不装也能用。',
        ),
      ],
    );
  }
}

// ────────────────────────────── 会话气泡 ──────────────────────────────

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: p.brandTint,
          borderRadius: BorderRadius.circular(14),
          border: p.inkBorder(on: p.brandTint),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: p.brandInk,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard();

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.ink3),
          ),
          const SizedBox(width: 10),
          Text(
            '正在查账本…',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink2),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonCard(
      color: p.redTint,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.redInk,
          height: 1.5,
        ),
      ),
    );
  }
}

// ────────────────────────────── 回答卡 ──────────────────────────────

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, required this.onAsk});

  final FinanceAnswer answer;
  final void Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Color accent = switch (answer.tone) {
      AnswerTone.warn => p.red,
      AnswerTone.good => p.green,
      AnswerTone.neutral => p.brandDeep,
    };

    return ToonCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  answer.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: p.ink3,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          if (answer.headline != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              answer.headline!,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: p.ink,
                height: 1.1,
              ),
            ),
            if (answer.headlineNote != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                answer.headlineNote!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink3,
                ),
              ),
            ],
          ],
          if (answer.facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(height: 1, color: p.line),
            const SizedBox(height: 8),
            for (final AnswerFact f in answer.facts) _FactRow(fact: f),
          ],
          const SizedBox(height: 10),
          Text(
            answer.narrative,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink2,
              height: 1.65,
            ),
          ),
          if (answer.suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String s in answer.suggestions)
                  _SuggestionChip(label: s, onTap: () => onAsk(s)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final AnswerFact fact;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              fact.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.ink2,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                fact.value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              if (fact.note != null)
                Text(
                  fact.note!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: p.ink3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────── 小件 ──────────────────────────────

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: p.canvas2,
          borderRadius: BorderRadius.circular(999),
          border: p.inkBorder(w: Tok.bw * 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: p.ink2,
          ),
        ),
      ),
    );
  }
}

class _HintNote extends StatelessWidget {
  const _HintNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.lock_outline_rounded, size: 13, color: p.ink3),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: p.ink3,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.ink, width: Tok.bw)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: p.canvas2,
                borderRadius: BorderRadius.circular(12),
                border: p.inkBorder(w: Tok.bw * 0.8),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
                decoration: InputDecoration(
                  hintText: '问一句，比如「这个月餐饮花了多少」',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.ink3,
                  ),
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ToonButton(
            label: '问',
            small: true,
            onPressed: busy ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}
