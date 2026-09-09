/// UUID v4 生成。
///
/// 用途：所有业务表的主键 id 由客户端生成 UUID（local-first 要求，见 SPEC-storage）。
/// 走 [Uuid] 包，Native / Web / 测试环境行为一致。
library;

import 'package:uuid/uuid.dart';

/// 全局实例（内部使用加密安全随机数）。
const _uuid = Uuid();

/// 生成标准 UUID v4 字符串，形如 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'。
String uuidV4() => _uuid.v4();

/// 判定字符串是否为合法 UUID v4（用于校验外部输入）。
bool isUuid(Object? v) {
  if (v is! String) return false;
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(v);
}
