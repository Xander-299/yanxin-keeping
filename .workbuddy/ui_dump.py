"""Dump MuMu/模拟器当前界面的 Flutter semantics 树，输出简洁可点列表。
用法: python .workbuddy/ui_dump.py [--raw]
每次运行自带 adb connect（沙箱会杀 daemon）。
"""
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

# adb 按机器自动挑（可用环境变量 ADB 覆盖）：A 机在 Android SDK 里，B 机在桌面 platform-tools
_ADB_CANDIDATES = [
    r"D:\Download\Java\Android\platform-tools\adb.exe",        # A 机（panda / D:）
    r"C:\Users\Administrator\Desktop\platform-tools\adb.exe",  # B 机（Administrator）
]
ADB = os.environ.get("ADB") or next(
    (p for p in _ADB_CANDIDATES if os.path.exists(p)), _ADB_CANDIDATES[0]
)
SERIAL = os.environ.get("MUMU_SERIAL", "127.0.0.1:16384")


def sh(args, **kw):
    return subprocess.run([ADB, "-s", SERIAL] + args, capture_output=True, **kw)


def main():
    sh(["connect", SERIAL])
    # ⚠️ 必须先删旧文件：`uiautomator dump` 失败时（App 切换 / 首帧未稳等）不会覆盖，
    #    紧跟着的 `cat` 就会读到**上一次**的 XML —— 表现是「界面没变 / 功能没生效」，
    #    极具误导性（2026-09-25 F7.14 首启弹层被误判成「没弹」）。删掉后 dump 失败
    #    会退化成「文件不存在」→ 下面的 `<?xml` 校验必然报 DUMP FAILED。
    sh(["shell", "rm", "-f", "/sdcard/_ui.xml"])
    sh(["shell", "uiautomator", "dump", "--compressed", "/sdcard/_ui.xml"])
    out = sh(["shell", "cat", "/sdcard/_ui.xml"]).stdout
    xml = out.decode("utf-8", "ignore")
    start = xml.find("<?xml")
    if start < 0:
        print("DUMP FAILED:", xml[:300])
        return 1
    root = ET.fromstring(xml[start:])

    rows = []
    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        label = desc or text
        if not label:
            continue
        clickable = node.get("clickable") == "true"
        b = node.get("bounds") or ""
        # bounds="[x1,y1][x2,y2]"
        nums = [int(n) for n in b.replace("[", " ").replace("]", " ").replace(",", " ").split()]
        cx, cy = (nums[0] + nums[2]) // 2, (nums[1] + nums[3]) // 2 if len(nums) == 4 else (0, 0)
        rows.append((label, clickable, cx, cy))

    for label, clickable, cx, cy in rows:
        flag = "[可点]" if clickable else "      "
        print(f"{flag} {label:<40} @({cx},{cy})")
    print(f"\n--- 共 {len(rows)} 个可见文本节点 ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
