/// 端上 OCR 的抽象（F8.1 截图记账）。
///
/// 为什么要抽一层：[解析层] 完全可以脱离原生环境单测，页面也可以注入假引擎跑
/// widget 测试 —— 只有 [OcrEngine] 的实现才碰平台通道。
///
/// 铁律：**引擎只负责"图片 → 文字行"**。金额 / 时间 / 商户的判定、
/// 以及最终写库，全部在 Dart 侧（drift 是唯一 DB writer）。
library;

import 'dart:ui' show Rect;

/// 一行识别结果。
class OcrLine {
  const OcrLine({required this.text, this.box});

  final String text;

  /// 归一化坐标（图片像素；`InputImage.fromFilePath` 已按 EXIF 把图转正）。
  final Rect? box;

  /// 行在图片里的纵坐标上沿（无坐标时按 0 处理，排序退化为「原顺序」）。
  double get top => box?.top ?? 0;

  /// 行在图片里的横坐标左沿。
  double get left => box?.left ?? 0;
}

/// 一次识别的结果。
class OcrResult {
  const OcrResult({
    required this.lines,
    required this.text,
    this.width,
    this.height,
    this.elapsedMs = 0,
  });

  const OcrResult.empty()
      : lines = const <OcrLine>[],
        text = '',
        width = null,
        height = null,
        elapsedMs = 0;

  final List<OcrLine> lines;

  /// 引擎给的整页文本（换行分隔）；解析一律用 [lineTexts]（顺序更可控）。
  final String text;

  final int? width;
  final int? height;

  /// 端上识别耗时（毫秒），用于"识别耗时 xx ms"这类诊断文案。
  final int elapsedMs;

  bool get isEmpty => lines.isEmpty;

  /// 按「先上后右」重排后的行文本。
  ///
  /// ML Kit 一般已按阅读顺序返回，但截图里常有多栏（金额在右、标签在左），
  /// 显式排序能让"同一行"的判定稳定 —— 排序是纯函数，逐条可测。
  ///
  /// ⚠️ `List.sort` **不保证稳定**：坐标相同（或都为空）时必须用原下标兜底，
  /// 否则同一张图两次识别的行序可能不一样 → 解析结果不稳定。
  List<String> get lineTexts {
    final List<({int index, OcrLine line})> indexed = <({int index, OcrLine line})>[
      for (int i = 0; i < lines.length; i++) (index: i, line: lines[i]),
    ];
    indexed.sort((({int index, OcrLine line}) a, ({int index, OcrLine line}) b) {
      // 纵向差在 1/4 行高内视为同一行 → 再按横向排（避免"右对齐的金额"被排到下一行）
      final double tolerance =
          ((a.line.box?.height ?? 0) + (b.line.box?.height ?? 0)) / 4;
      if ((a.line.top - b.line.top).abs() > tolerance) {
        return a.line.top.compareTo(b.line.top);
      }
      final int byLeft = a.line.left.compareTo(b.line.left);
      if (byLeft != 0) return byLeft;
      return a.index.compareTo(b.index);
    });
    return indexed
        .map((({int index, OcrLine line}) e) => e.line.text)
        .where((String s) => s.trim().isNotEmpty)
        .toList(growable: false);
  }
}

/// 识别失败（**预期内**的业务分支：模糊图 / 不是截图 / 通道不可用 …）。
class OcrFailure implements Exception {
  const OcrFailure(this.code, this.message);

  /// `unsupported_platform` | `file_not_found` | `bad_args` | `ocr_failed` | `timeout`
  final String code;

  /// 原生侧原始信息（只用于诊断，不展示给用户）。
  final String message;

  /// 给用户看的一句话（不暴露原生堆栈）。
  String get userMessage => switch (code) {
    'unsupported_platform' => '这台设备上用不了端上文字识别',
    'file_not_found' => '图片读不到了，换一张试试',
    'bad_args' => '图片参数不对，换一张试试',
    'timeout' => '识别超时了，再试一次',
    _ => '这张图没认出来，换一张或者手动记一笔',
  };

  @override
  String toString() => 'OcrFailure($code: $message)';
}

/// 端上文字识别引擎。
abstract interface class OcrEngine {
  /// 识别一张本地图片。失败一律抛 [OcrFailure]（不抛平台异常）。
  Future<OcrResult> recognize(String imagePath);

  /// 释放原生资源（页面销毁 / App 进后台时调）。
  Future<void> dispose();
}
