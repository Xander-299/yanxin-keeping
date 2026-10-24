/// ML Kit 文字识别引擎的 Dart 侧（F8.1）。
///
/// 通道对端：`android/app/src/main/kotlin/com/teacodeman/yanxin/ocr/OcrChannel.kt`
/// （`yanxin/ocr`，中文 **bundled** 模型，离线、不依赖 Google Play 服务）。
///
/// ⚠️ 非 Android（widget 测试 / 桌面）调用会抛 `MissingPluginException`
/// → 统一翻译成 [OcrFailure]`unsupported_platform`，**不得冒泡成崩溃**。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ocr_engine.dart';

/// 通过平台通道调用端上 ML Kit 识别。
class MlKitOcrEngine implements OcrEngine {
  MlKitOcrEngine({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kChannelName);

  /// 通道名（与 Kotlin 侧 `OcrChannel.NAME` 必须一致）。
  static const String kChannelName = 'yanxin/ocr';

  final MethodChannel _channel;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('recognize', <String, Object?>{
            'path': imagePath,
          });
      if (raw == null) {
        throw const OcrFailure('ocr_failed', '原生侧没有返回结果');
      }
      return _toResult(raw);
    } on MissingPluginException catch (e) {
      throw OcrFailure('unsupported_platform', e.message ?? e.toString());
    } on PlatformException catch (e) {
      throw OcrFailure(e.code, e.message ?? e.details?.toString() ?? '');
    }
  }

  /// 释放原生识别器（页面销毁 / 进后台时调）。
  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {
      // 通道不可用 / 已销毁：释放失败不值得打扰用户
    }
  }

  OcrResult _toResult(Map<Object?, Object?> raw) {
    final List<OcrLine> lines = <OcrLine>[];
    final Object? rawLines = raw['lines'];
    if (rawLines is List<Object?>) {
      for (final Object? item in rawLines) {
        if (item is! Map<Object?, Object?>) continue;
        final String text = (item['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) continue;
        lines.add(OcrLine(text: text, box: _boxOf(item)));
      }
    }
    return OcrResult(
      lines: lines,
      text: (raw['text'] as String?) ?? '',
      width: _intOf(raw['width']),
      height: _intOf(raw['height']),
      elapsedMs: _intOf(raw['elapsedMs']) ?? 0,
    );
  }

  Rect? _boxOf(Map<Object?, Object?> item) {
    final int? left = _intOf(item['left']);
    final int? top = _intOf(item['top']);
    final int? right = _intOf(item['right']);
    final int? bottom = _intOf(item['bottom']);
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    if (right <= left || bottom <= top) return null;
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }

  int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

/// OCR 引擎（默认 = ML Kit 端上识别）。
///
/// 测试里 `overrideWithValue(FakeOcrEngine(...))` 即可绕过平台通道。
final ocrEngineProvider = Provider<OcrEngine>((Ref ref) {
  final OcrEngine engine = MlKitOcrEngine();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});
