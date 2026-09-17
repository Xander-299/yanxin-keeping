/// 账户类型的展示元信息（中文名 + 图标）。
///
/// 类型值来自 `core/constants/preset.dart` 的 `accountTypes`：
/// cash / bank / credit / alipay / wechat / other。
library;

import 'package:flutter/material.dart';

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
