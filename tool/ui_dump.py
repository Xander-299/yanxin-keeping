#!/usr/bin/env python3
"""抓取 Android 设备当前界面的无障碍语义树（uiautomator dump），输出可点节点与坐标。

用途：Flutter 应用的文本 / 按钮都会出现在语义树里，读得到文案 ≈ 用户看得到，
比截图更适合脚本化断言（截图的像素判读见 `docs/dev/android-ui-smoke.md`）。

用法:
    python tool/ui_dump.py            # 打印「[可点] 文案 @(x,y)」列表
    python tool/ui_dump.py --raw      # 额外打印原始 XML

环境变量:
    ADB          adb 可执行文件路径（默认依次找 PATH、ANDROID_HOME、ANDROID_SDK_ROOT）
    MUMU_SERIAL  设备序列号（默认 127.0.0.1:16384）

注意：脚本会先删除设备上的旧 dump 文件再抓取 —— `uiautomator dump` 在界面切换
瞬间会失败且**不覆盖**旧文件，紧跟着的读取就会拿到上一屏的语义树，表现为
「改了代码但界面没变」，极具误导性。
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

DUMP_PATH = "/sdcard/_ui.xml"


def find_adb() -> str:
    """按 环境变量 → PATH → Android SDK 常见位置 的顺序找 adb。"""
    explicit = os.environ.get("ADB")
    if explicit:
        return explicit

    on_path = shutil.which("adb")
    if on_path:
        return on_path

    candidates: list[str] = []
    for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        root = os.environ.get(key)
        if root:
            candidates.append(os.path.join(root, "platform-tools", "adb.exe"))
            candidates.append(os.path.join(root, "platform-tools", "adb"))
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        candidates.append(os.path.join(local_app_data, "Android", "Sdk", "platform-tools", "adb.exe"))

    for path in candidates:
        if os.path.exists(path):
            return path

    raise SystemExit(
        "找不到 adb。请设置 ADB=<adb 路径>，或把 platform-tools 加进 PATH"
        "（也可设置 ANDROID_HOME / ANDROID_SDK_ROOT）。"
    )


ADB = find_adb()
SERIAL = os.environ.get("MUMU_SERIAL", "127.0.0.1:16384")


def sh(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([ADB, "-s", SERIAL, *args], capture_output=True)


def main() -> int:
    sh(["connect", SERIAL])
    # 必须先删旧文件：dump 失败时不覆盖，读到的会是上一屏的语义树。
    sh(["shell", "rm", "-f", DUMP_PATH])
    sh(["shell", "uiautomator", "dump", "--compressed", DUMP_PATH])
    out = sh(["shell", "cat", DUMP_PATH]).stdout
    xml = out.decode("utf-8", "ignore")
    start = xml.find("<?xml")
    if start < 0:
        print("DUMP FAILED:", xml[:300])
        return 1
    root = ET.fromstring(xml[start:])

    if "--raw" in sys.argv:
        print(xml[start:])

    rows: list[tuple[str, bool, int, int]] = []
    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        label = desc or text
        if not label:
            continue
        clickable = node.get("clickable") == "true"
        bounds = node.get("bounds") or ""
        # bounds="[x1,y1][x2,y2]"
        nums = [int(n) for n in bounds.replace("[", " ").replace("]", " ").replace(",", " ").split()]
        if len(nums) == 4:
            cx, cy = (nums[0] + nums[2]) // 2, (nums[1] + nums[3]) // 2
        else:
            cx, cy = 0, 0
        rows.append((label, clickable, cx, cy))

    for label, clickable, cx, cy in rows:
        flag = "[可点]" if clickable else "      "
        print(f"{flag} {label:<40} @({cx},{cy})")
    print(f"\n--- 共 {len(rows)} 个可见文本节点 ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
