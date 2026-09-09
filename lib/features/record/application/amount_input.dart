/// 金额键盘的输入规则（纯函数，便于单测）。
///
/// 约束与 [yuanToCents] 对齐：整数位最多 9 位、小数最多 2 位、不产生前导 0。
library;

/// 退格键。
const String amountKeyDelete = 'del';

/// 整数位上限。
const int maxIntegerDigits = 9;

/// 小数位上限。
const int maxFractionDigits = 2;

/// 按键 → 新金额字符串。非法输入原样返回。
///
/// [key] 取值为 '0'-'9'、'.' 或 [amountKeyDelete]。
String applyAmountKey(String current, String key) {
  if (key == amountKeyDelete) {
    if (current.isEmpty) return current;
    return current.substring(0, current.length - 1);
  }
  if (key == '.') {
    if (current.contains('.')) return current;
    return current.isEmpty ? '0.' : '$current.';
  }
  if (!RegExp(r'^\d$').hasMatch(key)) return current;

  final dotIndex = current.indexOf('.');
  final intPart = dotIndex < 0 ? current : current.substring(0, dotIndex);
  final fracPart = dotIndex < 0 ? '' : current.substring(dotIndex + 1);

  if (dotIndex >= 0) {
    if (fracPart.length >= maxFractionDigits) return current;
    return '$current$key';
  }
  if (intPart == '0') return key; // 去掉前导 0
  if (intPart.length >= maxIntegerDigits) return current;
  return '$current$key';
}

/// 是否是可以解析的金额（交给 [yuanToCents] 前先兜一层，避免抛异常）。
bool isParsableAmount(String value) {
  final s = value.trim();
  if (s.isEmpty) return false;
  return RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s);
}
