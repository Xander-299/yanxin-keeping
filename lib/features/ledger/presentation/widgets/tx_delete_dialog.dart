/// 删除流水前的确认对话框（首页与日历页共用）。
///
/// 视觉对齐页面原型 `dialog-delete`：白卡 + 3px 描边 + 大硬阴影 + 胶囊按钮。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

/// 弹出「删除这笔」确认框，返回用户是否确认。
Future<bool> confirmDeleteTx(BuildContext context) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 34),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '删除这笔',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              '删除后为软删除（deleted_at），不再出现在任何统计里，也不占回收站空间。',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                ToonButton(
                  label: '取消',
                  kind: ToonButtonKind.ghost,
                  small: true,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                const SizedBox(width: 8),
                ToonButton(
                  label: '删除',
                  kind: ToonButtonKind.danger,
                  small: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}
