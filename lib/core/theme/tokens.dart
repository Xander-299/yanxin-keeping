/// F7.6 设计令牌 —— 1:1 取自页面原型 `modao/yanxin/styles.css` 的 `:root`。
///
/// 约定：**产品代码里不再出现裸 `Color(0x…)`**（除本文件与 `toon.dart` 的画布细节），
/// 一律引用 [Tok] 里的令牌 —— 避免改一处漏三处。
library;

import 'package:flutter/material.dart';

/// 卡通浅色视觉令牌（粗描边 + 硬阴影 + 糖果色 + 圆胖形体）。
abstract final class Tok {
  // ── 墨色：描边与文字三阶 ──
  static const Color ink = Color(0xFF2A2A35);
  static const Color ink2 = Color(0xFF6C6C7C);
  static const Color ink3 = Color(0xFF9C9CAD);

  // ── 纸与画布 ──
  static const Color paper = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFFFF7EA);
  static const Color canvas2 = Color(0xFFFFFCF6);

  // ── 品牌琥珀 ──
  static const Color brand = Color(0xFFFFB627);
  static const Color brandDeep = Color(0xFFE1810A);
  static const Color brandInk = Color(0xFF4A3103);
  static const Color brandTint = Color(0xFFFFF1D4);
  static const Color brandTint2 = Color(0xFFFFE1AC);

  // ── 语义色（糖果色） ──
  static const Color red = Color(0xFFFF5D5D);
  static const Color redTint = Color(0xFFFFE5E5);
  static const Color green = Color(0xFF2FC98A);
  static const Color greenTint = Color(0xFFD9F7E9);
  static const Color blue = Color(0xFF4DA8FF);
  static const Color blueTint = Color(0xFFE2F0FF);
  static const Color purple = Color(0xFFA98BFF);
  static const Color purpleTint = Color(0xFFEEE7FF);
  static const Color pink = Color(0xFFFF7FAB);
  static const Color lemon = Color(0xFFFFE066);

  // ── 线条 ──
  static const Color line = Color(0xFFF0E7D8);

  /// 虚线分割 / 列表分隔（原型 `rgba(42,42,53,.2)`）。
  static const Color dash = Color(0x332A2A35);

  /// 环形进度 / 柱状的底槽。
  static const Color track = Color(0xFFF5EFE4);

  /// hero 卡上的深棕字色。
  static const Color heroInk = Color(0xFF3F2B06);

  /// 小猪鼻子的奶白。
  static const Color snout = Color(0xFFFFE7C2);

  /// 腮红。
  static const Color blush = Color(0xFFFF8FA8);

  /// 分类占比调色板（按占比顺序取用）。
  static const List<Color> pie = <Color>[
    Color(0xFFFFB627),
    Color(0xFFFF6B8A),
    Color(0xFF4DC9C0),
    Color(0xFF5A8DFF),
    Color(0xFFB18CFF),
    Color(0xFF5FD068),
    Color(0xFFFF8A3D),
    Color(0xFFF06FC0),
    Color(0xFF9AA5B1),
  ];

  // ── 形体 ──
  static const double bw = 2.5;
  static const double rXl = 28;
  static const double rLg = 22;
  static const double rMd = 16;
  static const double rSm = 12;

  /// 硬阴影。`blurRadius: 0` 才是「硬」边（有模糊就不像卡通了）。
  static List<BoxShadow> hard({double d = 4, Color color = ink}) => <BoxShadow>[
    BoxShadow(color: color, offset: Offset(d, d), blurRadius: 0),
  ];

  /// 墨色描边。
  static Border inkBorder({double w = bw}) => Border.all(color: ink, width: w);

  /// 卡通卡片装饰：白底 + 墨色描边 + 硬阴影。
  static BoxDecoration cardDeco({
    Color color = paper,
    double radius = rLg,
    double shadow = 4,
    bool bordered = true,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: bordered ? inkBorder() : null,
    boxShadow: shadow > 0 ? hard(d: shadow) : null,
  );
}

/// 全站主题：卡通浅色。
///
/// 关键点：`onSurfaceVariant` 映射到 [Tok.ink2]，这样既有页面里
/// 「次要文字用 onSurfaceVariant」的写法会自动变成原型的次级灰，不必逐处改。
ThemeData buildToonTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: Tok.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: Tok.brand,
    onPrimary: Tok.brandInk,
    surface: Tok.canvas,
    onSurface: Tok.ink,
    onSurfaceVariant: Tok.ink2,
    error: Tok.red,
    outline: Tok.ink,
  );

  const TextStyle base = TextStyle(color: Tok.ink, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tok.canvas,
    canvasColor: Tok.canvas,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      bodyLarge: base,
      bodyMedium: base,
      bodySmall: TextStyle(color: Tok.ink2, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(
        color: Tok.ink,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        color: Tok.ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      labelLarge: TextStyle(
        color: Tok.ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Tok.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tok.rLg),
        side: const BorderSide(color: Tok.ink, width: Tok.bw),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Tok.paper,
      foregroundColor: Tok.ink,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Tok.ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    ),
    dividerColor: Tok.dash,
    dividerTheme: const DividerThemeData(color: Tok.dash, thickness: 2, space: 2),
    iconTheme: const IconThemeData(color: Tok.ink),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Tok.paper,
      contentTextStyle: const TextStyle(
        color: Tok.ink,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: Tok.ink, width: Tok.bw),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Tok.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tok.rXl),
        side: const BorderSide(color: Tok.ink, width: 3),
      ),
      titleTextStyle: const TextStyle(
        color: Tok.ink,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
      contentTextStyle: const TextStyle(
        color: Tok.ink2,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tok.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
        side: BorderSide(color: Tok.ink, width: Tok.bw),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tok.paper,
      hintStyle: const TextStyle(color: Tok.ink3, fontWeight: FontWeight.w600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tok.rMd),
        borderSide: const BorderSide(color: Tok.ink, width: Tok.bw),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tok.rMd),
        borderSide: const BorderSide(color: Tok.ink, width: Tok.bw),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tok.rMd),
        borderSide: const BorderSide(color: Tok.ink, width: Tok.bw),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Tok.brand),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Tok.brandDeep,
      selectionColor: Tok.brandTint2,
    ),
  );
}
