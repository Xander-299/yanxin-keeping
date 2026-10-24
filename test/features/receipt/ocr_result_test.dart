/// OCR 结果模型测试（F8.1）：行排序必须稳定（否则同一张图两次识别得到不同文本，
/// 指纹去重就失效了）。
library;

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/receipt/data/ocr_engine.dart';

OcrLine line(String text, {double? top, double? left, double height = 20}) {
  if (top == null || left == null) return OcrLine(text: text);
  return OcrLine(
    text: text,
    box: Rect.fromLTWH(left, top, 100, height),
  );
}

void main() {
  test('按先上后右排序', () {
    final OcrResult r = OcrResult(
      lines: <OcrLine>[
        line('第二行', top: 40, left: 10),
        line('第一行右', top: 10, left: 200),
        line('第一行左', top: 10, left: 10),
      ],
      text: '',
    );
    expect(r.lineTexts, <String>['第一行左', '第一行右', '第二行']);
  });

  test('同一行（纵向差在 1/4 行高内）按横向排：右对齐的金额不会被排到下一行', () {
    final OcrResult r = OcrResult(
      lines: <OcrLine>[
        line('¥36.00', top: 12, left: 180),
        line('支付金额', top: 10, left: 10),
      ],
      text: '',
    );
    expect(r.lineTexts, <String>['支付金额', '¥36.00']);
  });

  test('没有坐标时保持原顺序（且有既有顺序兜底）', () {
    final OcrResult r = OcrResult(
      lines: <OcrLine>[line('a'), line('b'), line('c')],
      text: '',
    );
    expect(r.lineTexts, <String>['a', 'b', 'c']);
  });

  test('空行被丢掉，empty 判定正确', () {
    final OcrResult r = OcrResult(
      lines: <OcrLine>[line('  '), line('有字')],
      text: '',
    );
    expect(r.lineTexts, <String>['有字']);
    expect(r.isEmpty, isFalse);
    expect(const OcrResult.empty().isEmpty, isTrue);
  });

  test('OcrFailure 的 code 都有可读文案', () {
    for (final String code in <String>[
      'unsupported_platform',
      'file_not_found',
      'bad_args',
      'timeout',
      'ocr_failed',
    ]) {
      final OcrFailure failure = OcrFailure(code, 'raw');
      expect(failure.userMessage.trim(), isNotEmpty, reason: code);
      // 不把原生错误原文抛给用户
      expect(failure.userMessage.contains('raw'), isFalse, reason: code);
    }
  });
}
