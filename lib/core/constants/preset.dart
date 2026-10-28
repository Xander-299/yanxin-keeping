/// 预置数据与枚举常量（对应旧栈 `src/constants/preset.js`）。
///
/// 预置分类在**新建账本**时写入（`is_preset=1`）；老账本由
/// `CategoryRepository.ensurePresets()` 按名字幂等补齐（见 schema v4）。
///
/// 每个预置分类带**稳定图标 key** 与颜色（`core/constants/category_icons.dart`），
/// `aliases` 用于「老账本里叫旧名字」的匹配：例如老账本的「理财」对应新预置「投资收益」，
/// 补装时命中别名就不再插一条，避免同一个含义出现两个分类。
library;

/// 一个预置分类。
class PresetCategory {
  const PresetCategory(
    this.name,
    this.iconKey,
    this.color, {
    this.aliases = const <String>[],
  });

  final String name;
  final String iconKey;
  final String color;

  /// 老版本 / 旧栈用过的同义名（补装时命中就不重复插入）。
  final List<String> aliases;
}

/// 预置支出分类（11 个，一级）。
///
/// 与任务书建议的差异：**「其他支出」沿用既有名字「其他」** —— 老账本里已经是「其他」，
/// 改成「其他支出」会让老用户同时看到两个「其他」。收支靠 `kind` 区分（`(kind, name)` 才是唯一口径）。
const List<PresetCategory> presetExpense = <PresetCategory>[
  PresetCategory('餐饮', 'food', '#FF8A3D', aliases: <String>['吃饭']),
  PresetCategory('交通', 'transport', '#5A8DFF', aliases: <String>['出行']),
  PresetCategory('购物', 'shopping', '#FF6B8A'),
  PresetCategory('居住', 'home', '#B18CFF', aliases: <String>['房租']),
  PresetCategory('娱乐', 'entertainment', '#F06FC0'),
  PresetCategory('医疗', 'medical', '#4DC9C0'),
  PresetCategory('教育', 'education', '#5FD068'),
  PresetCategory('人情社交', 'social', '#FFB627', aliases: <String>['人情']),
  PresetCategory('旅行', 'travel', '#5A8DFF'),
  PresetCategory('通讯', 'phone', '#9AA5B1'),
  PresetCategory('其他', 'other', '#9AA5B1'),
];

/// 预置收入分类（7 个，一级）。
const List<PresetCategory> presetIncome = <PresetCategory>[
  PresetCategory('工资', 'salary', '#5FD068'),
  PresetCategory('奖金', 'bonus', '#FFB627'),
  PresetCategory('兼职', 'parttime', '#4DC9C0'),
  PresetCategory('投资收益', 'invest', '#5A8DFF', aliases: <String>['理财']),
  PresetCategory('退款', 'refund', '#9AA5B1'),
  PresetCategory('红包礼金', 'redpacket', '#FF6B8A', aliases: <String>['红包']),
  PresetCategory('其他', 'other', '#9AA5B1'),
];

/// 账户类型枚举值。
const accountTypes = ['cash', 'bank', 'credit', 'alipay', 'wechat', 'other'];

/// 默认币种。
const defaultCurrency = 'CNY';

/// 默认账本名。
const defaultBookName = '默认账本';

/// 默认现金账户名（新建账本时自动带一个）。
const defaultAccountName = '现金';
