/// 账单文件解码 — 旧栈 `bill-import/decode.js` 的移植。
///
/// 策略：先按 UTF-8 严格模式试解并剥 BOM；非法字节 → 回退 GBK；
/// GBK 也验不过 → 明确抛「无法识别的文件编码」，不猜。
///
/// 与旧栈的差异：
/// - JS TextDecoder 对 GBK 非法序列产出 U+FFFD，可直接检测；
///   `gbk_codec` 的解码器对未知序列回退成原字符码（无 FFFD），
///   故改用 **重编码回环校验**（decode → encode 比对原字节）判定解码是否可信。
/// - `gbk_codec` 导出两个实例：`gbk` 是逐字节版（双字节会拆散），
///   `gbk_bytes` 才是双字节合并解码版，用后者。
library;

import 'dart:convert';

import 'package:gbk_codec/gbk_codec.dart';

/// 解码结果：文本 + 实际使用的编码。
class DecodedBill {
  const DecodedBill({required this.text, required this.encoding});

  final String text;
  final String encoding; // 'utf-8' | 'gbk'
}

/// 账单字节流 → 文本。解码不出抛 [FormatException]。
DecodedBill decodeBillBytes(List<int> bytes) {
  // 1. UTF-8 严格尝试（非法序列抛 FormatException）
  try {
    final text = utf8.decode(bytes);
    return DecodedBill(text: stripBom(text), encoding: 'utf-8');
  } on FormatException {
    // 非 UTF-8，继续回退
  }

  // 2. GBK 回退 + 回环校验（未知双字节序列会被解码器静默替换，回环必不匹配）
  try {
    final text = gbk_bytes.decoder.convert(bytes);
    final roundTrip = gbk_bytes.encoder.convert(text);
    if (!_bytesEqual(roundTrip, bytes)) {
      throw const FormatException('gbk roundtrip mismatch');
    }
    return DecodedBill(text: stripBom(text), encoding: 'gbk');
  } catch (_) {
    throw const FormatException('无法识别的文件编码：既不是 UTF-8 也不是 GBK');
  }
}

/// 解码器不保证剥 BOM（UTF-8 会保留 U+FEFF），手动剥离。
String stripBom(String text) =>
    text.startsWith('\uFEFF') ? text.substring(1) : text;

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
