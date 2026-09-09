/// 金额键盘：3 列 4 行（1-9 / . 0 退格）+ 顶部金额显示。
///
/// 输入规则在 `application/amount_input.dart`，这里只负责渲染与回调。
library;

import 'package:flutter/material.dart';

import '../../application/amount_input.dart';

/// 金额键盘。
class AmountKeyboard extends StatelessWidget {
  const AmountKeyboard({
    super.key,
    required this.value,
    required this.onKey,
  });

  /// 当前金额字符串。
  final String value;

  /// 按键回调（'0'-'9' / '.' / [amountKeyDelete]）。
  final ValueChanged<String> onKey;

  static const List<List<String>> _keys = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['.', '0', amountKeyDelete],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value.isEmpty ? '0.00' : value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        for (final row in _keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: <Widget>[
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: key == row.first ? 0 : 5,
                        right: key == row.last ? 0 : 5,
                      ),
                      child: _KeyButton(
                        label: key == amountKeyDelete ? '⌫' : key,
                        onTap: () => onKey(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
