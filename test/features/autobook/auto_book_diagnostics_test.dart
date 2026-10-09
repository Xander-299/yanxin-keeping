/// `AutoBookDiagnostics` 的解析与**通道可用性判定**测试（F7.16）。
///
/// 为什么这组用例重要：2026-10-09 Redmi K50 实测发现「国产 ROM 不投递 posted 推送回调」，
/// 于是新增了 [AutoBookDiagnostics.postedChannelUnavailable] 与
/// [AutoBookDiagnostics.backgroundWakeWorks] 两个判定 —— 它们直接决定 `/autobook`
/// 页面给用户什么提示。判错 = 用户被误导去查错的方向。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yanxin/features/autobook/data/auto_book_diagnostics.dart';

/// 造一份完整快照，只覆盖给定字段（其余给合理默认）。
Map<String, Object?> _diag({
  bool listenerConnected = true,
  int lastConnectedAtMs = 1000000,
  int lastCaptureAtMs = 1000000,
  String lastCapturePkg = 'com.tencent.mm',
  int capturedTotal = 5,
  int skippedNotWatched = 10,
  int skippedEmpty = 0,
  int skippedDedup = 2,
  int skippedGroupSummary = 1,
  int lastDrainAtMs = 1000000,
  int lastDrainCount = 0,
  int drainedTotal = 5,
  int nowMs = 1000000,
  int lastCatchUpAtMs = 0,
  int lastCatchUpActive = 0,
  int lastCatchUpAdded = 0,
  int catchUpTotal = 0,
  int catchUpAddedTotal = 0,
  bool postedCallbackSeen = false,
  int lastPostedAtMs = 0,
  int removedCaptureTotal = 0,
  int lastRemovedAtMs = 0,
  int tickCatchUpTotal = 0,
  int lastTickCatchUpAtMs = 0,
}) {
  return <String, Object?>{
    'listenerConnected': listenerConnected,
    'lastConnectedAtMs': lastConnectedAtMs,
    'lastCaptureAtMs': lastCaptureAtMs,
    'lastCapturePkg': lastCapturePkg,
    'capturedTotal': capturedTotal,
    'skippedNotWatched': skippedNotWatched,
    'skippedEmpty': skippedEmpty,
    'skippedDedup': skippedDedup,
    'skippedGroupSummary': skippedGroupSummary,
    'lastDrainAtMs': lastDrainAtMs,
    'lastDrainCount': lastDrainCount,
    'drainedTotal': drainedTotal,
    'nowMs': nowMs,
    'lastCatchUpAtMs': lastCatchUpAtMs,
    'lastCatchUpActive': lastCatchUpActive,
    'lastCatchUpAdded': lastCatchUpAdded,
    'catchUpTotal': catchUpTotal,
    'catchUpAddedTotal': catchUpAddedTotal,
    'postedCallbackSeen': postedCallbackSeen,
    'lastPostedAtMs': lastPostedAtMs,
    'removedCaptureTotal': removedCaptureTotal,
    'lastRemovedAtMs': lastRemovedAtMs,
    'tickCatchUpTotal': tickCatchUpTotal,
    'lastTickCatchUpAtMs': lastTickCatchUpAtMs,
  };
}

