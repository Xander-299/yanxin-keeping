"""生成 Android adaptive icon 资源（纯标准库，不依赖 Dart / Pillow）。

## 为什么需要这个脚本

启动图标本身由 `flutter_launcher_icons` 生成，但它有两个缺口：

1. **它默认不生成 adaptive icon**（`mipmap-anydpi-v26/ic_launcher.xml`）—— 只出 legacy 的
   `mipmap-*/ic_launcher.png`。Android 8.0+（API 26+）拿不到 adaptive icon 就会走 legacy
   降级路径，由系统给图标**套白底 + 圆形遮罩**，真机上表现为图标周围一圈白边。
2. **本机 Dart 起不了子进程**（`CreateFile failed 231`）→ `dart run flutter_launcher_icons`
   在沙箱里跑不了，无法补生成资源。沙箱里也没有 Pillow。

## 产出（三层 + 一张预览）

| 文件 | 说明 |
|---|---|
| `<root>/assets/icon/app_icon_foreground.png` | 前景源图 1024²：透明底 + 图形缩进 66% 安全区 |
| `<root>/android/app/src/main/res/mipmap-<density>/ic_launcher_foreground.png` | 各 density 前景层（108dp 基准） |
| `<root>/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | adaptive icon 声明 |
| `<root>/android/app/src/main/res/values/ic_launcher_background.xml` | 背景色资源（取自源图主色） |
| `<root>/.workbuddy/qa-icons/adaptive-preview.png` | 圆形遮罩合成预览（仅肉眼核验，不入库） |

legacy `ic_launcher.png`（flutter_launcher_icons 的产物）**保持不动** ——
API < 26 的设备回落到它，两边视觉一致。

## 口径

- **66% 安全区**：adaptive icon 前景层画布 108dp，只有中间 66dp 不会被系统遮罩裁掉，
  所以图形最长边必须 ≤ 66/108 ≈ 61.1% 画布，否则圆 / 方形遮罩会切到笔画。
- **抠底**：按「与背景主色的距离」映射 alpha（两段式：死区内全透明 + 区间内线性过渡）。
  边缘抗锯齿像素得到中间 alpha，过渡自然；且背景层用的是**同一个颜色**，
  所以边缘残留的同色不必处理 —— 与背景天然融合。

用法（以下参数都有默认值，放进 `<项目>/tool/` 时可直接裸跑）：

    python gen_launcher_icons.py --probe          # 只看源图特征，不写文件
    python gen_launcher_icons.py                  # 生成资源
    python gen_launcher_icons.py --root <项目根>   # 在项目外（如技能目录）调用时
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from png_util import (  # noqa: E402
    alpha_stats,
    color_histogram,
    crop,
    load_png,
    opaque_bbox,
    resize_box,
    save_png,
)

FG_SOURCE_SIZE = 1024  # 官方推荐的前景源图边长
SAFE_ZONE_RATIO = 66 / 108  # adaptive icon 安全区占画布比例
CUTOUT_THRESHOLD = 100.0  # 与背景色距离 > 该值 → 完全不透明（0..441 的 3D 欧氏距离）

# 抠底死区（见 cutout_background 文档）。
# 实测源图右下角有一块 `#FFD322` 残留，距背景主色 `#FFD81B` 仅 8.6 → 只用连续映射
# 会留下 alpha≈22 的弱色斑。24 覆盖它且远小于字色距离（263），不会误伤图形。
CUTOUT_DEADZONE = 24.0

# 求图形包围盒时的 alpha 门槛。
# ⚠️ 抠底是**连续**的（alpha = 距离映射），所以背景里的轻微噪点会留下 alpha 4~8 的
#    弱残留；用低门槛（如 16）算 bbox 会把整张图边界算进去（实测 x1/y1 落到 999/969），
#    于是「图形占比」失去意义。128 让只有真正的图形 + 强抗锯齿边参与。
BBOX_ALPHA_MIN = 128

# adaptive icon 前景层边长（108dp 基准）
FG_DENSITIES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- 手工维护：flutter_launcher_icons 不产 adaptive 资源，
     本文件由 gen_launcher_icons.py 生成。改图标 → 重跑该脚本。 -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""

COLOR_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- 取自源图主色，与前景边缘残留同色 → 无缝融合 -->
    <color name="ic_launcher_background">{color}</color>
</resources>
"""


def default_root() -> Path:
    """脚本在 `<项目>/tool/` 下时项目根 = 上两级；否则退回当前工作目录。"""
    guess = Path(__file__).resolve().parent.parent
    return guess if (guess / "pubspec.yaml").exists() else Path.cwd()


def rel(path: Path, root: Path) -> str:
    """尽量显示相对路径（不在 root 下则显示绝对路径）。"""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def dominant_opaque_color(px: bytearray, w: int, h: int) -> tuple[int, int, int]:
    """取出现最多的「不透明」颜色作为背景主色。"""
    for (r, g, b, a), _ in color_histogram(px, w, h, top=40):
        if a >= 250:
            return r, g, b
    raise RuntimeError("源图找不到不透明主色（可能整张都带 alpha？）")


