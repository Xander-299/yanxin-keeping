/// 账户选择底部弹层（行列表 + 选中对勾）。
///
/// 视觉对齐记一笔页其它弹层：抓手 + 标题 + `ToonAvatar` 行列表；
/// 选中项右侧给品牌色对勾（**不给行加位移/变宽**，避免 F7.5-a 那种「选中变宽挤位移」）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/assets/application/account_meta.dart';

/// 打开账户选择器，返回选中的账户（取消返回 null）。
Future<Account?> showAccountPicker(
  BuildContext context, {
  required List<Account> accounts,
  String? selectedId,
}) {
  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: false,
    backgroundColor: Tok.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
      side: BorderSide(color: Tok.ink, width: Tok.bw),
    ),
    builder: (BuildContext context) => _AccountList(
      accounts: accounts,
      selectedId: selectedId,
    ),
  );
}

class _AccountList extends StatelessWidget {
  const _AccountList({required this.accounts, this.selectedId});

  final List<Account> accounts;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 抓手
            Center(
              child: Container(
                width: 46,
                height: 6,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Tok.ink,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const Text(
              '选择账户',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: Tok.cardDeco(),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < accounts.length; i++)
                        Column(
                          children: <Widget>[
                            if (i > 0) const ToonDashedLine(),
                            _AccountRow(
                              account: accounts[i],
                              selected: accounts[i].id == selectedId,
                              onTap: () =>
                                  Navigator.of(context).pop(accounts[i]),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '记一笔默认用列表第一个账户；到「资产 → 新增账户」可加更多。',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = account.name;
    return ToonPress(
      dx: 0,
      dy: 0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: <Widget>[
            ToonAvatar(
              text: name.isEmpty ? '?' : name.substring(0, 1),
              small: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accountTypeLabel(account.type),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Tok.ink2,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, size: 20, color: Tok.brandDeep),
          ],
        ),
      ),
    );
  }
}
