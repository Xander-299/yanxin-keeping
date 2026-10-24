// F8.1 真机诊断探针（**临时文件，验证完删除**）。
//
// 为什么需要它：走查时 `adb shell input tap` 在这台 MIUI 上点不中 Flutter 按钮
// （通道日志一条都没有），没法通过 UI 驱动「选图 → 识别」。
// 这个入口**不碰 UI**：启动即对一张固定路径的图片跑一遍端上 OCR + 规则解析，
// 结果打到 logcat（`adb logcat | grep PROBE`），用来把问题定位在「OCR」还是「解析」。
//
// 用法：
//   adb push bill.jpg /sdcard/Android/data/com.teacodeman.yanxin.qa/cache/bill.jpg
//   flutter build apk --release --no-pub -t tool/ocr_probe_main.dart
//   adb install -r -t build/app/outputs/flutter-apk/app-release.apk
//   adb shell am start -n com.teacodeman.yanxin.qa/com.teacodeman.yanxin.MainActivity
//   adb logcat -s flutter
// ignore_for_file: avoid_print
library;

import 'package:flutter/widgets.dart';

import 'package:yanxin/features/receipt/application/receipt_draft.dart';
import 'package:yanxin/features/receipt/data/mlkit_ocr_engine.dart';
import 'package:yanxin/features/receipt/data/ocr_engine.dart';
import 'package:yanxin/features/receipt/data/receipt_parse.dart';

/// 探针读取的图片路径：应用**内部**缓存目录。
///
/// ⚠️ 只能用内部目录：Android 11+ 的分区存储下，`/sdcard/Android/data/<pkg>/cache`
/// 里由 shell 推上去的文件 App 读不到（`File.exists()` 直接 false）。
/// 内部目录靠 debug 包的 `run-as` 写进去：
///   adb push bill.jpg /data/local/tmp/bill.jpg
///   adb shell run-as com.teacodeman.yanxin.qa cp /data/local/tmp/bill.jpg cache/bill.jpg
const String kProbeImagePath =
    '/data/data/com.teacodeman.yanxin.qa/cache/bill.jpg';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('PROBE start path=$kProbeImagePath');
  try {
    final OcrResult ocr = await MlKitOcrEngine().recognize(kProbeImagePath);
    print(
      'PROBE ocr lines=${ocr.lines.length} ms=${ocr.elapsedMs} '
      'size=${ocr.width}x${ocr.height}',
    );
    print('PROBE lines>>> ${ocr.lineTexts.join(' | ')}');
    final ReceiptDraft d = parseReceipt(
      ocr.lineTexts,
      nowMs: DateTime(2026, 10, 24, 20, 0).millisecondsSinceEpoch,
    );
    print(
      'PROBE draft platform=${d.platform.name} status=${d.status.name} '
      'direction=${d.direction.value} amountCents=${d.amountCents.value} '
      'amountConf=${d.amountCents.confidence.name} '
      'occurredAtMs=${d.occurredAtMs.value} merchant=${d.merchant.value} '
      'category=${d.categoryName.value} orderNo=${d.orderNo} '
      'issues=${d.issues.map((ReceiptIssue i) => i.name).join(',')}',
    );
  } catch (e, st) {
    print('PROBE error: $e');
    print('PROBE stack: $st');
  }
  runApp(const SizedBox.shrink());
}
