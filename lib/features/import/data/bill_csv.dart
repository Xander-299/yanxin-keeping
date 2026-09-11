/// CSV 行解析（状态机）— 旧栈 `bill-import/csv.js` 的移植。
///
/// 为什么不用 `split(',')`：账单备注/商品名常含逗号、引号甚至换行，
/// 逐字符状态机是唯一可靠解法。
///
/// 语法层只管切分，不做列数校验、不 trim、不转金额——那些是
/// profile 与归一化层的职责。
library;

/// 把整段 CSV 文本解析为二维数组。
///
/// 字段数不齐原样保留；行间空行跳过。
List<List<String>> parseCsvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = '';
  var inQuotes = false;
  var quoted = false; // 当前字段是否以引号开头（决定引号后内容的处理）

  void pushField() {
    row.add(field);
    field = '';
  }

  void pushRow() {
    pushField();
    // 空行（整行无内容）跳过；有内容的行即使字段不齐也保留
    if (!(row.length == 1 && row[0] == '')) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];

    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false; // 收尾引号
        }
      } else {
        field += ch; // 引号内的逗号/换行原样保留
      }
      continue;
    }

    if (ch == '"' && field.isEmpty && !quoted) {
      inQuotes = true;
      quoted = true;
      continue;
    }

    if (ch == ',') {
      pushField();
      quoted = false;
      continue;
    }

    if (ch == '\n' || ch == '\r') {
      // CRLF 当一个行分隔符处理
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      pushRow();
      quoted = false;
      continue;
    }

    // 引号收尾后直接跟内容（如 "a"b）：容错拼接
    field += ch;
  }

  // 文件末尾无换行：最后一行仍在缓冲区
  if (field.isNotEmpty || row.isNotEmpty) pushRow();

  return rows;
}
