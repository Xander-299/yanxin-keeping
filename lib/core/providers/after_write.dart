/// 写操作之后的统一刷新（F8.1 收口）。
///
/// 为什么单独抽出来：HANDOFF 不变量 #2 —— 常驻 provider 必须收到失效信号，
/// 否则「刚记一笔后搜索搜不到」这类过期快照 bug 会回来。这段刷新现在有三处调用方
/// （首页手工保存 / 自动记账 / 截图记账），逐处复制是**已知脆弱点**（漏一个就出 bug）。
///
/// 两个入口只是因为 `Ref`（Notifier 内）与 `WidgetRef`（Widget 内）是两个无关类型，
/// 刷新口径必须一致 —— 改这里就等于改全部调用方。
///
/// ⚠️ 全部刷新**吞异常**：写入是主流程，刷新失败绝不能冒泡成未捕获异步异常
/// （测试里库已 close、页面上 provider 还没建都会命中）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/features/calendar/application/calendar_controller.dart';
import 'package:yanxin/features/ledger/application/ledger_controller.dart';
import 'package:yanxin/features/stats/application/stats_controller.dart';

/// Notifier / Provider 内部调用（`Ref`）。
void refreshAfterWrite(Ref ref) {
  ref.invalidate(yearDayIndexProvider);
  unawaited(
    ref.read(calendarProvider.notifier).refresh().catchError((Object _) {}),
  );
  unawaited(ref.read(statsProvider.notifier).refresh().catchError((Object _) {}));
  unawaited(
    ref.read(ledgerProvider.notifier).refresh().catchError((Object _) {}),
  );
  ref.read(dataEpochProvider.notifier).bump();
}

/// Widget 内部调用（`WidgetRef`）—— 口径与 [refreshAfterWrite] 完全一致。
void refreshAfterWriteFromWidget(WidgetRef ref) {
  ref.invalidate(yearDayIndexProvider);
  unawaited(
    ref.read(calendarProvider.notifier).refresh().catchError((Object _) {}),
  );
  unawaited(ref.read(statsProvider.notifier).refresh().catchError((Object _) {}));
  unawaited(
    ref.read(ledgerProvider.notifier).refresh().catchError((Object _) {}),
  );
  ref.read(dataEpochProvider.notifier).bump();
}
