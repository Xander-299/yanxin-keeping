part of '../chat_page.dart';

/// 聊天里的「待确认账单」卡（截图记账的确认步骤，压成一张卡）。
///
/// 为什么不是跳转到旧的三步页：聊天流里「发图 → 看到我读到了什么 → 点头」本来就该是
/// 一条消息的来回；卡片上的每个字段都可改，**没点确认就绝不写库**。
class _ReceiptCard extends ConsumerStatefulWidget {
  const _ReceiptCard({required this.message, required this.index});

  final ReceiptMessage message;
  final int index;

  @override
  ConsumerState<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends ConsumerState<_ReceiptCard> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _type;
  late String? _categoryId;
  late String? _accountId;
  late int _occurredAtMs;

  @override
  void initState() {
    super.initState();
    _resetFromMessage();
  }

  void _resetFromMessage() {
    final ReceiptMessage m = widget.message;
    _amount = TextEditingController(text: m.amountCents > 0 ? centsToYuan(m.amountCents) : '');
    _note = TextEditingController(text: m.note);
    _type = m.type;
    _categoryId = m.categoryId;
    _accountId = m.accountId;
    _occurredAtMs = m.occurredAtMs;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

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
    if (accounts.isEmpty) return;
    final Account? picked = await showAccountPicker(
      context,
      accounts: accounts,
      selectedId: _accountId ?? accounts.first.id,
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

  void _confirm() {
    final bool ok = isParsableAmount(_amount.text) && yuanToCents(_amount.text) > 0;
    ref.read(chatProvider.notifier).confirmReceipt(
      widget.index,
      type: _type,
      amountCents: ok ? yuanToCents(_amount.text) : 0,
      categoryId: _categoryId,
      accountId: _accountId,
      occurredAtMs: _occurredAtMs,
      note: _note.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final ReceiptMessage m = widget.message;
    final List<Category> categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final List<Account> accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final bool blocked = m.blockers.isNotEmpty;
    final Category? category = _categoryById(categories, _categoryId);
    final Account? account = _accountById(accounts, _accountId) ??
        (accounts.isEmpty ? null : accounts.first);

    return ToonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: blocked ? p.redTint : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 头：来源 + 状态（识别到的，不给改）
          Row(
            children: <Widget>[
              Text(
                m.draft.platform.label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p.canvas2,
                  borderRadius: BorderRadius.circular(999),
                  border: p.inkBorder(w: Tok.bw * 0.7),
                ),
                child: Text(
                  m.draft.status.label,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink2),
                ),
              ),
              const Spacer(),
              if (m.done)
                Icon(Icons.check_circle, size: 16, color: p.green)
              else
                Text(
                  '待确认',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink3),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (m.done) ...<Widget>[
            Text(
              m.resultText ?? '已记账',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: p.ink,
                height: 1.5,
              ),
            ),
          ] else ...<Widget>[
            // 收支方向 + 金额
            Center(
              child: ToonSeg(
                labels: const <String>['支出', '收入'],
                index: _type == 'income' ? 1 : 0,
                onChanged: (int i) {
                  setState(() {
                    _type = i == 1 ? 'income' : 'expense';
                    final bool stillValid =
                        categories.any((Category c) => c.id == _categoryId && c.kind == _type);
                    if (!stillValid) {
                      _categoryId = matchCategoryId(categories, _type, null);
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '¥',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      hintText: '金额',
                      hintStyle: TextStyle(fontSize: 20, color: p.ink3),
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: p.line),
            ToonField(
              label: '分类',
              value: category?.name ?? '请选择分类',
              placeholder: category == null,
              onTap: () => _pickCategory(categories),
            ),
            ToonField(
              label: '日期',
              value: _formatDateTime(_occurredAtMs),
              dashedTop: true,
              onTap: _pickDate,
            ),
            ToonField(
              label: '账户',
              value: account?.name ?? '账本里还没有账户',
              placeholder: account == null,
              dashedTop: true,
              onTap: () => _pickAccount(accounts),
            ),
            ToonField(
              label: '备注',
              dashedTop: true,
              child: TextField(
                controller: _note,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '商户名（可改）',
                  hintStyle: TextStyle(color: p.ink3, fontWeight: FontWeight.w600),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),

            if (blocked) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _blockedReason(m.blockers),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.redInk,
                  height: 1.5,
                ),
              ),
            ] else if (m.draft.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _issueLine(m.draft.warnings),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink3,
                  height: 1.5,
                ),
              ),
            ],
            if (m.similar.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '疑似重复：${_formatDateTime(m.similar.first.occurredAt)} 已有一笔 '
                '¥${centsToYuan(m.similar.first.amountCents)}，确认不是同一笔再记。',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: p.redInk,
                  height: 1.5,
                ),
              ),
            ],
            if (m.error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                m.error!,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.redInk),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: ToonButton(
                    block: true,
                    small: true,
                    kind: ToonButtonKind.ghost,
                    label: '取消',
                    onPressed: m.saving
                        ? null
                        : () => ref.read(chatProvider.notifier).dismissReceipt(widget.index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ToonButton(
                    block: true,
                    small: true,
                    label: m.saving ? '保存中…' : '确认记账',
                    onPressed: blocked || m.saving ? null : _confirm,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Category? _categoryById(List<Category> list, String? id) {
    if (id == null) return null;
    for (final Category c in list) {
      if (c.id == id) return c;
    }
    return null;
  }

  Account? _accountById(List<Account> list, String? id) {
    if (id == null) return null;
    for (final Account a in list) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _blockedReason(List<ReceiptIssue> blockers) {
    if (blockers.contains(ReceiptIssue.paymentFailed)) return '识别到「支付失败」，这笔不能记账。';
    if (blockers.contains(ReceiptIssue.paymentCancelled)) return '识别到「交易已取消」，这笔不能记账。';
    if (blockers.contains(ReceiptIssue.emptyText)) return '这张图没读出文字，换一张更清晰的截图。';
    if (blockers.contains(ReceiptIssue.missingAmount)) return '没识别到金额，请手动填一个再记账。';
    return '这张图不能直接记账，请换一张或手动记一笔。';
  }

  /// 非阻断的提醒（多金额 / 年份推断 / 商户缺失 …），最多列三条。
  String _issueLine(List<ReceiptIssue> warnings) {
    if (warnings.isEmpty) return '';
    return '请核对：${warnings.take(3).map((ReceiptIssue i) => i.message).join('；')}';
  }
}
