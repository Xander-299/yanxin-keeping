"""轮询 `dumpsys notification --noredact`，把微信/支付宝通知的**真实文案**抓下来。

背景（F7.15）：真机反馈「能抓取但无法识别」——必须拿到真实通知的 title/text/bigText
才能判断是①包名没命中 ②忽略词误杀 ③方向词不匹配 ④金额正则不匹配。

用法：
    python tool/watch_notifications.py [--serial <sn>] [--seconds 600] [--out <file>] [--pkg a,b]

去重键 = pkg|title|text|bigText|subText；命中的记录追加写入 out（JSONL）。
Ctrl-C 或超时后打印汇总。
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_notif_dump import WANTED, parse  # noqa: E402

DEFAULT_PKGS = ("com.tencent.mm", "com.eg.android.AlipayGphone")


def dump(serial: str | None) -> str:
    cmd = ["adb"]
    if serial:
        cmd += ["-s", serial]
    cmd += ["shell", "dumpsys", "notification", "--noredact"]
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=40)
    except subprocess.TimeoutExpired:
        return ""
    return out.stdout.decode("utf-8", errors="replace")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", default=None)
    ap.add_argument("--seconds", type=int, default=600)
    ap.add_argument("--out", default=".workbuddy/qa-f715-real/watched.jsonl")
    ap.add_argument("--pkg", default=",".join(DEFAULT_PKGS))
    ap.add_argument("--interval", type=float, default=1.2)
    args = ap.parse_args()

    pkgs = [p.strip() for p in args.pkg.split(",") if p.strip()]
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    seen: set[str] = set()
    hits = 0
    t0 = time.time()
    print(f"[watch] 轮询中（{args.seconds}s，过滤 {pkgs}）→ {out_path}", flush=True)

    while time.time() - t0 < args.seconds:
        text = dump(args.serial)
        if text:
            tmp = out_path.parent / "_dump_tmp.txt"
            tmp.write_text(text, encoding="utf-8")
            for rec in parse(str(tmp)):
                if rec.get("pkg") not in pkgs:
                    continue
                body = " ".join(rec.get(k, "") for k in WANTED)
                key = rec.get("pkg", "") + "|" + body
                if key in seen:
                    continue
                seen.add(key)
                hits += 1
                rec["_capturedAt"] = time.strftime("%Y-%m-%d %H:%M:%S")
                with out_path.open("a", encoding="utf-8") as fh:
                    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
                print("=" * 70, flush=True)
                print("pkg   :", rec.get("pkg"))
                for k in WANTED:
                    if rec.get(k):
                        print(f"{k.split('.')[-1]:9s}: {rec[k]}")
                sys.stdout.flush()
        time.sleep(args.interval)

    print(f"[watch] 结束：抓到 {hits} 条新记录 → {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
