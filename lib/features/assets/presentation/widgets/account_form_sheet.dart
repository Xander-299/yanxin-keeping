/// 账户新增 / 编辑底部弹窗。
///
/// - 新增：名称 + 类型 + 初始余额（元，最多两位小数，不允许负数，见 SPEC §7）
/// - 编辑：同上，另加红色「删除账户」（**账户下有流水时禁止删除**）
/// 保存 / 删除成功后由 controller bump 数据版本号 → 资产页自动重算。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/constants/preset.dart';
import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/utils/money.dart';

import '../../application/account_meta.dart';
import '../../application/assets_controller.dart';

/// 打开账户表单弹窗。[account] 为空 = 新增，否则 = 编辑。
Future<void> showAccountFormSheet(
  BuildContext context,
  WidgetRef ref, {
  Account? account,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tok.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
      side: BorderSide(color: Tok.ink, width: Tok.bw),
    ),
    builder: (BuildContext _) => _AccountFormSheet(account: account),
  );
}

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet({this.account});

  final Account? account;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late String _type;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    final Account? a = widget.account;
    _name = TextEditingController(text: a?.name ?? '');
    _type = a?.type ?? 'cash';
    // 回填金额：1000.00 → 1000（去掉无意义的 .00，方便直接改）
    _balance = TextEditingController(
      text: (a?.initialBalanceCents ?? 0) > 0
          ? centsToYuan(a!.initialBalanceCents).replaceFirst(RegExp(r'\.00$'), '')
          : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  /// 解析初始余额（分）。空串 = 0；格式非法抛 [FormatException]。
  int _parseBalanceCents() {
    final String raw = _balance.text.trim();
    if (raw.isEmpty) return 0;
    return yuanToCents(raw);
  }

  Future<void> _save() async {
    if (_busy) return;
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入账户名称');
      return;
    }
    final int cents;
    try {
      cents = _parseBalanceCents();
    } on FormatException {
      setState(() => _error = '初始余额格式不对，最多两位小数');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    // pop 之后 widget 会销毁，这两个要先取出来
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final Account? a = widget.account;
      if (a == null) {
        await ref.read(assetsProvider.notifier).addAccount(
          name: name,
          type: _type,
          initialBalanceCents: cents,
        );
      } else {
        await ref.read(assetsProvider.notifier).updateAccount(
          a.id,
          name: name,
          type: _type,
          initialBalanceCents: cents,
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败：$e';
      });
      return;
    }
    if (!mounted) return;
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_isEdit ? '已保存「$name」' : '已新增「$name」'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _delete() async {
    final Account? a = widget.account;
    if (_busy || a == null) return;

    // 有流水的账户不能删：删了会让这些流水指向不存在的账户
    final int txCount = ref.read(assetsProvider.notifier).txCountOf(a.id);
    if (txCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('删不了这个账户'),
          content: Text('「${a.name}」下还有 $txCount 笔流水，请先把这些流水改到别的账户。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('删除「${a.name}」后不再计入净资产，确定删除？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(assetsProvider.notifier).deleteAccount(a.id);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '删除失败：$e';
      });
      return;
    }
    if (!mounted) return;
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${a.name}」'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘弹起时把内容顶上来
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _isEdit ? '编辑账户' : '新增账户',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  autofocus: !_isEdit,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '账户名称',
                    hintText: '如：现金 / 招行储蓄卡',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: '账户类型',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final String t in accountTypes)
                      DropdownMenuItem<String>(
                        value: t,
                        child: Text(accountTypeLabel(t)),
                      ),
                  ],
                  onChanged: (String? v) {
                    if (v != null) setState(() => _type = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _balance,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '初始余额（元）',
                    hintText: '0.00',
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B6B)),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    if (_isEdit)
                      TextButton(
                        onPressed: _busy ? null : _delete,
                        child: const Text(
                          '删除账户',
                          style: TextStyle(color: Color(0xFFFF6B6B)),
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
