/// 账单 profile — 旧栈 `bill-import/profiles/*.js` 的合并移植。
///
/// 同时覆盖两种导出格式：
/// - 微信旧版 CSV：文本时间、¥ 前缀金额
/// - 微信 2025+ xlsx：时间列为 Excel 序列号、纯数字金额
/// - 支付宝「交易记录明细查询」旧版 CSV /「电子客户回单」新版 CSV（GBK）
///
/// 列名一律用半角括号书写；表头匹配时全角括号会被归一化（normCell），
/// 所以「金额(元)」与「金额（元）」天然等价，不需要逐个别名。
library;

/// 账单来源标识（与旧栈/指纹算法共享同一套字符串）。
const sourceWechat = 'wechat_csv';
const sourceAlipay = 'alipay_csv';

/// 平台账单解析配置（「解析五层」第 2 层）。
class BillProfile {
  const BillProfile({
    required this.source,
    required this.name,
    required this.required,
    required this.columns,
    required this.directionMap,
    required this.statusWhitelist,
    required this.blacklistKeywords,
  });

  /// 来源标识，写入 transactions.source，参与指纹计算。
  final String source;

  /// 平台名（错误提示用）。
  final String name;

  /// 必需列：缺任何一个即判定「不是有效的该平台账单文件」。
  final List<String> required;

  /// canonical 列名 -> 表头列名（数组时按序回退）。
  final Map<String, List<String>> columns;

  /// 收/支 -> 方向；中性取值映射为 'skip'。
  final Map<String, String> directionMap;

  /// 状态白名单（精确匹配）；未命中白名单且未命中黑名单 = 未知状态，默认导入并标记。
  final List<String> statusWhitelist;

  /// 状态黑名单关键词（包含匹配），命中即跳过；含「已退款¥x」与「已全额退款」。
  final List<String> blacklistKeywords;
}

const wechatProfile = BillProfile(
  source: sourceWechat,
  name: '微信支付',
  required: ['交易时间', '收/支', '金额(元)', '当前状态', '交易单号'],
  columns: {
    'occurredAt': ['交易时间'],
    'direction': ['收/支'],
    'amount': ['金额(元)'],
    'status': ['当前状态'],
    'externalId': ['交易单号'],
    'counterparty': ['交易对方'],
    'product': ['商品'],
    'method': ['支付方式'],
  },
  // '/' 与「中性交易」（充值、提现、理财通等内部流转）均跳过
  directionMap: {
    '支出': 'expense',
    '收入': 'income',
    '/': 'skip',
    '中性交易': 'skip',
  },
  statusWhitelist: [
    '支付成功', '已存入零钱', '对方已收钱', '已转账',
    '充值完成', '已支付', '已收钱', '转账成功',
  ],
  blacklistKeywords: ['关闭', '退款', '失败', '失效'],
);

const alipayProfile = BillProfile(
  source: sourceAlipay,
  name: '支付宝',
  required: ['收/支', '交易状态'],
  columns: {
    // 付款时间为空时回退交易创建时间（旧版）；新版为「交易时间」
    'occurredAt': ['付款时间', '交易创建时间', '交易时间'],
    'direction': ['收/支'],
    'amount': ['金额(元)', '金额'],
    'status': ['交易状态'],
    'externalId': ['交易号', '交易订单号'],
    'counterparty': ['交易对方', '对方账号'],
    'product': ['商品名称', '商品说明'],
    'method': ['收/付款方式', ''],
  },
  directionMap: {
    '支出': 'expense',
    '收入': 'income',
    '不计收支': 'skip',
  },
  // 「等待确认收货」= 已付款未确认收货，钱已出，照常入账
  statusWhitelist: [
    '交易成功', '支付成功', '还款成功', '解冻成功', '代付成功', '等待确认收货',
  ],
  blacklistKeywords: ['关闭', '退款', '失败', '失效'],
);

/// profile 探测顺序：先微信后支付宝，必需列不全即判定不匹配。
const billProfiles = <BillProfile>[wechatProfile, alipayProfile];
