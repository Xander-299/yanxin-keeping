/// 卡通主题调色板（浅色 / 深色两套）。
///
/// 背景：F7.6 把色值做成了 `Tok` 的**编译期常量**，无法随主题切换（`const Color` 不会变，
/// 且 `const` 构造的 widget 实例会被 Element 判 `identical` 直接跳过重建）。
/// F7.17 起颜色全部从 `Theme.of(context)` 解析：**`ThemeExtension` + 实例方法**。
///
/// 用法（widget / build 内）：
/// ```dart
/// final ToonPalette p = context.toon;
/// Container(decoration: BoxDecoration(color: p.paper, border: p.inkBorder(), boxShadow: p.hard()));
/// ```
///
/// 约定：
/// - **产品代码里不出现裸 `Color(0x…)`**（本文件与 `toon.dart` 的画布细节除外）；
/// - 几何量（描边宽度 / 圆角）仍留在 [Tok]（与主题无关，不随深浅变）；
/// - 自定义绘制的画笔颜色**由构造函数注入**，不要在 `paint()` 里读 context。
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 一整套卡通视觉色板。
@immutable
class ToonPalette extends ThemeExtension<ToonPalette> {
  const ToonPalette({
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.paper,
    required this.canvas,
    required this.canvas2,
    required this.brand,
    required this.brandDeep,
    required this.onBrand,
    required this.brandInk,
    required this.brandTint,
    required this.brandTint2,
    required this.red,
    required this.redTint,
    required this.redInk,
    required this.onRed,
    required this.green,
    required this.greenTint,
    required this.blue,
    required this.blueTint,
    required this.purple,
    required this.purpleTint,
    required this.pink,
    required this.lemon,
    required this.line,
    required this.dash,
    required this.track,
    required this.heroInk,
    required this.snout,
    required this.blush,
    required this.decorInk,
    required this.shadow,
    required this.veil,
    required this.pie,
  });

  // ── 墨色：描边与文字三阶 ──
  final Color ink;
  final Color ink2;
  final Color ink3;

  // ── 纸与画布 ──
  final Color paper;
  final Color canvas;
  final Color canvas2;

  // ── 品牌琥珀 ──

  /// 品牌主色（**两套主题共用**：琥珀是品牌锚点）。
  final Color brand;

  /// 品牌深色：浅底上的品牌字 / 光标（深色主题下提亮）。
  final Color brandDeep;

  /// **亮琥珀底上的字**（主按钮 / 选中 chip / 中央 +）：两套主题都是深棕。
  final Color onBrand;

  /// **品牌浅底（[brandTint]）上的字**：浅色深棕、深色浅琥珀。
  final Color brandInk;

  final Color brandTint;
  final Color brandTint2;

  // ── 语义色（糖果色） ──
  final Color red;
  final Color redTint;

  /// 红底提示条上的深红字（[red] 铺在 [redTint] 上对比不足，单列）。
  final Color redInk;

  /// **实心 [red] 底上的字 / 图标**（左滑删除的动作区）。
  ///
  /// 不能直接用 [veil]（白）：[red] 在暗底上要够亮才能当金额色，亮度被顶到 0.30 上下，
  /// 白字压上去只有 ~2.8:1（深色）/ ~3.0:1（浅色）。用深暖黑才够 4.5:1。
  final Color onRed;

  final Color green;
  final Color greenTint;
  final Color blue;
  final Color blueTint;
  final Color purple;
  final Color purpleTint;
  final Color pink;
  final Color lemon;

  // ── 线条 ──

  /// 实线分割 / 卡片内浅分隔。
  final Color line;

  /// 虚线分隔（半透明墨色）。
  final Color dash;

  /// 环形进度 / 柱状 / 饼图的底槽。
  final Color track;

  /// hero 卡上的深棕字色（hero 恒为琥珀底，故两套主题一致）。
  final Color heroInk;

  /// 小猪鼻子的奶白。
  final Color snout;

  /// 腮红。
  final Color blush;

  /// **插画描边**（小猪的轮廓 / 眼睛、星星贴纸的边）：两套主题都恒为深色。
  ///
  /// 这些插画永远画在**品牌底或白底**上，若跟着 [ink] 在深色主题下反成浅色，
  /// 就会得到「白底白描边」的一团。
  final Color decorInk;

  /// 硬阴影色：浅色直接用墨色，深色用纯黑（浅色阴影在暗底上会像发光）。
  final Color shadow;

  /// 品牌色底上的半透明覆盖（hero 上的小胶囊 / 装饰圆）：两套主题都是白。
  final Color veil;

  /// 分类占比调色板（按占比顺序取用）。
  final List<Color> pie;

  // ─────────────────────────── 形体助手 ───────────────────────────

  /// 硬阴影。`blurRadius: 0` 才是「硬」边（有模糊就不像卡通了）。
  List<BoxShadow> hard({double d = 4, Color? color}) => <BoxShadow>[
    BoxShadow(color: color ?? shadow, offset: Offset(d, d), blurRadius: 0),
  ];

