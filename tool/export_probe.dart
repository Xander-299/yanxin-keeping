/// 数据导出纯函数的「脱离 flutter_tester」实跑探针（F7.7 B 批）。
///
/// 与 `test/features/export/csv_export_test.dart` **同口径**，但能在纯 Dart VM 里跑
/// （本机 Dart 起不了需要管道 stdio 的子进程 → `flutter test` 不可用，见 HANDOFF 第 1 条）。
///
/// 跑法：
///     python tool/data_layer_probe.py --script tool/export_probe.dart
///
/// 断言内容与单测一致，但这里只保留「会真出错」的部分；单测仍是正式门禁。
// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/budget_repository.dart';
import 'package:yanxin/features/export/application/csv_export.dart';

final int _nowMs = DateTime(2026, 9, 23, 16, 30, 5).millisecondsSinceEpoch;

int _pass = 0;
int _fail = 0;

void check(String label, Object? actual, Object? expected) {
  final bool ok = '$actual' == '$expected';
  if (ok) {
    _pass++;
    print('  ✅ $label');
  } else {
    _fail++;
    print('  ❌ $label\n      期望：$expected\n      实际：$actual');
  }
}

void checkTrue(String label, bool ok) => check(label, ok, true);

TxRow tx({
  String id = 't1',
  String accountId = 'a1',
  String? categoryId,
  String type = 'expense',
  required int cents,
  String note = '',
  String source = 'manual',
  int? at,
}) {
  final int ts = at ?? _nowMs;
  return TxRow(
    id: id,
    bookId: 'b1',
    accountId: accountId,
    categoryId: categoryId,
    type: type,
    amountCents: cents,
    note: note,
    occurredAt: ts,
    source: source,
    createdAt: ts,
    updatedAt: ts,
    dirty: 1,
  );
}

const Map<String, String> catNames = <String, String>{'c1': '餐饮', 'c2': '交通'};
const Map<String, String> accNames = <String, String>{'a1': '现金', 'a2': '工资卡'};