def cutout_background(
    px: bytearray, w: int, h: int, bg: tuple[int, int, int], threshold: float,
    deadzone: float = 0.0,
) -> bytearray:
    """把接近背景主色的像素变透明，返回新像素数组（不改原数组）。

    两段式：
    - `dist ≤ deadzone` → alpha 直接 0。实测源图边缘常有距主色 <10 的淡色残留，
      只用连续映射会留下 alpha≈22 的弱色斑；死区把它彻底抹平。
    - `deadzone < dist < threshold` → 线性过渡，保留抗锯齿边缘。
    - `dist ≥ threshold` → 原样保留。
    """
    out = bytearray(len(px))
    br, bgc, bb = bg
    span = max(1.0, threshold - deadzone)
    total = w * h
    for i in range(total):
        o = i * 4
        r, g, b, a = px[o], px[o + 1], px[o + 2], px[o + 3]
        dist = math.sqrt((r - br) ** 2 + (g - bgc) ** 2 + (b - bb) ** 2)
        out[o], out[o + 1], out[o + 2] = r, g, b
        if dist <= deadzone:
            out[o + 3] = 0
        elif dist >= threshold:
            out[o + 3] = a
        else:
            out[o + 3] = int(round(a * (dist - deadzone) / span))
    return out


def fit_into_square(
    px: bytearray, w: int, h: int, box: tuple[int, int, int, int], canvas: int, content_ratio: float
) -> bytearray:
    """把 box 内的图形裁出 → 缩放到「最长边 = content_ratio × canvas」→ 居中贴到 canvas² 透明画布。"""
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    _, _, cropped = crop(px, w, h, x0, y0, cw, ch)

    target = max(1, int(round(canvas * content_ratio)))
    if cw >= ch:
        tw, th = target, max(1, int(round(target * ch / cw)))
    else:
        th, tw = target, max(1, int(round(target * cw / ch)))

    _, _, resized = resize_box(cropped, cw, ch, tw, th)

    out = bytearray(canvas * canvas * 4)  # 全透明
    ox, oy = (canvas - tw) // 2, (canvas - th) // 2
    for y in range(th):
        src = y * tw * 4
        dst = ((oy + y) * canvas + ox) * 4
        out[dst:dst + tw * 4] = resized[src:src + tw * 4]
    return out


