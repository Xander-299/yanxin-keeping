/// 预置数据与枚举常量（对应旧栈 `src/constants/preset.js`）。
///
/// 预置分类在**新建账本**时写入（`is_preset=1`）；老账本由
/// `CategoryRepository.ensurePresets()` 按名字幂等补齐（见 schema v4）。
///
/// 2026-10-29 起预置分类带**二级子分类**（`PresetCategory.children`）：
/// 一级是「场景大类」（餐饮 / 交通 …），二级是「怎么花的」（早餐 / 地铁 …）。
/// 二级同样是 `is_preset=1`，用户可改名 / 归档 / 删除（删除后不会被补装复活）。
///
/// 每个预置分类带**稳定图标 key** 与颜色（`core/constants/category_icons.dart`），
/// `aliases` 用于「老账本里叫旧名字」的匹配：例如老账本的「理财」对应新预置「投资收益」，
/// 补装时命中别名就不再插一条，避免同一个含义出现两个分类。
library;

/// 一个预置二级分类（挂在某个一级分类下）。
class PresetChild {
  const PresetChild(
    this.name,
    this.iconKey, {
    this.aliases = const <String>[],
  });

  final String name;
  final String iconKey;

  /// 同义名（补装时命中就不重复插入）。
  final List<String> aliases;
}

/// 一个预置分类。
class PresetCategory {
  const PresetCategory(
    this.name,
    this.iconKey,
    this.color, {
    this.aliases = const <String>[],
    this.children = const <PresetChild>[],
  });

  final String name;
  final String iconKey;
  final String color;

  /// 老版本 / 旧栈用过的同义名（补装时命中就不重复插入）。
  final List<String> aliases;

  /// 预置的二级分类（**只需在「一级」写**，子分类颜色跟随父级）。
  final List<PresetChild> children;
}

/// 预置支出分类（11 个，一级；其中 10 个带二级）。
///
/// 与任务书建议的差异：**「其他支出」沿用既有名字「其他」** —— 老账本里已经是「其他」，
/// 改成「其他支出」会让老用户同时看到两个「其他」。收支靠 `kind` 区分（`(kind, name)` 才是唯一口径）。
///
/// 二级的取舍：
/// - 只给「支出」加二级 —— 收入一级本身已经够细（工资 / 奖金 / 投资收益…），再加一层是纯噪音；
/// - 「其他」保持无子分类（它就是兜底的，再分下去就失去了兜底的意义）；
/// - 名字用**记账时的口语**（早餐 / 地铁 / 话费），不用书面语（餐饮消费 / 城市轨道交通）。
const List<PresetCategory> presetExpense = <PresetCategory>[
  PresetCategory(
    '餐饮',
    'food',
    '#FF8A3D',
    aliases: <String>['吃饭'],
    children: <PresetChild>[
      PresetChild('早餐', 'breakfast'),
      PresetChild('午餐', 'lunch'),
      PresetChild('晚餐', 'dinner'),
      PresetChild('饮料', 'coffee', aliases: <String>['咖啡', '奶茶']),
      PresetChild('零食', 'snack'),
    ],
  ),
  PresetCategory(
    '交通',
    'transport',
    '#5A8DFF',
    aliases: <String>['出行'],
    children: <PresetChild>[
      PresetChild('地铁', 'transport', aliases: <String>['公交地铁']),
      PresetChild('公交', 'bus'),
      PresetChild('打车', 'taxi', aliases: <String>['网约车']),
      PresetChild('共享单车', 'bike', aliases: <String>['单车']),
      PresetChild('加油', 'fuel'),
    ],
  ),
  PresetCategory(
    '购物',
    'shopping',
    '#FF6B8A',
    children: <PresetChild>[
      PresetChild('服饰', 'clothes'),
      PresetChild('数码', 'digital'),
      PresetChild('日用品', 'shopping'),
    ],
  ),
  PresetCategory(
    '居住',
    'home',
    '#B18CFF',
    aliases: <String>['房租'],
    children: <PresetChild>[
      PresetChild('房租', 'rent'),
      PresetChild('水电燃气', 'utility', aliases: <String>['水电']),
      PresetChild('家居', 'home'),
    ],
  ),
  PresetCategory(
    '娱乐',
    'entertainment',
    '#F06FC0',
    children: <PresetChild>[
      PresetChild('电影', 'movie'),
      PresetChild('游戏', 'entertainment'),
      PresetChild('健身', 'fitness'),
    ],
  ),
  PresetCategory(
    '医疗',
    'medical',
    '#4DC9C0',
    children: <PresetChild>[
      PresetChild('门诊', 'medical'),
      PresetChild('药品', 'medicine'),
      PresetChild('体检', 'insurance', aliases: <String>['检查']),
    ],
  ),
  PresetCategory(
    '教育',
    'education',
    '#5FD068',
    children: <PresetChild>[
      PresetChild('学费', 'education'),
      PresetChild('书籍', 'book'),
      PresetChild('培训', 'school', aliases: <String>['课程']),
    ],
  ),
  PresetCategory(
    '人情社交',
    'social',
    '#FFB627',
    aliases: <String>['人情'],
    children: <PresetChild>[
      PresetChild('送礼', 'social'),
      PresetChild('请客', 'food'),
      PresetChild('红包', 'redpacket'),
    ],
  ),
  PresetCategory(
    '旅行',
    'travel',
    '#5A8DFF',
    children: <PresetChild>[
      PresetChild('机票', 'flight'),
      PresetChild('住宿', 'hotel'),
      PresetChild('门票', 'travel'),
    ],
  ),
  PresetCategory(
    '通讯',
    'phone',
    '#9AA5B1',
    children: <PresetChild>[
      PresetChild('话费', 'phone'),
      PresetChild('宽带', 'internet'),
    ],
  ),
  PresetCategory('其他', 'other', '#9AA5B1'),
];

/// 预置收入分类（7 个，一级）—— 刻意**不带二级**（见 [presetExpense] 的取舍说明）。
const List<PresetCategory> presetIncome = <PresetCategory>[
  PresetCategory('工资', 'salary', '#5FD068'),
  PresetCategory('奖金', 'bonus', '#FFB627'),
  PresetCategory('兼职', 'parttime', '#4DC9C0'),
  PresetCategory('投资收益', 'invest', '#5A8DFF', aliases: <String>['理财']),
  PresetCategory('退款', 'refund', '#9AA5B1'),
  PresetCategory('红包礼金', 'redpacket', '#FF6B8A', aliases: <String>['红包']),
  PresetCategory('其他', 'other', '#9AA5B1'),
];

/// 预置二级分类总数（测试与文档的单一口径）。
int get presetChildCount {
  int total = 0;
  for (final PresetCategory preset in <PresetCategory>[
    ...presetExpense,
    ...presetIncome,
  ]) {
    total += preset.children.length;
  }
  return total;
}

/// 账户类型枚举值。
const accountTypes = ['cash', 'bank', 'credit', 'alipay', 'wechat', 'other'];

/// 默认币种。
const defaultCurrency = 'CNY';

/// 默认账本名。
const defaultBookName = '默认账本';

/// 默认现金账户名（新建账本时自动带一个）。
const defaultAccountName = '现金';
