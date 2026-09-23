/// 账户类型的展示元信息（中文名 + 图标）。
///
/// 类型值来自 `core/constants/preset.dart` 的 `accountTypes`：
/// cash / bank / credit / alipay / wechat / other。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';

/// 类型值 → 中文名。未知类型原样返回（不吞掉数据）。
String accountTypeLabel(String type) => switch (type) {
  'cash' => '现金',
  'bank' => '储蓄卡',
  'credit' => '信用卡',
  'alipay' => '支付宝',
  'wechat' => '微信',
  'other' => '其他',
  _ => type,
};

/// 类型值 → 图标（不用品牌 logo，只做语义区分）。
IconData accountTypeIcon(String type) => switch (type) {
  'cash' => Icons.payments_rounded,
  'bank' => Icons.account_balance_rounded,
  'credit' => Icons.credit_card_rounded,
  'alipay' => Icons.account_balance_wallet_rounded,
  'wechat' => Icons.smartphone_rounded,
  'other' => Icons.savings_rounded,
  _ => Icons.account_balance_wallet_rounded,
};

// ── 自选图标 / 颜色（F7.7 C 批；存进 accounts.icon / accounts.color）──

/// 自选图标候选：key 存进 `accounts.icon`。
/// **空串 / 未知 key = 跟随账户类型**（见 [accountIcon]），所以这里不放「空」项。
const Map<String, IconData> kAccountIcons = <String, IconData>{
  'cash': Icons.payments_rounded, // 现金
  'bank': Icons.account_balance_rounded, // 银行
  'card': Icons.credit_card_rounded, // 银行卡
  'wallet': Icons.account_balance_wallet_rounded, // 钱包
  'phone': Icons.smartphone_rounded, // 手机支付
  'piggy': Icons.savings_rounded, // 存钱罐
  'yuan': Icons.currency_yuan_rounded, // 人民币
  'exchange': Icons.currency_exchange_rounded, // 汇兑
};

/// 自选颜色候选（`#RRGGBB`，取 [Tok.pie] 前 8 个；第 9 个是灰，不做候选）。
/// **空串 / 非法值 = 跟随类型默认底色**（见 [accountAvatarColor]）。
const List<String> kAccountColors = <String>[
  '#FFB627',
  '#FF6B8A',
  '#4DC9C0',
  '#5A8DFF',
  '#B18CFF',
  '#5FD068',
  '#FF8A3D',
  '#F06FC0',
];

/// 账户头像图标：[iconKey] 非空且在候选集里 → 用它；否则跟随 [type] 的类型图标。
///
/// 自选图标**只是装饰**，不参与任何筛选 / 口径（SPEC §C.3）。
IconData accountIcon(String? iconKey, String type) {
  final IconData? picked = iconKey == null ? null : kAccountIcons[iconKey];
  return picked ?? accountTypeIcon(type);
}

/// 解析 `#RRGGBB`（大小写均可，可带 alpha 的 8 位也兼容）。非法返回 null。
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final String h = hex.trim();
  final String body = h.startsWith('#') ? h.substring(1) : h;
  final int? value = body.length == 6 || body.length == 8
      ? int.tryParse(body, radix: 16)
      : null;
  if (value == null) return null;
  // 6 位 = 不透明 RGB；8 位按 ARGB。
  final int argb = body.length == 6 ? 0xFF000000 | value : value;
  return Color(argb);
}

/// `#RRGGBB`（大写）。只保留 RGB——本批所有候选色都是不透明色。
String colorToHex(Color c) {
  final int rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 账户头像底色：[colorHex] 能解析 → 用它；否则回退类型默认的 `Tok.brandTint`
/// （与老数据空串行为完全一致，SPEC §C.1 兼容条款）。
Color accountAvatarColor(String? colorHex) =>
    parseHexColor(colorHex) ?? Tok.brandTint;
