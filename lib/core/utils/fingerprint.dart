/// 入账指纹计算（防自动记账重复入账）。
///
/// 指纹 = sha1('source|externalId|amountCents|秒级 occurredAt')
/// externalId 缺失时置空，退化为「金额分 + 秒级时间」。
///
/// 算法与旧栈 `src/utils/fingerprint.js` 逐字节一致（同为 UTF-8 + SHA-1 十六进制）。
/// 旧栈用 Web Crypto 是异步的；Dart 端同步即可（SHA-1 输入仅几十字节）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 计算指纹，返回 40 位小写十六进制 SHA-1。
String computeFingerprint({
  required String source,
  String? externalId,
  required int amountCents,
  required int occurredAt,
}) {
  final sec = occurredAt ~/ 1000;
  final payload = '$source|${externalId ?? ''}|$amountCents|$sec';
  return sha1.convert(utf8.encode(payload)).toString();
}
