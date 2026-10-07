/// 自动记账的平台通道封装（F7.15 SPEC §3.2 / §3.7）。
///
/// Kotlin 侧实现见 `android/app/src/main/kotlin/com/teacodeman/yanxin/autobook/AutoBookChannel.kt`。
///
/// **降级铁律**：非 Android（含本机 widget 测试）或任何通道异常（`MissingPluginException`
/// / `PlatformException`）→ 全部返回安全默认值，**绝不抛给调用方**，绝不阻断冷启动。
/// 因此 `drain()` 在桌面测试环境里就是「空队列」，什么都不发生。
///
/// 方法都可被子类覆写 —— 测试里用假实现（`FakeAutoBookBridge`）替换整条 Native 链路。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_book_diagnostics.dart';

/// 通道名（与 Kotlin 侧 `AutoBookChannel.NAME` 必须一致）。
const String kAutoBookChannelName = 'yanxin/autobook';

/// 回执通知里「撤销」按钮的动作值（与 Kotlin `AutoBookNotifier.ACTION_UNDO` 一致）。
const String kAutoBookActionUndo = 'undo';

class AutoBookBridge {
  AutoBookBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kAutoBookChannelName);

  final MethodChannel _channel;

  /// 是否在受支持的平台（只有 Android 有这条原生链路）。
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 「通知使用权」是否已开启。
  Future<bool> listenerEnabled() async =>
      (await _invoke<bool>('permissionStatus')) ?? false;

  /// 通知是否允许（Android 13+ 还要求 POST_NOTIFICATIONS 运行时权限）。
  Future<bool> notificationsAllowed() async =>
      (await _invoke<bool>('notificationPermissionStatus')) ?? false;

  /// 申请通知权限（Android 13+；低版本是空操作）。
  Future<void> requestNotificationPermission() async {
    await _invoke<Object?>('requestNotificationPermission');
  }

  /// 跳到系统「通知使用权」设置页。
  Future<void> openListenerSettings() async {
    await _invoke<Object?>('openNotificationSettings');
  }

  /// 跳到本 App 的通知设置页（通知权限被拒后的兜底入口）。
  Future<void> openAppNotificationSettings() async {
    await _invoke<Object?>('openAppNotificationSettings');
  }

  /// 取走落盘队列（原始 JSONL 行，Dart 侧自行解析/丢弃坏行）。
  Future<List<String>> drainQueue() async {
    final Object? res = await _invoke<Object?>('drainQueue');
    if (res is List) {
      return res
          .map((Object? e) => e?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  /// 临时性失败时把原始行**放回原生队列**（等下次重试）。
  ///
  /// 不这么做的话「取走即清空」会让这批通知永久消失 —— 冷启动首帧账本未就绪、
  /// 写库抛异常等场景都会命中。
  Future<void> restoreQueue(List<String> lines) async {
    if (lines.isEmpty) return;
    await _invoke<Object?>('restoreQueue', <String, Object?>{'lines': lines});
  }

  /// 原生侧活性快照（服务是否被绑定 / 抓到过几条 / 上次 drain 情况）。
  /// 非 Android 或通道异常 → null（页面按「不可用」展示）。
  Future<AutoBookDiagnostics?> diagnostics() async {
    final Object? res = await _invoke<Object?>('diagnostics');
    if (res is String) return AutoBookDiagnostics.tryParse(res);
    return null;
  }

  /// 未处理条数（「识别到 N 笔」）。
  Future<int> pendingCount() async =>
      (await _invoke<int>('pendingCount')) ?? 0;

  /// 取走通知按钮落下的命令（读后即删）；无命令返回 null。
  Future<String?> takeCommand() => _invoke<String>('takeCommand');

  /// 更新为「已自动记账 N 笔」回执（含 `撤销` / `查看` 两个按钮）。
  Future<void> showReceipt({
    required int count,
    required String amountText,
    required String batchId,
    List<String> lines = const <String>[],
  }) async {
    await _invoke<Object?>('showReceipt', <String, Object?>{
      'count': count,
      'amountText': amountText,
      'batchId': batchId,
      'lines': lines,
    });
  }

  /// 收起当前那条自动记账通知（无新增入账时也用它清掉「识别到 N 笔」）。
  Future<void> cancelReceipt() async {
    await _invoke<Object?>('cancelReceipt');
  }

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      // 原生侧任何意外都不得影响记账主流程
      return null;
    }
  }
}

/// 平台通道（测试里 override 成假实现）。
final autoBookBridgeProvider = Provider<AutoBookBridge>(
  (Ref ref) => AutoBookBridge(),
);
