/// F7.6 设计令牌 —— 几何量（描边宽度 / 圆角）。
///
/// **颜色不在本文件**：F7.17 起深浅两套颜色在 [ToonPalette]（`palette.dart`），
/// 因为颜色必须随主题解析（`const Color` 切换主题不会变）。
///
/// 约定：
/// - 产品代码里**不出现裸 `Color(0x…)`**（除 `lib/core/theme/` 内）；
/// - 几何量走 [Tok]（`Tok.bw` / `Tok.rLg` …），颜色走 `context.toon`（`p.ink` / `p.paper` …）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';

/// 与主题无关的形体令牌（两套主题共用）。
abstract final class Tok {
  /// 描边宽度。
  static const double bw = 2.5;
  static const double rXl = 28;
  static const double rLg = 22;
  static const double rMd = 16;
  static const double rSm = 12;
}

/// 构建一套主题（浅色 / 深色共用同一份结构，颜色全部来自 [p]）。
///
/// 关键点：`onSurfaceVariant` 映射到 `p.ink2`，这样既有页面里
/// 「次要文字用 onSurfaceVariant」的写法会自动变成对应层级的灰，不必逐处改。
ThemeData buildToonTheme(ToonPalette p, Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final ColorScheme scheme =
      ColorScheme.fromSeed(seedColor: p.brand, brightness: brightness).copyWith(
        primary: p.brand,
        onPrimary: p.onBrand,
        surface: p.canvas,
        onSurface: p.ink,
        onSurfaceVariant: p.ink2,
        error: p.red,
        outline: p.ink,
      );

  final TextStyle base = TextStyle(color: p.ink, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    splashFactory: InkSparkle.splashFactory,
    extensions: <ThemeExtension<dynamic>>[p],
    textTheme: TextTheme(
      bodyLarge: base,
      bodyMedium: base,
      bodySmall: TextStyle(color: p.ink2, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(
        color: p.ink,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        color: p.ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      labelLarge: TextStyle(
        color: p.ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tok.rLg),
        side: BorderSide(color: p.ink, width: Tok.bw),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      centerTitle: true,
      // 深色主题 → 浅色状态栏图标；浅色主题 → 深色图标
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      // 原型 `.appbar` 底部一条墨色描边（`.plain` 变体除外，本 App 未用）
      shape: Border(bottom: BorderSide(color: p.ink, width: Tok.bw)),
      titleTextStyle: TextStyle(
        color: p.ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    ),
    dividerColor: p.dash,
    dividerTheme: DividerThemeData(color: p.dash, thickness: 2, space: 2),
    iconTheme: IconThemeData(color: p.ink),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.paper,
      contentTextStyle: TextStyle(
        color: p.ink,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: p.ink, width: Tok.bw),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tok.rXl),
        side: BorderSide(color: p.ink, width: 3),
      ),
      titleTextStyle: TextStyle(
        color: p.ink,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
      contentTextStyle: TextStyle(
        color: p.ink2,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper,
      modalBackgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Tok.rXl)),
        side: BorderSide(color: p.ink, width: Tok.bw),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.paper,
      hintStyle: TextStyle(color: p.ink3, fontWeight: FontWeight.w600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tok.rMd),
        borderSide: BorderSide(color: p.ink, width: Tok.bw),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tok.rMd),
        borderSide: BorderSide(color: p.ink, width: Tok.bw),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tok.rMd),
        borderSide: BorderSide(color: p.ink, width: Tok.bw),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brand),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.brandDeep,
      selectionColor: p.brandTint2,
    ),
  );
}