void main() async {
  print('[export] CSV');

  final empty = buildBillCsv(rows: <TxRow>[]);
  check('空账本 = 只有表头（含 BOM）', empty, '$kUtf8Bom$kBillCsvHeader');
  check('空账本没有换行', empty.contains('\r\n'), false);
  check('BOM 码位是 0xFEFF', empty.codeUnitAt(0), 0xFEFF);

  final one = buildBillCsv(
    rows: <TxRow>[
      tx(
        categoryId: 'c1',
        cents: 1234,
        note: '午饭',
        source: 'wechat_csv',
        at: DateTime(2026, 9, 23, 12, 5).millisecondsSinceEpoch,
      ),
    ],
    categoryNames: catNames,
    accountNames: accNames,
  );
  check(
    '整行内容（日期/类型/金额/分类/账户/备注/来源）',
    one.split('\r\n').last,
    '2026-09-23 12:05,支出,12.34,餐饮,现金,午饭,wechat_csv',
  );

  final mixed = buildBillCsv(
    rows: <TxRow>[
      tx(id: 'i1', type: 'income', cents: 100000, categoryId: 'c2'),
      tx(id: 'x1', type: 'transfer', cents: 5000),
      tx(id: 't2', categoryId: null, cents: 100, accountId: 'a9'),
    ],
    categoryNames: catNames,
    accountNames: accNames,
  );
  final List<String> lines = mixed.split('\r\n');
  check('收入 1000.00 且无符号', lines[1].contains(',收入,1000.00,交通,现金,,manual'), true);
  check('转账行分类列留空', lines[2].contains(',转账,50.00,,现金,,manual'), true);
  check('分类/账户查不到名字 → 留空', lines[3].contains(',支出,1.00,,,'), true);
  check('行数 = 表头 + 3', lines.length, 4);

  final quoted = buildBillCsv(
    rows: <TxRow>[tx(categoryId: 'c1', cents: 100, note: '买菜,顺便\n取快递')],
    categoryNames: catNames,
    accountNames: accNames,
  );
  check('内嵌换行被引号包住（CRLF 仍只有表头那一个）', '\r\n'.allMatches(quoted).length, 1);
  check('备注里的换行保留', quoted.contains('"买菜,顺便\n取快递"'), true);
  check('转义：逗号', csvField('a,b'), '"a,b"');
  check('转义：引号翻倍', csvField('说"好"'), '"说""好"""');
  check('转义：普通值不加引号', csvField('普通'), '普通');
  check('日期零填充', formatCsvDateTime(DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch), '2026-01-02 03:04');
  check('未知类型原样输出', billTypeLabel('weird'), 'weird');

  print('[export] 文件名');

  check('正常', exportFileName(bookName: '默认账本', ext: 'csv', nowMs: _nowMs), '颜芯记账_默认账本_20260923.csv');
  check('非法字符换下划线', exportFileName(bookName: 'a/b:c*d?e"f<g>h|i', ext: 'json', nowMs: _nowMs), '颜芯记账_a_b_c_d_e_f_g_h_i_20260923.json');
  check('空名退回「账本」', exportFileName(bookName: '   ', ext: 'csv', nowMs: _nowMs), '颜芯记账_账本_20260923.csv');
  check('跨年零填充', exportFileName(bookName: 'x', ext: 'csv', nowMs: DateTime(2026, 1, 5).millisecondsSinceEpoch), '颜芯记账_x_20260105.csv');

  print('[export] 备份 JSON');

  final String json = buildBackupJson(
    book: Book(
      id: 'b1',
      name: '默认账本',
      type: 'personal',
      currency: 'CNY',
      icon: '',
      color: '',
      sortOrder: 0,
      createdAt: _nowMs,
      updatedAt: _nowMs,
      dirty: 0,
    ),
    accounts: <Account>[
      Account(
        id: 'a1',
        bookId: 'b1',
        name: '现金',
        type: 'cash',
        initialBalanceCents: 0,
        sortOrder: 0,
        icon: '',
        color: '',
        createdAt: _nowMs,
        updatedAt: _nowMs,
        dirty: 1,
      ),
      Account(
        id: 'a2',
        bookId: 'b1',
        name: '工资卡',
        type: 'bank',
        initialBalanceCents: 0,
        sortOrder: 1,
        icon: '',
        color: '',
        createdAt: _nowMs,
        updatedAt: _nowMs,
        dirty: 1,
      ),
    ],
    categories: <Category>[
      Category(
        id: 'c1',
        bookId: 'b1',
        name: '餐饮',
        kind: 'expense',
        icon: '',
        color: '',
        sortOrder: 0,
        isPreset: 1,
        createdAt: _nowMs,
        updatedAt: _nowMs,
        dirty: 1,
      ),
    ],
    transactions: <TxRow>[tx(categoryId: 'c1', cents: 1234)],
    budgets: <BudgetRow>[
      BudgetRow(
        id: 'g1',
        bookId: 'b1',
        period: '2026-09',
        amountCents: 300000,
        createdAt: _nowMs,
        updatedAt: _nowMs,
        dirty: 1,
      ),
    ],
    exportedAtMs: _nowMs,
  );
  final Map<String, Object?> m = jsonDecode(json) as Map<String, Object?>;
  check(
    '顶层键顺序与个数',
    m.keys.join(','),
    'schemaVersion,exportedAt,book,accounts,categories,transactions,budgets',
  );
  check('schemaVersion', m['schemaVersion'], 2);
  check('book.name', (m['book']! as Map<String, Object?>)['name'], '默认账本');
  check('accounts 数量', (m['accounts']! as List<Object?>).length, 2);
  check('categories 数量', (m['categories']! as List<Object?>).length, 1);
  check('budgets 数量', (m['budgets']! as List<Object?>).length, 1);

  final Map<String, Object?> t0 =
      (m['transactions']! as List<Object?>).first as Map<String, Object?>;
  check('流水金额是整数分', t0['amountCents'], 1234);
  check('流水不含 dirty', t0.containsKey('dirty'), false);
  check(
    '流水字段齐全',
    t0.keys.join(','),
    'id,bookId,accountId,categoryId,type,amountCents,note,occurredAt,'
        'transferGroupId,source,fingerprint,ownerId,createdAt,updatedAt',
  );
  final Map<String, Object?> b0 =
      (m['budgets']! as List<Object?>).first as Map<String, Object?>;
  check('预算 period + 整数分', '${b0['period']}/${b0['amountCents']}', '2026-09/300000');

  final String at = m['exportedAt']! as String;
  check('exportedAt 本地时间', at.startsWith('2026-09-23T16:30:05'), true);
  checkTrue('exportedAt 带时区偏移', RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(at));

  final Map<String, Object?> emptyJson = jsonDecode(
    buildBackupJson(
      book: Book(
        id: 'b1',
        name: '空账本',
        type: 'personal',
        currency: 'CNY',
        icon: '',
        color: '',
        sortOrder: 0,
        createdAt: _nowMs,
        updatedAt: _nowMs,
        dirty: 0,
      ),
      accounts: <Account>[],
      categories: <Category>[],
      transactions: <TxRow>[],
      budgets: <BudgetRow>[],
      exportedAtMs: _nowMs,
    ),
  ) as Map<String, Object?>;
  check('空账本：transactions 为空数组', (emptyJson['transactions']! as List<Object?>).isEmpty, true);
  check('空账本：budgets 为空数组', (emptyJson['budgets']! as List<Object?>).isEmpty, true);

  print('[export] UTF-8 字节');

  final List<int> bytes = utf8Bytes(buildBillCsv(rows: <TxRow>[]));
  check('BOM 三字节', bytes.sublist(0, 3).join(','), '239,187,191');
  // 注意：Dart 的 utf8 解码器会把开头的 BOM 吃掉（实测），所以这里断言的是
  // 「解码后以表头开头、且首字符不是 U+FEFF」——BOM 只保证在**字节**里。
  final String decoded = utf8.decode(bytes);
  checkTrue('解码后以表头开头（BOM 已被解码器吃掉）', decoded.startsWith(kBillCsvHeader));
  check('解码后首字符不是 U+FEFF', decoded.codeUnitAt(0) == 0xFEFF, false);

  print('[B] budgetRepository.listByBook（B 批新增，导出备份 JSON 用）');

  final AppDatabase db = openAppDatabase();
  final String bookId = (await BookRepository(db).ensureDefaultBook()).id;
  final BudgetRepository budgets = BudgetRepository(db);
  // 乱序写入，验证返回顺序按 period 升序而不是写入顺序
  await budgets.setForMonth(bookId: bookId, year: 2026, month: 10, amountCents: 3);
  await budgets.setForMonth(bookId: bookId, year: 2025, month: 12, amountCents: 1);
  await budgets.setForMonth(bookId: bookId, year: 2026, month: 1, amountCents: 2);
  final List<BudgetRow> rows = await budgets.listByBook(bookId);
  check('period 升序', rows.map((BudgetRow b) => b.period).join(','), '2025-12,2026-01,2026-10');
  check('金额随行对齐', rows.map((BudgetRow b) => b.amountCents).join(','), '1,2,3');

  await budgets.clearForMonth(bookId, 2026, 1);
  final List<BudgetRow> after = await budgets.listByBook(bookId);
  check('软删的不再返回', after.map((BudgetRow b) => b.period).join(','), '2025-12,2026-10');

  final String otherBookId = (await BookRepository(db).create(name: '另一本')).id;
  await budgets.setForMonth(bookId: otherBookId, year: 2026, month: 9, amountCents: 999);
  check('按账本隔离', (await budgets.listByBook(bookId)).length, 2);
  await db.close();

  print('');
  print('[export] 通过 $_pass / 失败 $_fail');
  if (_fail > 0) {
    throw StateError('导出探针有 $_fail 条断言失败');
  }
}