  /// 墨色描边（默认用于纸底 / 画布底）。
  ///
  /// **[on] 传「描边所在的那块底色」**：亮底（琥珀 / 品牌浅底 / 用户自选色）自动改用
  /// 恒深的 [decorInk]，暗底用随主题反色的 [ink]。不传 = 纸底（等同于旧行为）。
  ///
  /// 为什么必须有这个参数：深色主题下 [ink] 是暖白，白描边压在琥珀上只有 ~1.3:1
  /// —— 主按钮 / 选中 tab / 选中的分类格 / hero 的描边会**整条消失**（F7.17 对比度修复）。
  Border inkBorder({double w = Tok.bw, Color? on}) =>
      Border.all(color: on == null ? ink : inkOn(on), width: w);

  /// 任意底色上的前景色：**亮底用深墨、暗底用白**。
  ///
  /// 用于「底色不是主题色」的场合（如账户自选色 `#FF6B8A` 这类用户数据）：
  /// 深色主题下 [ink] 是暖白，直接铺在亮色块上会读不清。
  Color inkOn(Color background) =>
      background.computeLuminance() > 0.45 ? decorInk : veil;

  /// 卡通卡片装饰：卡片底 + 墨色描边 + 硬阴影。
  BoxDecoration cardDeco({
    Color? color,
    double radius = Tok.rLg,
    double depth = 4,
    bool bordered = true,
  }) => BoxDecoration(
    color: color ?? paper,
    borderRadius: BorderRadius.circular(radius),
    border: bordered ? inkBorder() : null,
    boxShadow: depth > 0 ? hard(d: depth) : null,
  );

  // ─────────────────────────── 调色板本体 ───────────────────────────

  /// 浅色（F7.6 原型 `:root`，1:1 保留）。
  static const ToonPalette light = ToonPalette(
    ink: Color(0xFF2A2A35),
    ink2: Color(0xFF6C6C7C),
    ink3: Color(0xFF9C9CAD),
    paper: Color(0xFFFFFFFF),
    canvas: Color(0xFFFFF7EA),
    canvas2: Color(0xFFFFFCF6),
    brand: Color(0xFFFFB627),
    brandDeep: Color(0xFFE1810A),
    onBrand: Color(0xFF4A3103),
    brandInk: Color(0xFF4A3103),
    brandTint: Color(0xFFFFF1D4),
    brandTint2: Color(0xFFFFE1AC),
    red: Color(0xFFFF5D5D),
    redTint: Color(0xFFFFE5E5),
    redInk: Color(0xFFA8321F),
    onRed: Color(0xFF4A0F0A),
    green: Color(0xFF2FC98A),
    greenTint: Color(0xFFD9F7E9),
    blue: Color(0xFF4DA8FF),
    blueTint: Color(0xFFE2F0FF),
    purple: Color(0xFFA98BFF),
    purpleTint: Color(0xFFEEE7FF),
    pink: Color(0xFFFF7FAB),
    lemon: Color(0xFFFFE066),
    line: Color(0xFFF0E7D8),
    dash: Color(0x332A2A35),
    track: Color(0xFFF5EFE4),
    heroInk: Color(0xFF3F2B06),
    snout: Color(0xFFFFE7C2),
    blush: Color(0xFFFF8FA8),
    decorInk: Color(0xFF2A2A35),
    shadow: Color(0xFF2A2A35),
    veil: Color(0xFFFFFFFF),
    pie: pieColors,
  );

  /// 深色（F7.17「卡通夜灯」）：暖黑画布 + 暖白描边 + 纯黑硬阴影，品牌琥珀不动。
  static const ToonPalette dark = ToonPalette(
    ink: Color(0xFFF6F0E4),
    ink2: Color(0xFFBDB6C7),
    // 三级灰：#857F91 在深色纸底上只有 3.96:1，而它承担了底栏标签(10~11px)、
    // 输入框 hint、8px 月历辅助字 —— 提亮到 #A098AE 后 paper 5.52 / canvas2 6.09 /
    // track 4.73，全部过 AA；仍明显暗于 ink2(#BDB6C7, 7.76)，层级不丢。
    ink3: Color(0xFFA098AE),
    paper: Color(0xFF26242F),
    canvas: Color(0xFF17151D),
    canvas2: Color(0xFF1E1C25),
    brand: Color(0xFFFFB627),
    brandDeep: Color(0xFFFFC85C),
    onBrand: Color(0xFF33230A),
    brandInk: Color(0xFFFFD98C),
    brandTint: Color(0xFF3A2C10),
    brandTint2: Color(0xFF5B4316),
    red: Color(0xFFFF6B6B),
    redTint: Color(0xFF3B2024),
    redInk: Color(0xFFFF9F9F),
    onRed: Color(0xFF2A1210),
    green: Color(0xFF3FD79A),
    greenTint: Color(0xFF143227),
    blue: Color(0xFF6BB6FF),
    blueTint: Color(0xFF142838),
    purple: Color(0xFFB79CFF),
    purpleTint: Color(0xFF262038),
    pink: Color(0xFFFF8FB4),
    lemon: Color(0xFFFFE066),
    line: Color(0xFF35323F),
    dash: Color(0x38F6F0E4),
    track: Color(0xFF322F3C),
    heroInk: Color(0xFF3F2B06),
    snout: Color(0xFFFFE7C2),
    blush: Color(0xFFFF8FA8),
    decorInk: Color(0xFF2A2A35),
    // 纯黑：深色主题的描边是浅的，阴影若也用墨色会像「外发光」
    shadow: Color(0xFF000000),
    veil: Color(0xFFFFFFFF),
    pie: pieColors,
  );

