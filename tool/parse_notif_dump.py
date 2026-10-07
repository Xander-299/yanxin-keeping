"""从 `adb shell dumpsys notification --noredact` 的输出里抽出「包名 + 通知文案」。

用途（F7.15 真机排查）：拿到微信 / 支付宝通知的**真实文案**，用来校准
`lib/features/autobook/data/auto_book_rules.dart` 里的关键词与金额正则。

用法：
    adb shell dumpsys notification --noredact > dump.txt
    python tool/parse_notif_dump.py dump.txt [包名过滤...]

输出每个 NotificationRecord 的 pkg / title / text / bigText / subText / tickerText，
只保留含中文或含「元/¥」等有解析价值的记录（可用 --all 放开）。
"""

from __future__ import annotations

import re
import sys

REC_START = re.compile(r"^\s{4}NotificationRecord\(0x[0-9a-f]+:\s*(.*)\)\s*$")
PKG = re.compile(r"pkg=(\S+)")
EXTRAS_START = re.compile(r"^\s+extras=\{\s*$")

# 只关心这些 extra key（与 Kotlin 侧取的位置一致）
WANTED = (
    "android.title",
    "android.text",
    "android.bigText",
    "android.subText",
    "android.infoText",
    "android.summaryText",
    "android.tickerText",
)

KEYVAL = re.compile(r"^\s{16}([A-Za-z0-9_.]+)=(.+?)\s*$")


def parse(path: str) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    cur: dict[str, str] | None = None
    in_extras = False
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = REC_START.match(line)
            if m:
                cur = {"pkg": (PKG.search(m.group(1)) or re.search(r"pkg=(\S+)", m.group(1))).group(1) if PKG.search(m.group(1)) else "?"}
                records.append(cur)
                in_extras = False
                continue
            if cur is None:
                continue
            if EXTRAS_START.match(line):
                in_extras = True
                continue
            if in_extras:
                if line.strip().startswith("}"):
                    in_extras = False
                    continue
                kv = KEYVAL.match(line)
                if kv and kv.group(1) in WANTED:
                    val = kv.group(2)
                    # 值形如 `String (真实文案)` / `SpannableString (..)` / `CharSequence (..)`
                    vm = re.match(r"^[A-Za-z]+ \((.*)\)$", val, re.S)
                    text = (vm.group(1) if vm else val).strip()
                    # dumpsys 对未设置的 extra 直接打印裸 `null`（不是 String(null)）→ 丢弃
                    if text and text != "null":
                        cur[kv.group(1)] = text
    return records


def main() -> int:
    args = [a for a in sys.argv[1:]]
    show_all = "--all" in args
    args = [a for a in args if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    path, filters = args[0], args[1:]
    recs = parse(path)
    if filters:
        recs = [r for r in recs if any(f.lower() in r.get("pkg", "").lower() for f in filters)]
    shown = 0
    for r in recs:
        body = " ".join(r.get(k, "") for k in WANTED[1:])
        interesting = show_all or bool(re.search(r"[\u4e00-\u9fff]", body)) or ("元" in body) or ("¥" in body)
        if not interesting:
            continue
        shown += 1
        print("-" * 72)
        print("pkg   :", r.get("pkg", "?"))
        for k in WANTED:
            if r.get(k):
                print(f"{k.split('.')[-1]:9s}:", r[k])
    print("-" * 72)
    print(f"records total={len(recs)} shown={shown}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
