/// 数据版本号：任何写操作（记一笔 / 导入 / 删流水 / 账户增删改）成功后 +1。
///
/// 存在的理由：HANDOFF 记载过「漏刷 `statsProvider` 出 bug」——
/// 逐个 provider 手工 `refresh()` 是已知脆弱点，新增一个消费方就要补 N 处调用。
/// 改为 watch 一个版本号后，写操作只需 bump 一行，新页面接入零成本。
///
/// 当前只有资产页 watch 它；stats / calendar / ledger 的既有 refresh 调用本次不动（避免回归）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 数据版本号。值本身无意义，只用于「变了就重算」。
final dataEpochProvider = NotifierProvider<DataEpoch, int>(DataEpoch.new);

class DataEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// 写操作成功后调用：让 watch 了它的 provider 重新取数。
  void bump() => state++;
}
