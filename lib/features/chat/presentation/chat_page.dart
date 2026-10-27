/// 聊天页：**文字问账本 + 图片记账**合成一条流（首页入口卡的落点）。
///
/// 与旧页面的关系：
/// - 文字问答沿用 M1 的意图解析 + 模板回答（`answerQuestion`）；
/// - 图片记账沿用 F8.1 的 OCR + 规则解析 + `importTransaction`，只是把「三步页」压成
///   **聊天里的一张待确认卡片**（确认前不写库）。
///
/// 三条产品口径不变：
/// 1. 图片与文字都只在本机处理，没有网络调用；
/// 2. 数字来自账本（文字）或用户确认（图片），绝不编；
/// 3. 不认识 / 识别失败都明说，不猜。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/platform/media_picker.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/data/providers/account_providers.dart';
import 'package:yanxin/data/providers/category_providers.dart';
import 'package:yanxin/features/assistant/application/finance_answer.dart';
import 'package:yanxin/features/receipt/application/receipt_draft.dart';
import 'package:yanxin/features/record/application/amount_input.dart';
import 'package:yanxin/features/record/presentation/widgets/account_picker_sheet.dart';
import 'package:yanxin/features/record/presentation/widgets/category_picker.dart';
import 'package:yanxin/features/record/presentation/widgets/date_picker_sheet.dart';

import '../application/chat_controller.dart';

part 'widgets/chat_bubbles.dart';
part 'widgets/receipt_card.dart';

/// `2026-10-24 16:28`（本地时区）—— 卡片与结果气泡共用。
String _formatDateTime(int ms) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// 打开聊天页时的落点（首页入口卡带过来的意图）。
class ChatLaunch {
  const ChatLaunch({this.openImagePicker = false, this.question});

  /// 进入后立刻弹相册（首页点了 📷）。
  final bool openImagePicker;

  /// 进入后立刻问这一句（首页点了示例 chip）。
  final String? question;
}

/// 聊天页。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.launch});

  final ChatLaunch? launch;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ref.listenManual<ChatState>(chatProvider, (ChatState? _, ChatState next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    });
    final ChatLaunch? launch = widget.launch;
    if (launch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final String? question = launch.question;
        if (question != null) _ask(question);
        if (launch.openImagePicker) _pickImage();
      });
    }
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
      _scroll.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _ask(String question) {
    if (question.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    _input.clear();
    ref.read(chatProvider.notifier).ask(question);
  }

  Future<void> _pickImage() async {
    String? path;
    try {
      path = await ref.read(mediaPickerProvider).pickImage();
    } on MediaPickFailure catch (e) {
      if (!mounted) return;
      _toast('这台设备打不开相册：${e.code}');
      return;
    }
    if (path == null || path.isEmpty || !mounted) return; // 用户取消
    await ref.read(chatProvider.notifier).sendImage(path);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final ChatState state = ref.watch(chatProvider);

    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        title: const Text('记一笔 / 问一句'),
        actions: <Widget>[
          if (state.messages.isNotEmpty)
            IconButton(
              tooltip: '清空',
              onPressed: () => ref.read(chatProvider.notifier).clear(),
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
                  if (state.messages.isEmpty)
                    _Welcome(onAsk: _ask, onPickImage: _pickImage)
                  else
                    for (int i = 0; i < state.messages.length; i++) ...<Widget>[
                      _MessageView(message: state.messages[i], index: i),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
            _InputBar(
              controller: _input,
              busy: state.busy,
              onSend: () => _ask(_input.text),
              onPickImage: state.busy ? null : _pickImage,
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────── 消息分发 ──────────────────────────────

class _MessageView extends ConsumerWidget {
  const _MessageView({required this.message, required this.index});

  final ChatMessage message;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (message) {
      UserTextMessage(:final String text) => _QuestionBubble(text: text, icon: Icons.chat_bubble_outline_rounded),
      UserImageMessage() => const _QuestionBubble(text: '发了一张账单截图', icon: Icons.image_outlined),
      AnswerMessage(:final FinanceAnswer answer) => _AnswerCard(answer: answer, onAsk: (String q) {
        ref.read(chatProvider.notifier).ask(q);
      }),
      NoticeMessage(:final String text, :final NoticeTone tone) => _NoticeBubble(text: text, tone: tone),
      ReceiptMessage() => _ReceiptCard(message: message as ReceiptMessage, index: index),
      _ => const SizedBox.shrink(),
    };
  }
}

// ────────────────────────────── 空态 ──────────────────────────────

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAsk, required this.onPickImage});

  final void Function(String) onAsk;
  final Future<void> Function() onPickImage;

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
                      '说吧：问一句，或发张截图',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '问账本 → 数字直接算给你；发支付 / 订单截图 → 识别成待确认账单，'
                '你点头才记账。全部在本机完成。',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              ToonButton(
                block: true,
                icon: Icons.photo_library_outlined,
                label: '发一张账单截图',
                onPressed: onPickImage,
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

// ────────────────────────────── 输入栏 ──────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onPickImage,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final Future<void> Function()? onPickImage;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.ink, width: Tok.bw)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          IconButton(
            tooltip: '发账单截图',
            onPressed: onPickImage == null ? null : () => onPickImage!(),
            icon: Icon(Icons.photo_camera_outlined, color: p.ink2),
          ),
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
                onSubmitted: (_) => onSend(),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink),
                decoration: InputDecoration(
                  hintText: '问一句，或点左边发截图',
                  hintStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink3),
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
          const SizedBox(width: 6),
          ToonButton(label: '发送', small: true, onPressed: busy ? null : onSend),
        ],
      ),
    );
  }
}
