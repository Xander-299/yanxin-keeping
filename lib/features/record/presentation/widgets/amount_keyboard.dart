/// 金额键盘：3 列 4 行（1-9 / . 0 退格）+ 顶部金额显示。
///
/// 输入规则在 `application/amount_input.dart`，这里只负责渲染与回调。
/// 视觉对齐页面原型 `.amount-box` + `.keypad`（白键 + 墨色描边 + 硬阴影）。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';

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
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: Tok.cardDeco(radius: Tok.rLg, shadow: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              const Text(
                '¥',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Tok.ink2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value.isEmpty ? '0.00' : value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: value.isEmpty ? Tok.ink3 : Tok.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final List<String> row in _keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: <Widget>[
                for (final String key in row)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: key == row.first ? 0 : 5,
                        right: key == row.last ? 0 : 5,
                      ),
                      child: _KeyButton(
                        label: key == amountKeyDelete ? null : key,
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

/// 单个按键：白底描边 + 硬阴影；退格键用品牌浅底（原型 `.keypad button.del`）。
class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, required this.onTap});

  /// 为空则渲染退格图标。
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool del = label == null;
    return ToonPress(
      dx: 2.5,
      dy: 2.5,
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: del ? Tok.brandTint : Tok.paper,
          borderRadius: BorderRadius.circular(Tok.rMd),
          border: Tok.inkBorder(),
          boxShadow: Tok.hard(d: 2.5),
        ),
        child: del
            ? const Icon(Icons.backspace_outlined, size: 24, color: Tok.brandInk)
            : Text(
                label!,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
      ),
    );
  }
}
