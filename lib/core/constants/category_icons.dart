/// 分类的图标 / 颜色目录（schema v4 起使用）。
///
/// 存进 `categories.icon` 的是**稳定 key**（`food` / `transport` …），不是
/// `IconData.toString()` 或 `hashCode` —— 后者是运行期值，跨版本/跨设备都不可复用。
/// 颜色存 `#RRGGBB`；空串 = 跟随收支方向的默认色（见 [categoryColor]）。
///
/// 这套 key 一旦发出去就不能改名（老数据里存着它），只能**追加**。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/palette.dart';

/// 图标 key → IconData。
const Map<String, IconData> kCategoryIcons = <String, IconData>{
  // 支出
  'food': Icons.restaurant_rounded, // 餐饮
  'breakfast': Icons.bakery_dining_rounded, // 早餐
  'lunch': Icons.rice_bowl_rounded, // 正餐
  'dinner': Icons.dinner_dining_rounded, // 晚餐
  'coffee': Icons.local_cafe_rounded, // 咖啡 / 奶茶
  'snack': Icons.cookie_rounded, // 零食
  'transport': Icons.directions_subway_rounded, // 交通
  'bus': Icons.directions_bus_rounded, // 公交
  'bike': Icons.pedal_bike_rounded, // 共享单车
  'taxi': Icons.local_taxi_rounded, // 打车
  'fuel': Icons.local_gas_station_rounded, // 加油
  'shopping': Icons.shopping_bag_rounded, // 购物
  'clothes': Icons.checkroom_rounded, // 服饰
  'digital': Icons.devices_rounded, // 数码
  'home': Icons.home_rounded, // 居住
  'rent': Icons.apartment_rounded, // 房租
  'utility': Icons.water_drop_rounded, // 水电
  'phone': Icons.smartphone_rounded, // 通讯
  'internet': Icons.wifi_rounded, // 网络
  'entertainment': Icons.videogame_asset_rounded, // 娱乐
  'movie': Icons.movie_rounded, // 影音
  'travel': Icons.luggage_rounded, // 旅行
  'flight': Icons.flight_takeoff_rounded, // 机票
  'hotel': Icons.hotel_rounded, // 住宿
  'medical': Icons.local_hospital_rounded, // 医疗
  'medicine': Icons.medication_rounded, // 药品
  'education': Icons.school_rounded, // 教育
  'book': Icons.menu_book_rounded, // 书籍
  'social': Icons.card_giftcard_rounded, // 人情社交
  'pet': Icons.pets_rounded, // 宠物
  'baby': Icons.child_care_rounded, // 育儿
  'fitness': Icons.fitness_center_rounded, // 运动
  'beauty': Icons.spa_rounded, // 美容
  'office': Icons.work_outline_rounded, // 办公
  'insurance': Icons.health_and_safety_rounded, // 保险
  'tax': Icons.receipt_long_rounded, // 税费
  'donation': Icons.volunteer_activism_rounded, // 捐赠
  // 收入
  'salary': Icons.account_balance_wallet_rounded, // 工资
  'bonus': Icons.emoji_events_rounded, // 奖金
  'parttime': Icons.handyman_rounded, // 兼职
  'invest': Icons.trending_up_rounded, // 投资收益
  'refund': Icons.undo_rounded, // 退款
  'redpacket': Icons.redeem_rounded, // 红包礼金
  // 兜底
  'other': Icons.label_outline_rounded, // 其他
};

/// 图标选择器的展示顺序（按上面的声明顺序）。
List<String> get kCategoryIconKeys => kCategoryIcons.keys.toList(growable: false);

/// 分类图标：key 未知 / 空串 → 按收支方向给默认图标。
IconData categoryIconData(String key, {String kind = 'expense'}) {
  final IconData? hit = kCategoryIcons[key];
  if (hit != null) return hit;
  return kind == 'income' ? Icons.savings_rounded : Icons.label_outline_rounded;
}

/// 分类颜色候选（`#RRGGBB`）。取调色板 pie 前 9 个，保证深浅主题下都能看清。
const List<String> kCategoryColors = <String>[
  '#FFB627',
  '#FF6B8A',
  '#4DC9C0',
  '#5A8DFF',
  '#B18CFF',
  '#5FD068',
  '#FF8A3D',
  '#F06FC0',
  '#9AA5B1',
];

/// `#RRGGBB` → Color；空串 / 非法值 → [fallback]。
Color parseHexColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  final String s = hex.replaceFirst('#', '');
  if (s.length != 6) return fallback;
  final int? v = int.tryParse(s, radix: 16);
  if (v == null) return fallback;
  return Color(0xFF000000 | v);
}

/// 分类色块底色：`categories.color` 为空 → 按收支方向给浅底。
Color categoryColor(ToonPalette p, String hex, {required String kind}) {
  final Color fallback = kind == 'income' ? p.greenTint : p.brandTint;
  return parseHexColor(hex, fallback);
}

/// 分类色块上的字 / 图标色：按底色亮度取深墨或白。
Color categoryOnColor(ToonPalette p, String hex, {required String kind}) {
  return p.inkOn(categoryColor(p, hex, kind: kind));
}
