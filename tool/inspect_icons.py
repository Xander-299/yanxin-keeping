"""自查启动图标资源：PNG 头解析（纯标准库，无需 Pillow）。

用途：F7.9f 图标批次的资源体检 —— 验源图与各 density 产物的真实像素尺寸、
是否含 alpha、文件是否为合法 PNG。本机 Dart 起不了子进程，改用 Python。

用法：python tool/inspect_icons.py
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TARGETS = [
    ("源图", "assets/icon/app_icon.png"),
    ("前景源图", "assets/icon/app_icon_foreground.png"),
    ("mdpi  48", "android/app/src/main/res/mipmap-mdpi/ic_launcher.png"),
    ("hdpi  72", "android/app/src/main/res/mipmap-hdpi/ic_launcher.png"),
    ("xhdpi 96", "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"),
    ("xxhdpi144", "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"),
    ("xxxhdpi192", "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"),
    ("fg-mdpi 108", "android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png"),
    ("fg-hdpi 162", "android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png"),
    ("fg-xh 216", "android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png"),
    ("fg-xx 324", "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png"),
    ("fg-xxx 432", "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png"),
]

# 目录名 → (legacy 期望边长, adaptive 前景层期望边长)
DENSITY_SIZES = {
    "mipmap-mdpi": (48, 108),
    "mipmap-hdpi": (72, 162),
    "mipmap-xhdpi": (96, 216),
    "mipmap-xxhdpi": (144, 324),
    "mipmap-xxxhdpi": (192, 432),
}

# PNG color type -> 名称
COLOR_TYPE = {0: "灰度", 2: "RGB", 3: "索引", 4: "灰度+A", 6: "RGBA"}


def read_png_header(path: Path) -> tuple[int, int, int, str]:
    """返回 (width, height, bit_depth, color_type_name)。非 PNG 则抛错。"""
    with path.open("rb") as fh:
        sig = fh.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise ValueError("不是合法 PNG（签名不符）")
        length = struct.unpack(">I", fh.read(4))[0]
        chunk_type = fh.read(4)
        if chunk_type != b"IHDR":
            raise ValueError(f"首个 chunk 不是 IHDR，而是 {chunk_type!r}")
        data = fh.read(length)
        width, height, bit_depth, color_type = struct.unpack(">IIBB", data[:10])
    return width, height, bit_depth, COLOR_TYPE.get(color_type, f"未知({color_type})")


def main() -> int:
    problems: list[str] = []
    print(f"{'角色':<11} {'路径':<52} {'尺寸':>12}  位深/色型")
    print("-" * 92)

    for role, rel in TARGETS:
        path = ROOT / rel
        if not path.exists():
            problems.append(f"缺失：{rel}")
            print(f"{role:<11} {rel:<52} {'—':>12}  ❌ 文件不存在")
            continue
        try:
            w, h, depth, ctype = read_png_header(path)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"非法 PNG：{rel}（{exc}）")
            print(f"{role:<11} {rel:<52} {'—':>12}  ❌ {exc}")
            continue

        size = f"{w}x{h}"
        is_source = rel == "assets/icon/app_icon.png"
        dir_name = Path(rel).parent.name
        stem = Path(rel).stem

        if w != h:
            if is_source:
                # 源图非正方形只作提示：flutter_launcher_icons 会按目标边长硬缩放
                # （1000→970 差 30px ≈ 3% 横向压缩），肉眼不可见；
                # 且源图是用户资产，工具不去改它。
                print(f"{role:<11} {rel:<52} {size:>12}  {depth}bit {ctype}  ℹ️ 非正方形（差 {abs(w - h)}px）")
            else:
                problems.append(f"非正方形：{rel} = {size}")
                print(f"{role:<11} {rel:<52} {size:>12}  {depth}bit {ctype}  ⚠️ 非正方形")
            continue

        # 尺寸校验：legacy ic_launcher.png / adaptive ic_launcher_foreground.png
        note = ""
        if dir_name in DENSITY_SIZES:
            legacy, adaptive = DENSITY_SIZES[dir_name]
            expected = adaptive if stem == "ic_launcher_foreground" else legacy
            if w != expected:
                problems.append(f"尺寸不符：{rel} 期望 {expected}²，实为 {size}")
                note = f"  ⚠️ 期望 {expected}²"
        print(f"{role:<11} {rel:<52} {size:>12}  {depth}bit {ctype}{note}")

    # adaptive icon 资源是否存在（Android 8.0+ / API 26+ 必需）
    print("\n=== adaptive icon（API 26+）===")
    anydpi = ROOT / "android/app/src/main/res/mipmap-anydpi-v26"
    xml = anydpi / "ic_launcher.xml"
    if xml.exists():
        print(f"  ✅ {xml.relative_to(ROOT)}")
    else:
        print(f"  ❌ 缺 {xml.relative_to(ROOT)} → Android 8.0+ 会给图标套白底/白圈")
        problems.append("缺 adaptive icon（mipmap-anydpi-v26/ic_launcher.xml）")

    # 背景层：色值资源（values/）或 drawable 皆可
    bg_values = ROOT / "android/app/src/main/res/values/ic_launcher_background.xml"
    bg_drawable = list((ROOT / "android/app/src/main/res/drawable").glob("ic_launcher_background.*"))
    if bg_values.exists() or bg_drawable:
        found = bg_values if bg_values.exists() else bg_drawable[0]
        print(f"  ✅ 背景层 {found.relative_to(ROOT)}")
    else:
        print("  ❌ 缺背景层资源（values/ic_launcher_background.xml）")
        problems.append("缺 adaptive 背景层资源")

    # adaptive 前景层数量（5 个 density 齐否）
    fg_count = len(list((ROOT / "android/app/src/main/res").glob("mipmap-*/ic_launcher_foreground.png")))
    if fg_count == len(DENSITY_SIZES):
        print(f"  ✅ 前景层 {fg_count}/{len(DENSITY_SIZES)} 个 density 齐备")
    else:
        print(f"  ❌ 前景层只有 {fg_count}/{len(DENSITY_SIZES)} 个 density")
        problems.append(f"前景层缺 density（{fg_count}/{len(DENSITY_SIZES)}）")

    print("\n=== 汇总 ===")
    if problems:
        for p in problems:
            print(f"  ⚠️ {p}")
        return 1
    print("  全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
