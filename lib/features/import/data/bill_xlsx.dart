/// 极简 xlsx 读取器 — 旧栈 `bill-import/xlsx.js` 的移植，专用于微信账单明细。
///
/// 为什么不用 `excel` 包：它把数值单元格经 double 解析后再输出，
/// 31 位交易单号必丢精度（真实件回归测试明确断言不丢）。
/// 这里沿用旧栈思路：正则提取 XML 原文，数值不经过任何浮点；
/// 解压交给 `archive` 包（纯 Dart，无 native 钩子）。
///
/// 范围与限制（够用即可）：
/// - 取第一个 worksheet；不支持公式结果以外的 t="e"/t="str" 特殊类型（账单不含）
/// - 单元格值一律以 XML 原文文本返回：数值不经过 float，
///   Excel 日期序列号的转换在 bill_normalize.parseTimeMs 里按 profile 语义处理
library;

import 'dart:convert';

import 'package:archive/archive.dart';

/// ZIP 本地文件头魔数 PK\x03\x04。
bool isZipBytes(List<int> bytes) =>
    bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;

/// xlsx 内部 XML 恒为 UTF-8，Dart 自带 utf8.decode 覆盖（含代理对）。
String _decodeUtf8(List<int> bytes) => utf8.decode(bytes);

String _xmlEscape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.parse(m.group(1)!);
      return String.fromCharCode(code);
    })
    .replaceAll('&amp;', '&');

/// 解析 sharedStrings.xml -> `List<String>`（富文本的多段 `<t>` 拼接）。
List<String> _parseSharedStrings(String xml) {
  final out = <String>[];
  final re = RegExp(r'<si(?:\s[^>]*)?>([\s\S]*?)</si>|<si(?:\s[^>]*)?/>');
  for (final m in re.allMatches(xml)) {
    final body = m.group(1);
    if (body == null) {
      out.add('');
      continue;
    }
    final parts = <String>[];
    final tre = RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>|<t(?:\s[^>]*)?/>');
    for (final t in tre.allMatches(body)) {
      final content = t.group(1);
      parts.add(content != null ? _xmlEscape(content) : '');
    }
    out.add(parts.join());
  }
  return out;
}

/// 'C18' -> 2（0-based 列号）；'A' -> 0。
int _colIndex(String ref) {
  var n = 0;
  for (var i = 0; i < ref.length; i++) {
    final ch = ref[i];
    final code = ch.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      n = n * 26 + (code - 64);
    } else {
      break;
    }
  }
  return n - 1;
}

/// 解析 worksheet XML -> 行矩阵（稀疏单元格按列号落位，缺位补空串）。
List<List<String>> _parseSheet(String xml, List<String> shared) {
  final rows = <List<String>>[];
  final rowRe = RegExp(r'<row(?:\s[^>]*)?>([\s\S]*?)</row>|<row(?:\s[^>]*)?/>');
  for (final rm in rowRe.allMatches(xml)) {
    final cells = <String>[];
    final cellRe = RegExp(r'<c\s([^>]*?)(?:/>|>([\s\S]*?)</c>)');
    for (final cm in cellRe.allMatches(rm.group(1)!)) {
      final attrs = cm.group(1)!;
      final inner = cm.group(2) ?? '';
      final refM = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs);
      final col = refM != null ? _colIndex(refM.group(1)!) : cells.length;
      var text = '';
      final tM = RegExp(r't="(\w+)"').firstMatch(attrs);
      final vM =
          RegExp(r'<v(?:\s[^>]*)?>([\s\S]*?)</v>').firstMatch(inner);
      final t = tM?.group(1);
      if (t == 's' || t == 'str') {
        if (vM == null) {
          text = '';
        } else if (t == 's') {
          // 共享字符串：按索引查表
          final idx = int.tryParse(vM.group(1)!) ?? -1;
          text = (idx >= 0 && idx < shared.length) ? shared[idx] : '';
        } else {
          text = _xmlEscape(vM.group(1)!);
        }
      } else if (t == 'inlineStr') {
        final parts = <String>[];
        final tre = RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>');
        for (final tm in tre.allMatches(inner)) {
          parts.add(_xmlEscape(tm.group(1)!));
        }
        text = parts.join();
      } else if (vM != null) {
        // 数值：保留 XML 原文（不 float 化，交易单号不丢精度）
        text = vM.group(1)!;
      }
      if (col >= cells.length) {
        cells.addAll(List.filled(col + 1 - cells.length, ''));
      }
      cells[col] = text;
    }
    rows.add(cells);
  }
  return rows;
}

/// 读取 xlsx -> 行矩阵。解不开抛 [FormatException]。
List<List<String>> readXlsxRows(List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('无法解压该文件，不是有效的 xlsx');
  }
  ArchiveFile? sharedFile;
  ArchiveFile? sheetFile;
  final sheetNames = <String>[];
  for (final f in archive.files) {
    if (f.name == 'xl/sharedStrings.xml') sharedFile = f;
    if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) {
      sheetNames.add(f.name);
    }
  }
  sheetNames.sort();
  if (sheetNames.isEmpty) {
    throw const FormatException('xlsx 中找不到工作表');
  }
  sheetFile = archive.findFile(sheetNames.first);

  final shared =
      sharedFile != null ? _parseSharedStrings(_decodeUtf8(sharedFile.content)) : <String>[];
  final sheetXml = _decodeUtf8(sheetFile!.content);
  return _parseSheet(sheetXml, shared);
}
