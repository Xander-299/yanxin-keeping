"""Dump MuMu/模拟器当前界面的 Flutter semantics 树，输出简洁可点列表。
用法: python .workbuddy/ui_dump.py [--raw]
每次运行自带 adb connect（沙箱会杀 daemon）。
"""
import subprocess
import sys
import xml.etree.ElementTree as ET

ADB = r"D:\Download\Java\Android\platform-tools\adb.exe"
SERIAL = "127.0.0.1:16384"


def sh(args, **kw):
    return subprocess.run([ADB, "-s", SERIAL] + args, capture_output=True, **kw)


def main():
    sh(["connect", SERIAL])
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
