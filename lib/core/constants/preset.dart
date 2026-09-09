/// 预置数据与枚举常量（对应旧栈 src/constants/preset.js）。
///
/// 预置分类在新建账本时自动写入，is_preset=1 不可删（用户可改名/改图标）。
library;

/// 预置支出分类（9 个）。
const presetExpense = [
  '餐饮',
  '交通',
  '购物',
  '居住',
  '娱乐',
  '医疗',
  '教育',
  '人情',
  '其他',
];

/// 预置收入分类（6 个）。
const presetIncome = ['工资', '奖金', '理财', '兼职', '红包', '其他'];

/// 账户类型枚举值。
const accountTypes = ['cash', 'bank', 'credit', 'alipay', 'wechat', 'other'];

/// 默认币种。
const defaultCurrency = 'CNY';

/// 默认账本名。
const defaultBookName = '默认账本';

/// 默认现金账户名（新建账本时自动带一个）。
const defaultAccountName = '现金';