def render_round_preview(
    fg: bytearray, canvas: int, bg: tuple[int, int, int], path: Path
) -> None:
    """把前景层合成到背景色上，再套**圆形遮罩**（launcher 最常见的裁切形状），
    圆外填浅灰冒充桌面 —— 一眼就能看出图形有没有被裁到。

    Android 圆形遮罩是自适应裁剪（各 OEM 半径略有差异），这里用「内切圆、留 2px 余量」
    作为最严苛情形；图形过不了这一关就说明安全区没留够。
    """
    out = bytearray(canvas * canvas * 4)
    for i in range(canvas * canvas):
        out[i * 4:i * 4 + 4] = b"\xF2\xF2\xF2\xFF"  # 浅灰桌面底

    cx = cy = canvas / 2.0
    r = canvas / 2.0 - 2
    r2 = r * r
    for y in range(canvas):
        dy = y - cy + 0.5
        row = y * canvas
        for x in range(canvas):
            dx = x - cx + 0.5
            if dx * dx + dy * dy > r2:
                continue
            o = (row + x) * 4
            a = fg[o + 3]
            if a == 0:
                out[o], out[o + 1], out[o + 2] = bg
                continue
            inv = 255 - a
            out[o] = (fg[o] * a + bg[0] * inv) // 255
            out[o + 1] = (fg[o + 1] * a + bg[1] * inv) // 255
            out[o + 2] = (fg[o + 2] * a + bg[2] * inv) // 255
    save_png(path, canvas, canvas, out)


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 adaptive icon 资源")
    ap.add_argument("--root", type=Path, default=None, help="项目根（默认：脚本上两级，否则 CWD）")
    ap.add_argument("--source", type=Path, default=None, help="图标源图（默认 <root>/assets/icon/app_icon.png）")
    ap.add_argument("--fg-source", type=Path, default=None, help="前景源图输出路径")
    ap.add_argument("--res", type=Path, default=None, help="Android res 目录")
    ap.add_argument("--preview", type=Path, default=None, help="圆形遮罩预览输出路径")
    ap.add_argument("--probe", action="store_true", help="只打印源图特征，不写文件")
    ap.add_argument("--threshold", type=float, default=CUTOUT_THRESHOLD, help="抠底距离阈值")
    ap.add_argument("--deadzone", type=float, default=CUTOUT_DEADZONE, help="抠底死区（≤ 该距离直接全透明）")
    args = ap.parse_args()

    root = (args.root or default_root()).resolve()
    source = (args.source or root / "assets/icon/app_icon.png").resolve()
    fg_source = (args.fg_source or root / "assets/icon/app_icon_foreground.png").resolve()
    res = (args.res or root / "android/app/src/main/res").resolve()
    preview = (args.preview or root / ".workbuddy/qa-icons/adaptive-preview.png").resolve()

    if not source.exists():
        print(f"❌ 源图不存在：{source}")
        return 2

    print(f"项目根 {root}")
    print(f"解码 {rel(source, root)} …")
    w, h, px = load_png(source)
    print(f"  尺寸 {w}x{h}" + ("" if w == h else f"  ⚠️ 非正方形（差 {abs(w - h)}px）"))

    bg = dominant_opaque_color(px, w, h)
    hex_bg = "#{:02X}{:02X}{:02X}".format(*bg)
    print(f"  背景主色 {hex_bg}")

    print("  颜色直方图 top6：")
    for (r, g, b, a), n in color_histogram(px, w, h, top=6):
        print(f"    #{r:02X}{g:02X}{b:02X} a={a:<3} 采样计数 {n}")

    if args.probe:
        print(f"\n  alpha 分布：{alpha_stats(px, w, h)}")
        cut = cutout_background(px, w, h, bg, args.threshold, args.deadzone)
        print("  抠底后按不同 alpha 门槛算包围盒（诊断用）：")
        for amin in (8, 16, 64, 128, 200):
            box = opaque_bbox(cut, w, h, alpha_min=amin)
            if box is None:
                print(f"    alpha≥{amin:<4} → 无")
                continue
            bx0, by0, bx1, by1 = box
            print(f"    alpha≥{amin:<4} → ({bx0},{by0})-({bx1},{by1})  "
                  f"{bx1 - bx0 + 1}x{by1 - by0 + 1}")
        print("  右/下边缘采样（找 bbox 撑到图边界的原因）：")
        for label, pts in (
            ("右边缘 x=w-1", [(w - 1, y) for y in (5, h // 2, h - 20, h - 1)]),
            ("下边缘 y=h-1", [(x, h - 1) for x in (5, w // 2, w - 20, w - 1)]),
        ):
            print(f"    {label}:")
            for x, y in pts:
                o = (y * w + x) * 4
                r, g, b, a = px[o], px[o + 1], px[o + 2], px[o + 3]
                dist = math.sqrt((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2)
                print(f"      ({x},{y}) #{r:02X}{g:02X}{b:02X} a={a} 距背景色 {dist:.1f}"
                      f" → 抠底后 alpha {int(round(a * min(1.0, dist / args.threshold)))}")
        print("\n（--probe 模式：未写任何文件）")
        return 0

    print(f"  抠底（阈值 {args.threshold:.0f} / 死区 {args.deadzone:.0f}）…")
    cut = cutout_background(px, w, h, bg, args.threshold, args.deadzone)

    box = opaque_bbox(cut, w, h, alpha_min=BBOX_ALPHA_MIN)
    if box is None:
        print(f"❌ 抠底后没有 alpha≥{BBOX_ALPHA_MIN} 的像素 —— 阈值过大，图形被抠掉了。")
        return 3
    x0, y0, x1, y1 = box
    print(f"  图形包围盒 ({x0},{y0})-({x1},{y1})  = {x1 - x0 + 1}x{y1 - y0 + 1}"
          f"（alpha≥{BBOX_ALPHA_MIN}）")

    # 1) 前景源图（1024²，图形占 61.1% 安全区）
    fg = fit_into_square(cut, w, h, box, FG_SOURCE_SIZE, SAFE_ZONE_RATIO)
    save_png(fg_source, FG_SOURCE_SIZE, FG_SOURCE_SIZE, fg)
    print(f"  ✅ {rel(fg_source, root)}  {FG_SOURCE_SIZE}²  "
          f"内容占比 {SAFE_ZONE_RATIO:.1%}（安全区）")

    # 2) 各 density 前景层
    for folder, size in FG_DENSITIES.items():
        _, _, scaled = resize_box(fg, FG_SOURCE_SIZE, FG_SOURCE_SIZE, size, size)
        out = res / folder / "ic_launcher_foreground.png"
        save_png(out, size, size, scaled)
        print(f"  ✅ {rel(out, root)}  {size}²")

    # 3) adaptive icon 声明 + 背景色
    xml_dir = res / "mipmap-anydpi-v26"
    xml_dir.mkdir(parents=True, exist_ok=True)
    (xml_dir / "ic_launcher.xml").write_text(ADAPTIVE_XML, encoding="utf-8", newline="\n")
    print(f"  ✅ {rel(xml_dir / 'ic_launcher.xml', root)}")

    color_xml = res / "values" / "ic_launcher_background.xml"
    color_xml.parent.mkdir(parents=True, exist_ok=True)
    color_xml.write_text(COLOR_XML.format(color=hex_bg), encoding="utf-8", newline="\n")
    print(f"  ✅ {rel(color_xml, root)}  background = {hex_bg}")

    # 4) 圆形遮罩预览（只看效果，不入库）
    render_round_preview(fg, FG_SOURCE_SIZE, bg, preview)
    print(f"  👁  {rel(preview, root)}  （圆形遮罩合成预览，用于肉眼核验安全区）")

    print("\n完成。legacy ic_launcher.png 未改动（API<26 回落用，视觉一致）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
