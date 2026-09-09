/// 金额工具：一律以「整数分」为内部单位，界面展示才转「元字符串」。
///
/// 铁律（见 SPEC-storage）：金额绝不用浮点表示或计算。
/// 例如 0.1 + 0.2 元：先各转成 10 分、20 分，整数相加得 30 分，
/// 永不出现 0.30000000000000004。
library;

/// 元字符串 -> 整数分。
///
/// 支持 '12.34' / '1,234.56'（千分位会被忽略）/ '12' / '0'。
/// 非法格式抛 [FormatException]，避免脏数据入库。
int yuanToCents(Object yuanStr) {
  final s = yuanStr.toString().trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
    throw FormatException('金额格式非法：$yuanStr');
  }
  final parts = s.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : '';
  // 整数位 + 两位小数位，直接拼接成整数，全程不碰浮点
  return int.parse(intPart + decPart.padRight(2, '0').substring(0, 2));
}

/// 整数分 -> 元字符串。
///
/// [group] 为 true 时加千分位。例：'12.34' / '-0.30' / '1,234,567.89'。
String centsToYuan(int cents, {bool group = false}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final intPart = abs ~/ 100;
  final decPart = (abs % 100).toString().padLeft(2, '0');
  var intStr = intPart.toString();
  if (group) {
    intStr = intStr.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
  final s = '$intStr.$decPart';
  return neg ? '-$s' : s;
}

/// 整数分求和（用整数加法，杜绝浮点误差）。
int sumCents(List<int> parts) => parts.fold(0, (acc, p) => acc + p);

/// 绝对值（分）。
int absCents(int cents) => cents.abs();
