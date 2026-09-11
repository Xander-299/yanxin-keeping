/// 输入名称的对话框（有状态持有 controller，避免重建丢文本）。
library;

import 'package:flutter/material.dart';

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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