void main() {
  group('tryParse 基本兼容', () {
    test('null / 空串 → null', () {
      expect(AutoBookDiagnostics.tryParse(null), isNull);
      expect(AutoBookDiagnostics.tryParse(''), isNull);
    });

    test('非 JSON → null（不抛）', () {
      expect(AutoBookDiagnostics.tryParse('not-json{'), isNull);
    });

    test('JSON 非 Map → null', () {
      expect(AutoBookDiagnostics.tryParse('[1,2,3]'), isNull);
    });

    test('缺全部字段也能解析出默认值（原生侧字段缺失时不崩）', () {
      final AutoBookDiagnostics? d = AutoBookDiagnostics.tryParse('{}');
      expect(d, isNotNull);
      expect(d!.capturedTotal, 0);
      expect(d.listenerConnected, isFalse);
    });

    test('⚠️ 旧版原生快照（无 F7.16 新字段）必须仍能解析', () {
      // 这是**向后兼容的硬要求**：Flutter 版本可能新于已装的 APK（用户没更新），
      // 或反之。任一方向都不能让整个诊断区挂掉。
      final AutoBookDiagnostics? d = AutoBookDiagnostics.tryParse(
        jsonEncode(<String, Object?>{
          'listenerConnected': true,
          'lastConnectedAtMs': 1,
          'lastCaptureAtMs': 2,
          'lastCapturePkg': 'com.tencent.mm',
          'capturedTotal': 14,
          'skippedNotWatched': 4475,
          'skippedEmpty': 0,
          'skippedDedup': 136,
          'skippedGroupSummary': 49,
          'lastDrainAtMs': 3,
          'lastDrainCount': 0,
          'drainedTotal': 16,
          'nowMs': 4,
        }),
      );
      expect(d, isNotNull);
      expect(d!.capturedTotal, 14);
      // 新字段走默认值，不能因为缺键而崩
      expect(d.tickCatchUpTotal, 0);
      expect(d.postedCallbackSeen, isFalse);
      expect(d.removedCaptureTotal, 0);
    });

    test('数值以字符串形式回来也能解析（跨端类型不一致的兜底）', () {
      final AutoBookDiagnostics? d = AutoBookDiagnostics.tryParse(
        '{"capturedTotal":"14","nowMs":"999"}',
      );
      expect(d!.capturedTotal, 14);
      expect(d.nowMs, 999);
    });
  });

  group('postedChannelUnavailable —— 实时推送是否确定不可用', () {
    const int tenMin = 10 * 60 * 1000;

    test('见过 posted 回调 → 可用', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(postedCallbackSeen: true, nowMs: 1000000 + tenMin * 2)),
      )!;
      expect(d.postedChannelUnavailable, isFalse);
    });

    test('没见过 + 连接已久（>10min）→ 判定不可用', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(
          lastConnectedAtMs: 1000, // 已绑定过，且是很久以前
          nowMs: tenMin * 11,
        )),
      )!;
      expect(d.postedCallbackSeen, isFalse);
      expect(d.postedChannelUnavailable, isTrue);
    });

    test('刚连上不久 → **不**判定不可用（避免刚启动就误报）', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(lastConnectedAtMs: tenMin * 9, nowMs: tenMin * 10)),
      )!;
      expect(d.postedChannelUnavailable, isFalse);
    });

    test('⚠️ 边界：恰好 10 分钟 → 不报（用严格大于，避免抖动误报）', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(lastConnectedAtMs: 0, nowMs: tenMin)),
      )!;
      expect(d.postedChannelUnavailable, isFalse);
    });

    test('⚠️ lastConnectedAtMs=0（从未连过）→ 不报', () {
      // 从未连接过属于「没绑定」，那是另一个判定（listenerLooksDead）的职责，
      // 不能混进「推送不可用」—— 否则提示会指向错误方向。
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(lastConnectedAtMs: 0, nowMs: tenMin * 100)),
      )!;
      expect(d.postedChannelUnavailable, isFalse);
    });
  });

  group('backgroundWakeWorks —— 后台唤醒是否真的生效过', () {
    const int fiveMin = 5 * 60 * 1000;
    // 实测（Redmi K50 / MIUI，2026-10-09）：本机恒为 false —— 闹钟与广播都被系统吞掉。
    // 所以这个判据**只**回答「后台唤醒有没有至少成功过一次」，
    // 页面据此如实提示「后台被限制，请打开本 App 一次」，不让用户误以为后台在记。
    test('从未成功唤醒过 → false（本机实测就是这个状态）', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(tickCatchUpTotal: 0, nowMs: fiveMin * 100)),
      )!;
      expect(d.backgroundWakeWorks, isFalse);
    });

    test('成功唤醒过至少一次 → true（其它 ROM 上会出现）', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(tickCatchUpTotal: 30, nowMs: fiveMin * 100)),
      )!;
      expect(d.backgroundWakeWorks, isTrue);
    });

    test('⚠️ 曾经唤醒过但很久没再转 → 仍为 true（只答「有没有成功过」）', () {
      // 刻意不为「最近有没有转」加判定：那会让页面把「一次都没成」和
      // 「成过但后来被限流」两种不同问题混成一句话，反而更难排查。
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(
          tickCatchUpTotal: 30,
          lastTickCatchUpAtMs: 0,
          nowMs: fiveMin * 100,
        )),
      )!;
      expect(d.backgroundWakeWorks, isTrue);
    });
  });

  group('既有判定未被破坏', () {
    test('neverCaptured', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(capturedTotal: 0)),
      )!;
      expect(d.neverCaptured, isTrue);
    });

    test('listenerLooksDead：设置开着但当前没绑定', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(listenerConnected: false, lastConnectedAtMs: 12345)),
      )!;
      expect(d.listenerLooksDead, isTrue);
    });

    test('listenerLooksDead：从来没连上过 → false', () {
      final AutoBookDiagnostics d = AutoBookDiagnostics.tryParse(
        jsonEncode(_diag(listenerConnected: false, lastConnectedAtMs: 0)),
      )!;
      expect(d.listenerLooksDead, isFalse);
    });
  });
}
