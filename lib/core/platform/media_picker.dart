/// 选本地文件（图片 / 账单文件）—— 走**自己的**平台通道 `yanxin/ocr`。
///
/// 为什么不用 `file_picker`：2026-10-24 真机实测（Redmi K50 / Android 14 / release 包），
/// `FilePicker.pickFile()` **点什么都没反应**：系统 Activity 根本没被拉起、也不报错
/// （「导入账单 → 选择文件」与「截图记账 → 选图」同样失效）。
/// 改成自己起 `Intent`（图片走 Android 13+ 的系统 Photo Picker，账单文件走 SAF）后一次就好。
///
/// 两条路径都**不需要任何运行时权限**，也完全离线；选中的文件会由原生侧复制到
/// 应用缓存目录，返回**本机绝对路径**（Dart 再读字节或直接交给 ML Kit）。
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 选文件失败（**预期内**的业务分支）。
class MediaPickFailure implements Exception {
  const MediaPickFailure(this.code, this.message);

  /// `unsupported_platform` | `busy` | `file_not_found` | …
  final String code;

  /// 原生侧原始信息（只用于诊断）。
  final String message;

  /// 给用户看的一句话。
  String get userMessage => switch (code) {
    'unsupported_platform' => '这台设备没有可用的文件选择器',
    'busy' => '上一次选择还没结束，稍等一下',
    'file_not_found' => '文件读不到了，换一个试试',
    _ => '选择文件失败，再试一次',
  };

  @override
  String toString() => 'MediaPickFailure($code: $message)';
}

/// 选本地文件。
abstract interface class MediaPicker {
  /// 选一张图片（相册 / Photo Picker）。用户取消返回 null。
  Future<String?> pickImage();

  /// 选一个账单文件（csv / xlsx，SAF）。用户取消返回 null。
  Future<String?> pickDocument();
}

/// 平台通道实现。
class ChannelMediaPicker implements MediaPicker {
  ChannelMediaPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yanxin/ocr');

  final MethodChannel _channel;

  @override
  Future<String?> pickImage() => _invoke('pickImage');

  @override
  Future<String?> pickDocument() => _invoke('pickDocument');

  Future<String?> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<String>(method);
    } on MissingPluginException catch (e) {
      throw MediaPickFailure('unsupported_platform', e.message ?? e.toString());
    } on PlatformException catch (e) {
      throw MediaPickFailure(e.code, e.message ?? '');
    }
  }
}

/// 选文件器（默认走平台通道）。测试里用 `overrideWithValue` 注入假实现。
final mediaPickerProvider = Provider<MediaPicker>(
  (Ref ref) => ChannelMediaPicker(),
);
