/// 输入名称的对话框（有状态持有 controller，避免重建丢文本）。
library;

import 'package:flutter/material.dart';

import '../../core/theme/toon.dart';

/// 弹出输入框，返回名称（取消返回 null）。
Future<String?> showNameDialog(BuildContext context, {required String title}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _NameDialog(title: title),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title});

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '请输入名称'),
      ),
      actions: <Widget>[
        ToonButton(
          label: '取消',
          kind: ToonButtonKind.ghost,
          small: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ToonButton(
          label: '确定',
          small: true,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}
