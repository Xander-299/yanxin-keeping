/// 数据层「首次使用」验收探针（跑在**不依赖 Flutter** 的纯 Dart VM 里）。
///
/// 由 `tool/data_layer_probe.py` 驱动：它会复制一份 `lib/` 到 `.dart_tool/`
/// 下的临时包，把 `core/db/database.dart` 的 drift_flutter 换成内存库
/// （drift_flutter → path_provider → dart:ui，纯 Dart VM 载不进来），
/// 再执行本文件。用**真实仓储 + 真实聚合代码**跑一遍零配置新用户的数据链路：
///
///   冷启动 ensureDefaultBook → 记第一笔 → 首页汇总 → 报表三档 → 边界 → 性能
///
/// 为什么要这样绕：本机 Dart VM 起不了「需要管道 stdio」的子进程（命名管道
/// `CreateFile failed 231`）→ `flutter test` 不可用。详见 `HANDOFF.md`。
library;

// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/core/utils/date.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/data/repositories/book_repository.dart';
import 'package:yanxin/data/repositories/category_repository.dart';
import 'package:yanxin/data/repositories/transaction_repository.dart';
import 'package:yanxin/features/ledger/application/month_summary.dart';
import 'package:yanxin/features/reports/application/report_aggregate.dart';

final List<String> _failures = <String>[];

void _check(String what, bool pass, String detail) {
  print('${pass ? '  [PASS]' : '  [FAIL]'} $what — $detail');
  if (!pass) _failures.add(what);
}

void _head(String s) => print('\n=== $s ===');

