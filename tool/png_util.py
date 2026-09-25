"""纯标准库 PNG 编解码 + 缩放（8bit、非交错）。

为什么不用 Pillow：本机沙箱 PyPI 不稳（见 skill `pdf-text-extract-stdlib`），
且项目坚持「零新依赖」。启动图标生成只需要 RGBA8 + 面积平均缩放，标准库足够。

用法（作为模块）：
    from png_util import load_png, save_png, crop, resize_box, color_histogram
    w, h, px = load_png(path)          # px = bytearray(w*h*4)，RGBA8
    save_png(path, w, h, px)
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"


# ---------------------------------------------------------------- 解码

def _unfilter(raw: bytes, width: int, height: int, bpp: int) -> bytearray:
    """把 IDAT 解压后的原始扫描线做反滤波，返回紧凑 RGBA8 像素数组。"""
    stride = width * bpp
    out = bytearray(stride * height)
    pos = 0
    prev = bytearray(stride)  # 上一行（首行全 0）
    for y in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 0:  # None
            pass
        elif ftype == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        else:
            raise ValueError(f"未知的 PNG filter 类型：{ftype}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


def load_png(path: str | Path) -> tuple[int, int, bytearray]:
    """读取 PNG，返回 (width, height, RGBA8 像素)。支持灰度/RGB/RGBA/灰度+A。"""
    data = Path(path).read_bytes()
    if data[:8] != PNG_SIG:
        raise ValueError(f"{path} 不是合法 PNG")

    pos = 8
    width = height = bit_depth = color_type = interlace = None
    idat = bytearray()
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length  # 8 头 + length + 4 CRC
        if ctype == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif ctype == b"IDAT":
            idat.extend(body)
        elif ctype == b"IEND":
            break

    if bit_depth != 8:
        raise ValueError(f"只支持 8bit PNG，实为 {bit_depth}bit")
    if interlace != 0:
        raise ValueError("不支持交错（Adam7）PNG")

    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color_type]
    raw = zlib.decompress(bytes(idat))
    flat = _unfilter(raw, width, height, channels)

    # 统一转成 RGBA8
    px = bytearray(width * height * 4)
    if channels == 4:
        px[:] = flat
    else:
        for i in range(width * height):
            v = flat[i * channels:(i + 1) * channels]
            o = i * 4
            if channels == 1:
                px[o] = px[o + 1] = px[o + 2] = v[0]
                px[o + 3] = 255
            elif channels == 2:
                px[o] = px[o + 1] = px[o + 2] = v[0]
                px[o + 3] = v[1]
            else:  # 3
                px[o], px[o + 1], px[o + 2], px[o + 3] = v[0], v[1], v[2], 255
    return width, height, px


# ---------------------------------------------------------------- 编码

def _chunk(ctype: bytes, body: bytes) -> bytes:
    return (
        struct.pack(">I", len(body))
        + ctype
        + body
        + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF)
    )


def save_png(path: str | Path, width: int, height: int, px: bytes | bytearray) -> None:
    """把 RGBA8 像素写为 PNG（filter 全 0，zlib 最高压缩）。"""
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None
        raw.extend(px[y * stride:(y + 1) * stride])

    out = bytearray(PNG_SIG)
    out += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    out += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += _chunk(b"IEND", b"")
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(bytes(out))


# ---------------------------------------------------------------- 几何

def crop(px: bytes | bytearray, w: int, h: int, x0: int, y0: int, cw: int, ch: int) -> tuple[int, int, bytearray]:
    """裁切出 [x0, x0+cw) × [y0, y0+ch)。"""
    out = bytearray(cw * ch * 4)
    for y in range(ch):
        s = ((y0 + y) * w + x0) * 4
        out[y * cw * 4:(y + 1) * cw * 4] = px[s:s + cw * 4]
    return cw, ch, out


def resize_box(px: bytes | bytearray, sw: int, sh: int, dw: int, dh: int) -> tuple[int, int, bytearray]:
    """面积平均（box filter）缩放 —— 缩小时比最近邻/双线性更少混叠。

    对目标像素覆盖的源区域做**加权**平均（含 alpha 加权，避免透明边发黑）。
    """
    out = bytearray(dw * dh * 4)
    x_ratio = sw / dw
    y_ratio = sh / dh
    for dy in range(dh):
        sy0 = dy * y_ratio
        sy1 = (dy + 1) * y_ratio
        y_start, y_end = int(sy0), min(sh, int(-(-sy1 // 1)))
        for dx in range(dw):
            sx0 = dx * x_ratio
            sx1 = (dx + 1) * x_ratio
            x_start, x_end = int(sx0), min(sw, int(-(-sx1 // 1)))

            acc_r = acc_g = acc_b = acc_a = 0.0
            wsum = 0.0
            for sy in range(y_start, y_end):
                wy = min(sy + 1, sy1) - max(sy, sy0)
                if wy <= 0:
                    continue
                srow = sy * sw
                for sx in range(x_start, x_end):
                    wx = min(sx + 1, sx1) - max(sx, sx0)
                    if wx <= 0:
                        continue
                    wgt = wx * wy
                    o = (srow + sx) * 4
                    a = px[o + 3]
                    # 预乘 alpha 累加 → 防止透明像素的黑色渗入
                    acc_r += px[o] * a * wgt
                    acc_g += px[o + 1] * a * wgt
                    acc_b += px[o + 2] * a * wgt
                    acc_a += a * wgt
                    wsum += wgt
            d = (dy * dw + dx) * 4
            if wsum == 0 or acc_a == 0:
                out[d:d + 4] = b"\x00\x00\x00\x00"
                continue
            out[d] = int(round(acc_r / acc_a))
            out[d + 1] = int(round(acc_g / acc_a))
            out[d + 2] = int(round(acc_b / acc_a))
            out[d + 3] = int(round(acc_a / wsum))
    return dw, dh, out


# ---------------------------------------------------------------- 分析

def color_histogram(px: bytes | bytearray, w: int, h: int, top: int = 12) -> list[tuple[tuple[int, int, int, int], int]]:
    """统计出现最多的颜色（采样步长自适应，大图不全量遍历）。"""
    total = w * h
    step = max(1, total // 200_000)
    counts: dict[tuple[int, int, int, int], int] = {}
    for i in range(0, total, step):
        o = i * 4
        key = (px[o], px[o + 1], px[o + 2], px[o + 3])
        counts[key] = counts.get(key, 0) + 1
    return sorted(counts.items(), key=lambda kv: -kv[1])[:top]


def alpha_stats(px: bytes | bytearray, w: int, h: int) -> dict[str, int]:
    """alpha 分布：完全不透明 / 完全透明 / 半透明 的像素数。"""
    total = w * h
    opaque = translucent = transparent = 0
    for i in range(total):
        a = px[i * 4 + 3]
        if a == 255:
            opaque += 1
        elif a == 0:
            transparent += 1
        else:
            translucent += 1
    return {"不透明": opaque, "半透明": translucent, "全透明": transparent}


def opaque_bbox(px: bytes | bytearray, w: int, h: int, alpha_min: int = 16) -> tuple[int, int, int, int] | None:
    """返回「非全透明」像素的包围盒 (x0, y0, x1, y1)（闭区间）。"""
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = y * w
        for x in range(w):
            if px[(row + x) * 4 + 3] >= alpha_min:
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    if x1 < 0:
        return None
    return x0, y0, x1, y1
