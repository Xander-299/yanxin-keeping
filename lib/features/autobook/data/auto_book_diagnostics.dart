/// 自动记账的**诊断数据**（F7.15 走查补丁）—— 把「静默失败」变成可归因的状态。
///
/// 这个功能有四个断点，全都不给用户任何反馈：
///   ① 系统有没有把监听服务绑上（`listenerConnected`）
///   ② 服务有没有抓到微信/支付宝的通知（`lastCaptureAtMs` / `capturedTotal` / `skipped*`）
///   ③ Dart 有没有触发消费队列（`lastDrainAtMs` / 队列里的 `pendingCount`）
///   ④ Dart 处理时入账成功还是全被丢/判重复（[AutoBookLastRun]）
///
/// 没有这层信息时，用户与开发者都只能看到「没记上」，无法判断该去开权限、等下次打开、
/// 还是去改解析规则。数据本身不参与记账逻辑。
library;

import 'dart:convert';

/// 「最近一次检查结果」在 `schema_meta` KV 里的键（与 `autobook_batches` / `active_book_id` 同表）。
const String kAutoBookLastRunKey = 'autobook_last_run';

/// 原生侧活性快照（`AutoBookChannel` 的 `diagnostics`）。
class AutoBookDiagnostics {
  const AutoBookDiagnostics({
    required this.listenerConnected,
    required this.lastConnectedAtMs,
    required this.lastCaptureAtMs,
    required this.lastCapturePkg,
    required this.capturedTotal,
    required this.skippedNotWatched,
    required this.skippedEmpty,
    required this.skippedDedup,
    required this.lastDrainAtMs,
    required this.lastDrainCount,
    required this.drainedTotal,
    required this.nowMs,
  });

  /// 系统当前是否绑定着监听服务。
  final bool listenerConnected;

  /// 最近一次被系统绑定的时间（0 = 从未）。
  final int lastConnectedAtMs;

  /// 最近一次成功抓到并入库的通知时间（0 = 从未抓到过）。
  final int lastCaptureAtMs;
  final String lastCapturePkg;

  /// 累计抓到（入队）的条数。
  final int capturedTotal;

  /// 被各层过滤掉的条数 —— 「抓到但没记账」时看这里。
  final int skippedNotWatched;
  final int skippedEmpty;
  final int skippedDedup;

  /// 最近一次被 Dart 取走队列的时间与条数。
  final int lastDrainAtMs;
  final int lastDrainCount;
  final int drainedTotal;

  /// 取快照时的设备时间（页面据此算「多久之前」，不依赖端上时钟一致性）。
  final int nowMs;

  /// 是否从未抓到过任何通知（判断「服务白开」）。
  bool get neverCaptured => capturedTotal == 0;

  /// 「设置里开着，但系统并未绑定服务」—— 典型的国产 ROM 后台限制表现。
  bool get listenerLooksDead => !listenerConnected && lastConnectedAtMs > 0;

  static AutoBookDiagnostics? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, Object?> m = decoded.cast<String, Object?>();
      return AutoBookDiagnostics(
        listenerConnected: m['listenerConnected'] == true,
        lastConnectedAtMs: _asInt(m['lastConnectedAtMs']),
        lastCaptureAtMs: _asInt(m['lastCaptureAtMs']),
        lastCapturePkg: (m['lastCapturePkg'] as String?) ?? '',
        capturedTotal: _asInt(m['capturedTotal']),
        skippedNotWatched: _asInt(m['skippedNotWatched']),
        skippedEmpty: _asInt(m['skippedEmpty']),
        skippedDedup: _asInt(m['skippedDedup']),
        lastDrainAtMs: _asInt(m['lastDrainAtMs']),
        lastDrainCount: _asInt(m['lastDrainCount']),
        drainedTotal: _asInt(m['drainedTotal']),
        nowMs: _asInt(m['nowMs']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 「最近一次检查」的结果（落 `schema_meta` KV，跨启动可见）。
///
/// 用户点「检查一次」或 App 自动 drain 后都会写一条 —— 下一次进来能看到上次干了什么，
/// 而不是永远只显示「没有新的支付通知」。
class AutoBookLastRun {
  const AutoBookLastRun({
    required this.atMs,
    this.imported = 0,
    this.duplicates = 0,
    this.dropped = 0,
    this.undone = 0,
    this.restored = false,
    this.error = '',
  });

  const AutoBookLastRun.initial()
    : atMs = 0,
      imported = 0,
      duplicates = 0,
      dropped = 0,
      undone = 0,
      restored = false,
      error = '';

  final int atMs;
  final int imported;
  final int duplicates;

  /// 解析不出而丢弃的条数（非消费通知 / 坏数据 / 命中忽略规则）。
  final int dropped;
  final int undone;

  /// 本次因临时性失败（账本未就绪 / 写库异常）把队列**回写**了，等下次重试。
  final bool restored;

  /// 失败原因（空 = 正常）。
  final String error;

  bool get hasRun => atMs > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'atMs': atMs,
    'imported': imported,
    'duplicates': duplicates,
    'dropped': dropped,
    'undone': undone,
    'restored': restored,
    'error': error,
  };

  /// 一行摘要（页面直接用）。
  String get summary {
    if (error.isNotEmpty) return '上次检查出错：$error';
    if (!hasRun) return '还没有检查过';
    if (imported > 0) return '上次检查：新入账 $imported 笔';
    if (undone > 0) return '上次检查：撤销 $undone 笔';
    if (restored) return '上次检查：暂时无法入账，已保留待下次重试';
    if (duplicates > 0) return '上次检查：$duplicates 笔已存在（未重复入账）';
    if (dropped > 0) return '上次检查：$dropped 条通知不符合记账条件';
    return '上次检查：没有新的支付通知';
  }

  static AutoBookLastRun? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> m = raw.cast<String, Object?>();
    return AutoBookLastRun(
      atMs: _asInt(m['atMs']),
      imported: _asInt(m['imported']),
      duplicates: _asInt(m['duplicates']),
      dropped: _asInt(m['dropped']),
      undone: _asInt(m['undone']),
      restored: m['restored'] == true,
      error: (m['error'] as String?) ?? '',
    );
  }

  static AutoBookLastRun? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return tryFromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