Future<void> main() async {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  print('sqlite3 native: ${sqlite3.version} (winsqlite3.dll)');

  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  final books = BookRepository(db);
  final accounts = AccountRepository(db);
  final categories = CategoryRepository(db);
  final txs = TransactionRepository(db);

  // ---------------------------------------------------------------- 冷启动
  _head('S1 冷启动：零配置新用户第一次打开（空库）');
  final int t0 = DateTime.now().millisecondsSinceEpoch;
  final Book book = await books.ensureDefaultBook();
  final int coldMs = DateTime.now().millisecondsSinceEpoch - t0;
  print('  账本：${book.name}  冷启动耗时 ${coldMs}ms');
  _check('冷启动自动建账本', book.name == '默认账本', 'name=${book.name}');

  final List<Account> accs = await accounts.listByBook(book.id);
  print('  账户（${accs.length}）：${accs.map((Account a) => '${a.name}[${a.type}]').join(', ')}');
  _check(
    '冷启动自动带 1 个现金账户',
    accs.length == 1 && accs.first.name == '现金',
    '${accs.length} 个：${accs.map((Account a) => a.name).join('/')}',
  );

  final List<Category> exps = await categories.listByBook(book.id, kind: 'expense');
  final List<Category> incs = await categories.listByBook(book.id, kind: 'income');
  print('  支出分类（${exps.length}）：${exps.map((Category c) => c.name).join(' ')}');
  print('  收入分类（${incs.length}）：${incs.map((Category c) => c.name).join(' ')}');
  _check(
    '冷启动预置分类 9 支出 + 6 收入',
    exps.length == 9 && incs.length == 6,
    'expense=${exps.length} income=${incs.length}',
  );
  print(
    '  → 记一笔页首帧可用性：账户=${accs.isNotEmpty}，分类=${exps.isNotEmpty}'
    '（两者都非空 = 用户不必先去建账户 / 分类）',
  );

  // ------------------------------------------------- 记第一笔（expense）
  _head('S2 记第一笔：支出 ¥33.50 餐饮（现金账户）');
  final DateTime now = DateTime.now();
  final int today = DateTime(now.year, now.month, now.day, 12).millisecondsSinceEpoch;
  final TxRow t1 = await txs.create(
    bookId: book.id,
    accountId: accs.first.id,
    type: 'expense',
    categoryId: exps.firstWhere((Category c) => c.name == '餐饮').id,
    amountCents: 3350,
    occurredAt: today,
    note: '午饭',
  );
  print(
    '  已入账：${t1.type} ${centsToYuan(t1.amountCents)} '
    '${formatFullDay(DateTime.fromMillisecondsSinceEpoch(t1.occurredAt))} 备注「${t1.note}」',
  );

  final Category traffic = exps.firstWhere((Category c) => c.name == '交通');
  final Category salary = incs.firstWhere((Category c) => c.name == '工资');
  final Account bank = await accounts.create(
    bookId: book.id,
    name: '招行卡',
    type: 'bank',
  );
  await txs.create(
    bookId: book.id,
    accountId: accs.first.id,
    type: 'expense',
    categoryId: traffic.id,
    amountCents: 1200,
    occurredAt: today,
  );
  await txs.create(
    bookId: book.id,
    accountId: bank.id,
    type: 'income',
    categoryId: salary.id,
    amountCents: 20000,
    occurredAt: today,
  );
  await txs.create(
    bookId: book.id,
    accountId: bank.id,
    type: 'transfer',
    amountCents: 5000,
    occurredAt: today,
  );
  print('  再加：交通 ¥12.00 / 工资 ¥200.00（招行卡）/ 转账 ¥50.00');

  // ------------------------------------------------------------- 首页汇总
  _head('S3 首页 hero 汇总（listByMonth + summarize）');
  final List<TxRow> month = await txs.listByMonth(book.id, now.year, now.month);
  final MonthSummary sum = summarize(month);
  print('  ${now.year}年${now.month}月 · ${month.length} 笔');
  print('  支出 ${sum.expenseYuan} · 收入 ${sum.incomeYuan} · 结余 ${sum.balanceYuan}');
  _check('首页支出口径 = 33.50 + 12.00（转账不计）', sum.expenseCents == 4550,
      'expenseCents=${sum.expenseCents}');
  _check('首页收入口径 = 200.00', sum.incomeCents == 20000,
      'incomeCents=${sum.incomeCents}');
  final List<DayGroup<TxRow>> days =
      groupByDay<TxRow>(month, (TxRow t) => t.occurredAt);
  print(
    '  明细按天分组（${days.length} 组）：'
    '${days.map((DayGroup<TxRow> g) => '${g.label}×${g.items.length}').join(', ')}',
  );
  _check('明细档日标签可用', reportDayLabel(today).isNotEmpty, reportDayLabel(today));

  // --------------------------------------------------------- 报表页 分类档
  _head('S4 报表页「分类」档（首页 header 入口的默认档）');
  final List<Category> allCats = await categories.listByBook(book.id);
  final Map<String, String> catNames = <String, String>{
    for (final Category c in allCats) c.id: c.name,
  };
  String nameOf(String? id) => (id == null ? null : catNames[id]) ?? kUncategorized;
  for (final ReportGroup g
      in groupByCategory(month, type: kReportExpense, nameOf: nameOf)) {
    print('  支出段 · ${g.title}  ${centsToYuan(g.expenseCents)}  ${g.txCount} 笔');
  }
  for (final ReportGroup g
      in groupByCategory(month, type: kReportIncome, nameOf: nameOf)) {
    print('  收入段 · ${g.title}  ${centsToYuan(g.incomeCents)}  ${g.txCount} 笔');
  }
  final List<TxRow> transfers = transferRows(month);
  print(
    '  转账单列段：${transfers.length} 笔 '
    '合计 ${centsToYuan(sumCentsOf(month, kReportTransfer))}',
  );
  final List<ReportGroup> expGroups =
      groupByCategory(month, type: kReportExpense, nameOf: nameOf);
  _check('分类档支出合并成 2 组（餐饮 / 交通）', expGroups.length == 2,
      expGroups.map((ReportGroup g) => g.title).join('/'));
  _check('分类档转账单列（不进支出）', transfers.length == 1, '${transfers.length} 笔');

  // --------------------------------------------------------- 报表页 账户档
  _head('S5 报表页「账户」档');
  final List<Account> allAccs = await accounts.listByBook(book.id);
  final Map<String, String> accNames = <String, String>{
    for (final Account a in allAccs) a.id: a.name,
  };
  String accNameOf(String id) => accNames[id] ?? kOtherAccountTitle;
  final List<ReportGroup> accGroups = groupByAccount(
    month,
    knownAccountIds: accNames.keys.toSet(),
    nameOf: accNameOf,
  );
  for (final ReportGroup g in accGroups) {
    print(
      '  ${g.title}  支出 ${centsToYuan(g.expenseCents)} / '
      '收入 ${centsToYuan(g.incomeCents)} / 转账 ${centsToYuan(g.transferCents)}  '
      '${g.txCount} 笔',
    );
  }
  _check('账户档 2 组（现金 / 招行卡）', accGroups.length == 2,
      accGroups.map((ReportGroup g) => g.title).join('/'));
  _check('账户档按合计降序（招行卡 250.00 > 现金 45.50）',
      accGroups.first.title == '招行卡', accGroups.first.title);
  _check(
    '每行四向数值自洽',
    accGroups.every((ReportGroup g) =>
        g.totalCents == g.expenseCents + g.incomeCents + g.transferCents),
    'ok',
  );

  // ------------------------------------------------------------ 边界/软删
  _head('S6 边界：账户被软删后其流水归「其他账户」');
  await accounts.softDelete(bank.id);
  final List<Account> alive = await accounts.listByBook(book.id);
  final Map<String, String> aliveNames = <String, String>{
    for (final Account a in alive) a.id: a.name,
  };
  String aliveNameOf(String id) => aliveNames[id] ?? kOtherAccountTitle;
  final List<ReportGroup> after = groupByAccount(
    month,
    knownAccountIds: aliveNames.keys.toSet(),
    nameOf: aliveNameOf,
  );
  for (final ReportGroup g in after) {
    print('  ${g.title}  ${g.txCount} 笔  合计 ${centsToYuan(g.totalCents)}');
  }
  _check('软删账户的流水归并到「其他账户」',
      after.any((ReportGroup g) => g.title == kOtherAccountTitle),
      after.map((ReportGroup g) => g.title).join('/'));

  _head('S7 边界：空月份（新用户翻到上月）');
  final List<TxRow> empty = await txs.listByMonth(book.id, now.year - 1, 1);
  _check('空月份返回空列表（页面进空态）', empty.isEmpty, '${empty.length} 笔');

  _head('S8 边界：单组 250 笔 > kReportDetailLimit');
  final Category other = exps.firstWhere((Category c) => c.name == '其他');
  for (int i = 0; i < 250; i++) {
    await txs.create(
      bookId: book.id,
      accountId: alive.first.id,
      type: 'expense',
      categoryId: other.id,
      amountCents: 100,
      occurredAt: today - i * 1000,
    );
  }
  final List<TxRow> bulk = await txs.listByMonth(book.id, now.year, now.month);
  final ReportGroup otherGroup =
      groupByCategory(bulk, type: kReportExpense, nameOf: nameOf)
          .firstWhere((ReportGroup g) => g.title == '其他');
  print('  「其他」组内 ${otherGroup.txCount} 笔'
      '（渲染上限 $kReportDetailLimit，超出截断 + 尾注）');
  _check('组内笔数完整（截断在渲染层）', otherGroup.txCount == 250,
      '${otherGroup.txCount} 笔');

  _head('S9 性能：全月 ${bulk.length} 笔的报表聚合耗时');
  final int aggStart = DateTime.now().millisecondsSinceEpoch;
  groupByCategory(bulk, type: kReportExpense, nameOf: nameOf);
  groupByAccount(
    bulk,
    knownAccountIds: aliveNames.keys.toSet(),
    nameOf: aliveNameOf,
  );
  print('  聚合耗时 ${DateTime.now().millisecondsSinceEpoch - aggStart}ms');

  await db.close();

  print('\n================ 结果 ================');
  if (_failures.isEmpty) {
    print('全部断言通过（0 失败）');
  } else {
    print('失败 ${_failures.length} 项：');
    for (final String f in _failures) {
      print('  - $f');
    }
  }
  exitCode = _failures.isEmpty ? 0 : 1;
}
