/// 删除流水前的确认对话框（首页与日历页共用）。
library;

import 'package:flutter/material.dart';

/// 弹出「删除这笔」确认框，返回用户是否确认。
Future<bool> confirmDeleteTx(BuildContext context) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('删除这笔'),
      content: const Text('删除后在回收站保留，确定删除？'),
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
  return ok ?? false;
}
