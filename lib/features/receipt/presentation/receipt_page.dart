/// 截图记账（F8.1）：选图 → 端上识别 + 规则解析 → 用户确认 → 复用现有业务写库。
///
/// 三步页（与 `/import` 同构）：
///   ① 选图（系统相册 / SAF，**不需要任何运行时权限**）
///   ② 核对（字段可改、低可信高亮、多金额可切换、识别原文可展开）
///   ③ 结果（成功 / 之前记过了 / 失败）
///
/// 三条硬约束：
/// 1. **图片与文字都只在本机**：识别在 Kotlin 侧用 bundled ML Kit 完成，解析在 Dart 侧，
///    全链路没有网络调用（release 包也没有 `INTERNET` 权限）。
/// 2. **未确认绝不写库**：只有点「确认记账」才会调 `writeReceipt`。
/// 3. **不确定就交给用户**：解析不出金额 / 是退款 / 是失败单，一律在界面上说清楚，
///    绝不猜一个数字写进去。
library;

import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/platform/media_picker.dart';
import 'package:yanxin/core/providers/after_write.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/data/providers/account_providers.dart';
import 'package:yanxin/data/providers/book_providers.dart';
import 'package:yanxin/data/providers/category_providers.dart';
import 'package:yanxin/data/providers/database.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/receipt/application/receipt_draft.dart';
import 'package:yanxin/features/receipt/application/receipt_write.dart';
import 'package:yanxin/features/receipt/data/mlkit_ocr_engine.dart';
import 'package:yanxin/features/receipt/data/ocr_engine.dart';
import 'package:yanxin/features/receipt/data/receipt_parse.dart';
import 'package:yanxin/features/record/application/amount_input.dart';
import 'package:yanxin/features/record/presentation/widgets/account_picker_sheet.dart';
import 'package:yanxin/features/record/presentation/widgets/amount_keyboard.dart';
import 'package:yanxin/features/record/presentation/widgets/category_picker.dart';
import 'package:yanxin/features/record/presentation/widgets/date_picker_sheet.dart';

part 'widgets/receipt_bits.dart';

/// 截图记账页。
class ReceiptPage extends ConsumerStatefulWidget {
  const ReceiptPage({super.key, this.pickImageOverride, this.nowMsOverride});

  /// 测试注入：返回本地图片路径（绕过系统相册），返回 null = 用户取消。
  final Future<String?> Function()? pickImageOverride;

  /// 测试注入：固定"现在"（让"缺年份按今年推算"这类规则可复现）。
  final int? nowMsOverride;

