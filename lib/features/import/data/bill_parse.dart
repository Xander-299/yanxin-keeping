/// 账单文件统一解析入口 — 旧栈 `bill-import/parse.js` 的移植。
///
/// 页面只调 [parseBillFileAuto]，不感知格式差异：
/// - ZIP 魔数（PK\x03\x04）→ xlsx（微信 2025+ 导出格式）→ parseBillRows
/// - 否则按文本解码（UTF-8 / GBK 回退）→ parseBillCsv
/// profile 自动探测：先微信后支付宝，必需列不全即判定不匹配。
library;

import 'bill_decode.dart';
import 'bill_normalize.dart';
import 'bill_profiles.dart';
import 'bill_xlsx.dart';

/// 账单文件原始字节 → 解析报告。无法识别时抛 [FormatException]。
BillParseResult parseBillFileAuto(List<int> bytes) {
  List<List<String>>? matrix;
  String? text;

  if (isZipBytes(bytes)) {
    matrix = readXlsxRows(bytes);
  } else {
    try {
      text = decodeBillBytes(bytes).text;
    } on FormatException catch (e) {
      throw FormatException(e.message == '' ? '无法识别的文件编码' : e.message);
    }
  }

  final errors = <String>[];
  for (final profile in billProfiles) {
    try {
      return matrix != null
          ? parseBillRows(profile, matrix)
          : parseBillCsv(profile, text!);
    } on FormatException catch (e) {
      errors.add('${profile.name}：${e.message}');
    }
  }
  throw FormatException('无法识别的账单文件格式。${errors.join('；')}');
}