  /// 分类占比调色板的**源常量**（两套主题共用；测试与画笔也直接引用它）。
  static const List<Color> pieColors = <Color>[
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

  /// 取当前上下文的调色板；主题没注册时回落浅色（测试里裸 `MaterialApp` 也不炸）。
  static ToonPalette of(BuildContext context) =>
      Theme.of(context).extension<ToonPalette>() ?? light;

  @override
  ToonPalette copyWith({
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? paper,
    Color? canvas,
    Color? canvas2,
    Color? brand,
    Color? brandDeep,
    Color? onBrand,
    Color? brandInk,
    Color? brandTint,
    Color? brandTint2,
    Color? red,
    Color? redTint,
    Color? redInk,
    Color? onRed,
    Color? green,
    Color? greenTint,
    Color? blue,
    Color? blueTint,
    Color? purple,
    Color? purpleTint,
    Color? pink,
    Color? lemon,
    Color? line,
    Color? dash,
    Color? track,
    Color? heroInk,
    Color? snout,
    Color? blush,
    Color? decorInk,
    Color? shadow,
    Color? veil,
    List<Color>? pie,
  }) => ToonPalette(
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    ink3: ink3 ?? this.ink3,
    paper: paper ?? this.paper,
    canvas: canvas ?? this.canvas,
    canvas2: canvas2 ?? this.canvas2,
    brand: brand ?? this.brand,
    brandDeep: brandDeep ?? this.brandDeep,
    onBrand: onBrand ?? this.onBrand,
    brandInk: brandInk ?? this.brandInk,
    brandTint: brandTint ?? this.brandTint,
    brandTint2: brandTint2 ?? this.brandTint2,
    red: red ?? this.red,
    redTint: redTint ?? this.redTint,
    redInk: redInk ?? this.redInk,
    onRed: onRed ?? this.onRed,
    green: green ?? this.green,
    greenTint: greenTint ?? this.greenTint,
    blue: blue ?? this.blue,
    blueTint: blueTint ?? this.blueTint,
    purple: purple ?? this.purple,
    purpleTint: purpleTint ?? this.purpleTint,
    pink: pink ?? this.pink,
    lemon: lemon ?? this.lemon,
    line: line ?? this.line,
    dash: dash ?? this.dash,
    track: track ?? this.track,
    heroInk: heroInk ?? this.heroInk,
    snout: snout ?? this.snout,
    blush: blush ?? this.blush,
    decorInk: decorInk ?? this.decorInk,
    shadow: shadow ?? this.shadow,
    veil: veil ?? this.veil,
    pie: pie ?? this.pie,
  );

  @override
  ToonPalette lerp(covariant ToonPalette? other, double t) {
    if (other == null) return this;
    return ToonPalette(
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvas2: Color.lerp(canvas2, other.canvas2, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandDeep: Color.lerp(brandDeep, other.brandDeep, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      brandTint: Color.lerp(brandTint, other.brandTint, t)!,
      brandTint2: Color.lerp(brandTint2, other.brandTint2, t)!,
      red: Color.lerp(red, other.red, t)!,
      redTint: Color.lerp(redTint, other.redTint, t)!,
      redInk: Color.lerp(redInk, other.redInk, t)!,
      onRed: Color.lerp(onRed, other.onRed, t)!,
      green: Color.lerp(green, other.green, t)!,
      greenTint: Color.lerp(greenTint, other.greenTint, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      blueTint: Color.lerp(blueTint, other.blueTint, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      purpleTint: Color.lerp(purpleTint, other.purpleTint, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      lemon: Color.lerp(lemon, other.lemon, t)!,
      line: Color.lerp(line, other.line, t)!,
      dash: Color.lerp(dash, other.dash, t)!,
      track: Color.lerp(track, other.track, t)!,
      heroInk: Color.lerp(heroInk, other.heroInk, t)!,
      snout: Color.lerp(snout, other.snout, t)!,
      blush: Color.lerp(blush, other.blush, t)!,
      decorInk: Color.lerp(decorInk, other.decorInk, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      veil: Color.lerp(veil, other.veil, t)!,
      pie: <Color>[
        for (int i = 0; i < pie.length; i++)
          Color.lerp(pie[i], other.pie[i % other.pie.length], t)!,
      ],
    );
  }
}

/// `context.toon` —— 取当前主题的调色板。
extension ToonPaletteContext on BuildContext {
  ToonPalette get toon => ToonPalette.of(this);
}
