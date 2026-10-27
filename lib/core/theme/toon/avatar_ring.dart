part of '../toon.dart';

// ────────────────────────────── 头像 / 进度环 ──────────────────────────────

/// 圆形头像（Material 3 `CircleAvatar`）：一个字符或 emoji + 可选底色。
///
/// 旧版是「描边 + 硬阴影 + 手绘」，现在只用 M3 的 tonal 圆底 —— 视觉更轻，
/// 但 API 不变，所以记一笔 / 报表 / 搜索结果里的 6 处调用点不用改。
class ToonAvatar extends StatelessWidget {
  const ToonAvatar({
    super.key,
    required this.text,
    this.bg,
    this.fg,
    this.small = false,
  });

  final String text;
  final Color? bg;
  final Color? fg;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return CircleAvatar(
      radius: small ? 17 : 19,
      backgroundColor: bg ?? p.brandTint,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: small ? 12 : 13,
          fontWeight: FontWeight.w600,
          color: fg ?? p.brandInk,
        ),
      ),
    );
  }
}

/// 环形进度 + 中心文字（Material 3 `CircularProgressIndicator`）。
class ToonRing extends StatelessWidget {
  const ToonRing({
    super.key,
    required this.progress,
    required this.color,
    required this.text,
    this.size = 58,
  });

  final double progress;
  final Color color;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 6,
              color: color,
              backgroundColor: p.track,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
        ],
      ),
    );
  }
}