  @override
  ConsumerState<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends ConsumerState<ReceiptPage> {
  bool _recognizing = false;
  bool _saving = false;
  String? _error;

  String? _imagePath;
  ReceiptDraft? _draft;
  int _ocrElapsedMs = 0;
  List<TxRow> _similar = const <TxRow>[];

  // ── 用户可编辑的确认字段（初值来自草稿，用户改过就以用户为准） ──
  String _type = 'expense';
  String _amount = '';
  String? _categoryId;
  String? _accountId;
  int _occurredAtMs = 0;
  final TextEditingController _note = TextEditingController();

  bool _showRaw = false;
  ReceiptWriteResult? _result;

  int get _nowMs =>
      widget.nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;

  int get _step => _result != null ? 3 : (_draft != null ? 2 : 1);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  // ────────────────────────────── 选图 + 识别 ──────────────────────────────

  Future<void> _pickAndRecognize() async {
    if (_recognizing) return;
    setState(() {
      _recognizing = true;
      _error = null;
    });
    try {
      final String? path = await _pickImage();
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        setState(() => _recognizing = false);
        return; // 用户取消
      }
      final OcrResult ocr = await ref.read(ocrEngineProvider).recognize(path);
      final ReceiptDraft draft = parseReceipt(ocr.lineTexts, nowMs: _nowMs);
      await _applyDraft(draft, path: path, elapsedMs: ocr.elapsedMs);
    } on OcrFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = '识别失败了，换一张或者手动记一笔';
      });
    }
  }

  Future<String?> _pickImage() async {
    if (widget.pickImageOverride != null) return widget.pickImageOverride!();
    // 走自家平台通道（系统 Photo Picker），不经 file_picker —— 见 core/platform/media_picker.dart
    try {
      return await ref.read(mediaPickerProvider).pickImage();
    } on MediaPickFailure catch (e) {
      throw OcrFailure('unsupported_platform', '${e.code}: ${e.message}');
    }
  }

  /// 把草稿填进"可编辑字段"，并顺手查一下有没有疑似同一笔。
  Future<void> _applyDraft(
    ReceiptDraft draft, {
    required String path,
    required int elapsedMs,
  }) async {
    final List<Category> categories =
        ref.read(categoriesProvider).value ?? const <Category>[];
    final List<Account> accounts =
        ref.read(accountsProvider).value ?? const <Account>[];
    final String type = draft.direction.value ?? 'expense';
    final String? categoryId = _matchCategory(
      categories,
      type,
      draft.categoryName.value,
    );
    final String? accountId = _matchAccount(accounts, draft.paymentType);
    final int occurredAt = draft.occurredAtMs.value ?? _nowMs;
    final int? amountCents = draft.amountCents.value;

    List<TxRow> similar = const <TxRow>[];
    final String? bookId = ref.read(activeBookIdProvider).value;
    if (bookId != null && amountCents != null && amountCents > 0) {
      similar = await findSimilarReceipts(
        ref.read(transactionRepositoryProvider),
        bookId: bookId,
        type: type,
        amountCents: amountCents,
        occurredAtMs: occurredAt,
      );
    }
    if (!mounted) return;
    setState(() {
      _recognizing = false;
      _draft = draft;
      _imagePath = path;
      _ocrElapsedMs = elapsedMs;
      _type = type;
      _amount = amountCents == null ? '' : centsToYuan(amountCents);
      _categoryId = categoryId;
      _accountId = accountId;
      _occurredAtMs = occurredAt;
      _note.text = draft.merchant.value ?? '';
      _similar = similar;
      _showRaw = false;
    });
  }

  /// 分类名 → id（同名「其他」有两个，必须按 kind 收窄）。
  String? _matchCategory(List<Category> categories, String kind, String? name) {    final List<Category> sameKind = categories
        .where((Category c) => c.kind == kind)
        .toList(growable: false);
    if (sameKind.isEmpty) return null;
    for (final Category c in sameKind) {
      if (c.name == name) return c.id;
    }
    for (final Category c in sameKind) {
      if (c.name == '其他') return c.id;
    }
    return sameKind.first.id;
  }

  /// 按 id 取分类（不存在返回 null —— 用户可能刚把这个分类删了）。
  Category? _categoryById(List<Category> categories, String? id) {
    if (id == null) return null;
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 支付方式 → 账户（找不到匹配类型就沿用"第一个账户"，与记一笔页一致）。
  String? _matchAccount(List<Account> accounts, String? paymentType) {    if (accounts.isEmpty || paymentType == null) return null;
    for (final Account a in accounts) {
      if (a.type == paymentType) return a.id;
    }
    return null;
  }

  Account? _effectiveAccount(List<Account> accounts) {
    if (accounts.isEmpty) return null;
    for (final Account a in accounts) {
      if (a.id == _accountId) return a;
    }
    return accounts.first;
  }

  // ────────────────────────────── 交互 ──────────────────────────────

  Future<void> _pickCategory(List<Category> all) async {
    final Category? picked = await showCategoryPicker(
      context,
      categories: all,
      kind: _type,
      selectedId: _categoryId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked.id;
      _type = picked.kind;
    });
  }

  Future<void> _pickAccount(List<Account> accounts) async {
    if (accounts.isEmpty) {
      _toast('账本里还没有账户');
      return;
    }
    final Account? picked = await showAccountPicker(
      context,
      accounts: accounts,
      selectedId: _effectiveAccount(accounts)?.id,
    );
    if (picked == null || !mounted) return;
    setState(() => _accountId = picked.id);
  }

  Future<void> _pickDate() async {
    final DateTime initial = DateTime.fromMillisecondsSinceEpoch(_occurredAtMs);
    final DateTime? picked = await showDatePickerSheet(context, initial: initial);
    if (picked == null || !mounted) return;
    setState(() {
      _occurredAtMs = DateTime(
        picked.year,
        picked.month,
        picked.day,
        initial.hour,
        initial.minute,
      ).millisecondsSinceEpoch;
    });
  }

  Future<void> _save() async {
    final ReceiptDraft? draft = _draft;
    if (draft == null || _saving) return;
    if (!isParsableAmount(_amount) || yuanToCents(_amount) <= 0) {
      _toast('请填写金额');
      return;
    }
    if (_categoryId == null) {
      _toast('请选择分类');
      return;
    }
    final List<Account> accounts =
        ref.read(accountsProvider).value ?? const <Account>[];
    final Account? account = _effectiveAccount(accounts);
    if (account == null) {
      _toast('账本里还没有账户');
      return;
    }
    final String? bookId = await ref.read(activeBookIdProvider.future);
    if (bookId == null || !mounted) {
      _toast('账本还没就绪，稍后再试');
      return;
    }

    setState(() => _saving = true);
    final ReceiptWriteResult result = await writeReceipt(
      ref.read(transactionRepositoryProvider),
      bookId: bookId,
      accountId: account.id,
      type: _type,
      amountCents: yuanToCents(_amount),
      occurredAtMs: _occurredAtMs,
      categoryId: _categoryId!,
      note: _note.text.trim(),
      textHash: draft.textHash,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _result = result;
    });
    if (result is ReceiptWritten) {
      refreshAfterWriteFromWidget(ref);
    }
  }

  Future<void> _goToLedger() async {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(_occurredAtMs);
    await ref.read(ledgerProvider.notifier).jumpToMonth(d.year, d.month);
    if (!mounted) return;
    context.go('/');
  }

  void _resetToPick() {
    setState(() {
      _result = null;
      _draft = null;
      _imagePath = null;
      _error = null;
      _similar = const <TxRow>[];
      _amount = '';
      _categoryId = null;
      _accountId = null;
      _note.text = '';
      _showRaw = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ────────────────────────────── 构建 ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final List<Category> categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final List<Account> accounts =
        ref.watch(accountsProvider).value ?? const <Account>[];

    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        title: const Text('截图记账'),
        leading: BackButton(
          onPressed: () {
            if (_step == 1) {
              context.pop();
            } else {
              _resetToPick();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ReceiptStepBar(step: _step),
            Expanded(
              child: switch (_step) {
                1 => _buildPickBody(context),
                2 => _buildConfirmBody(context, categories, accounts),
                _ => _buildResultBody(context),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── 第 1 步：选图 ──

  Widget _buildPickBody(BuildContext context) {
    final ToonPalette p = context.toon;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        ToonCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.brandTint,
                      borderRadius: BorderRadius.circular(14),
                      border: p.inkBorder(on: p.brandTint),
                      boxShadow: p.hard(d: 2),
                    ),
                    child: Icon(
                      Icons.document_scanner_outlined,
                      size: 22,
                      color: p.brandDeep,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '选一张支付截图',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '支持微信支付 / 支付宝 / 银行卡短信 / 购物订单的截图。'
                '识别在手机本地完成，图片不会上传。',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              ToonButton(
                block: true,
                icon: Icons.photo_library_outlined,
                label: _recognizing ? '识别中…' : '从相册选一张',
                onPressed: _recognizing ? null : _pickAndRecognize,
              ),
              const SizedBox(height: 10),
              Text(
                '识别后先给你核对，确认了才会记账',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 14),
          _ReceiptNotice(
            text: _error!,
            kind: _ReceiptNoticeKind.error,
          ),
        ],
        const SizedBox(height: 14),
        const _ReceiptNotice(
          text: '识别不出金额时不会自动记账 —— 你可以手动填，或者直接用「记一笔」。',
          kind: _ReceiptNoticeKind.tip,
        ),
      ],
    );
  }

  // ── 第 2 步：核对 ──

  Widget _buildConfirmBody(
    BuildContext context,
    List<Category> categories,
    List<Account> accounts,
  ) {
    final ToonPalette p = context.toon;
    final ReceiptDraft draft = _draft!;
    final Category? selectedCategory = _categoryById(categories, _categoryId);
    final Account? selectedAccount = _effectiveAccount(accounts);
    final List<int> choices = draft.amountChoices;

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeadCard(context, draft),
                const SizedBox(height: 12),
                Center(
                  child: ToonSeg(
                    labels: const <String>['支出', '收入'],
                    index: _type == 'income' ? 1 : 0,
                    onChanged: (int i) {
                      final String next = i == 1 ? 'income' : 'expense';
                      setState(() {
                        _type = next;
                        // 换方向后原分类不再适用
                        final bool stillValid = categories.any(
                          (Category c) => c.id == _categoryId && c.kind == next,
                        );
                        if (!stillValid) {
                          _categoryId = _matchCategory(categories, next, null);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                AmountKeyboard(
                  value: _amount,
                  onKey: (String key) {
                    if (draft.blockers.isNotEmpty) return; // 失败单不允许改金额后硬记
                    setState(() => _amount = applyAmountKey(_amount, key));
                  },
                ),
                if (choices.length > 1) ...<Widget>[
                  const SizedBox(height: 10),
                  _CandidateRow(
                    amounts: choices,
                    currentCents: isParsableAmount(_amount)
                        ? yuanToCents(_amount)
                        : null,
                    onPick: (int cents) =>
                        setState(() => _amount = centsToYuan(cents)),
                  ),
                ],
                const SizedBox(height: 12),
                ToonCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: <Widget>[
                      ToonField(
                        label: '分类',
                        value: selectedCategory?.name ?? '请选择分类',
                        placeholder: selectedCategory == null,
                        onTap: () => _pickCategory(categories),
                      ),
                      ToonField(
                        label: '日期',
                        value: _fmtDate(_occurredAtMs),
                        dashedTop: true,
                        onTap: _pickDate,
                      ),
                      ToonField(
                        label: '账户',
                        value: selectedAccount?.name ?? '请选择账户',
                        placeholder: selectedAccount == null,
                        dashedTop: true,
                        onTap: () => _pickAccount(accounts),
                      ),
                      ToonField(
                        label: '备注',
                        dashedTop: true,
                        child: TextField(
                          controller: _note,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: '商户名（可改）',
                            hintStyle: TextStyle(
                              color: p.ink3,
                              fontWeight: FontWeight.w600,
                            ),
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (draft.issues.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _IssueList(draft: draft),
                ],
                if (_similar.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _ReceiptNotice(
                    text: '疑似重复：${_fmtDate(_similar.first.occurredAt)} 已经有一笔 '
                        '¥${centsToYuan(_similar.first.amountCents)} 的同类记录，确认不是同一笔再记。',
                    kind: _ReceiptNoticeKind.warn,
                  ),
                ],
                const SizedBox(height: 12),
                _RawTextBlock(
                  text: draft.rawText,
                  expanded: _showRaw,
                  elapsedMs: _ocrElapsedMs,
                  onToggle: () => setState(() => _showRaw = !_showRaw),
                ),
              ],
            ),
          ),
        ),
        _buildStickySave(context, draft),
      ],
    );
  }

  Widget _buildHeadCard(BuildContext context, ReceiptDraft draft) {
    final ToonPalette p = context.toon;
    final bool blocked = draft.blockers.isNotEmpty;
    return ToonCard(
      color: blocked ? p.redTint : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                draft.platform.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: draft.status),
              const Spacer(),
              if (_imagePath != null && File(_imagePath!).existsSync())
                _Thumb(path: _imagePath!),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _headline(draft),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: blocked ? p.redInk : p.ink2,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  String _headline(ReceiptDraft draft) {
    if (draft.blockers.contains(ReceiptIssue.emptyText)) {
      return '这张图没读出文字，换一张更清晰的截图，或者手动记一笔。';
    }
    if (draft.blockers.contains(ReceiptIssue.paymentFailed)) {
      return '识别到「支付失败」，这笔不能记账。';
    }
    if (draft.blockers.contains(ReceiptIssue.paymentCancelled)) {
      return '识别到「交易已取消」，这笔不能记账。';
    }
    if (draft.blockers.contains(ReceiptIssue.missingAmount)) {
      return '没识别到金额，请手动填一个再记账。';
    }
    final String amountTag = draft.amountCents.confidence == FieldConfidence.high
        ? '金额已确认'
        : '金额请核对';
    return '$amountTag · 识别依据：${draft.amountCents.tag.isEmpty ? '—' : draft.amountCents.tag}'
        ' · 用时 ${_ocrElapsedMs}ms';
  }

  Widget _buildStickySave(BuildContext context, ReceiptDraft draft) {
    final ToonPalette p = context.toon;
    final bool blocked = draft.blockers.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.ink, width: Tok.bw)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Opacity(
            opacity: blocked || _saving ? 0.5 : 1,
            child: ToonButton(
              block: true,
              label: _saving ? '保存中…' : '确认记账',
              onPressed: blocked || _saving ? null : _save,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            blocked ? '这张图不能直接记账，请换一张或手动记一笔' : '确认后写入当前账本，重复确认不会记两笔',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p.ink2,
            ),
          ),
        ],
      ),
    );
  }

  // ── 第 3 步：结果 ──

  Widget _buildResultBody(BuildContext context) {
    final ToonPalette p = context.toon;
    final ReceiptWriteResult result = _result!;
    final ({bool ok, String title, String sub}) view = switch (result) {
      ReceiptWritten(tx: final TxRow tx) => (
        ok: true,
        title: '已记账',
        sub:
            '${tx.type == 'income' ? '收入' : '支出'} ¥${centsToYuan(tx.amountCents)}'
            ' · ${_fmtDate(tx.occurredAt)}',
      ),
      ReceiptDuplicate(existing: final TxRow tx) => (
        ok: false,
        title: '这笔之前已经记过了',
        sub:
            '${_fmtDate(tx.occurredAt)} · ¥${centsToYuan(tx.amountCents)}，没有重复入账',
      ),
      ReceiptWriteFailed(message: final String message) => (
        ok: false,
        title: '没记上',
        sub: message,
      ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        ToonCard(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: view.ok ? p.greenTint : p.track,
                      borderRadius: BorderRadius.circular(14),
                      border: p.inkBorder(on: view.ok ? p.greenTint : p.track),
                      boxShadow: p.hard(d: 2),
                    ),
                    child: Icon(
                      view.ok ? Icons.check : Icons.info_outline,
                      size: 24,
                      color: view.ok ? p.green : p.ink3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      view.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                view.sub,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ToonButton(block: true, label: '去看账单', onPressed: _goToLedger),
        const SizedBox(height: 10),
        ToonButton(
          block: true,
          kind: ToonButtonKind.ghost,
          label: '再识别一张',
          onPressed: _resetToPick,
        ),
      ],
    );
  }

  String _fmtDate(int ms) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
