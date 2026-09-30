/// 自动记账的账户归属（F7.15 SPEC §3.3）—— 按来源自动建账户。
///
/// 写法照抄导入链路的 `ensureImportAccount`（先查同名、无则创建），
/// **不放进 `AccountRepository`** —— 仓储的定位是「只做数据读写与字段校验，不含业务规则」。
library;

import 'package:yanxin/core/db/database.dart';
import 'package:yanxin/data/repositories/account_repository.dart';
import 'package:yanxin/features/autobook/data/auto_book_rules.dart';

/// 确保账本下存在该来源对应的账户，返回其 id。
///
/// - `notify_wechat` → 「微信」
/// - `notify_alipay` → 「支付宝」
/// - `share` → 「分享记账」
Future<String> ensureSourceAccount(
  AccountRepository accountRepo,
  String bookId,
  String source,
) async {
  final String name = kSourceLabel[source] ?? '自动记账';
  final List<Account> accounts = await accountRepo.listByBook(bookId);
  for (final Account a in accounts) {
    if (a.name == name) return a.id;
  }
  final Account created = await accountRepo.create(
    bookId: bookId,
    name: name,
    type: 'other',
  );
  return created.id;}
