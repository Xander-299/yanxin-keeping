"""真机取证：验证「微信/支付宝支付通知会被撤回」这个前提是否成立。

背景（F7.16 候选修复）：用户反馈「返回微信/支付宝后通知会被丢弃，应用没来得及采集」。
上一轮已加 `catchUp()`（补抓），但它的**固有边界**是「只能捞此刻仍在通知栏里的通知」。
若支付成功页一出现、微信就 cancel 掉通知 → 补抓也捞不到 → 该场景永久丢账。

## 为什么需要这个工具（而不是直接写代码）

计划中的修复是「实现 `onNotificationRemoved` 回调，在通知被撤回那一刻仍读 extras」。
但**该回调是我们自己代码里的** —— 不写就不存在，纯 adb 无法验证它。
纯 adb 能验证的是它的**前提**：

1. 支付通知**是否真的会被撤回**（`getActiveNotifications()` 之后查不到）；
2. 撤回得**有多快**（决定补抓的竞态窗口有多大）；
3. 撤回后本App 队列 / 诊断**是否真的没记上**（问题确实存在，而非误判）。

前提不成立 → 整个修复方向作废，改走别的路。所以先跑这个。

## 用法

    # 1) 先开着，等用户在手机上做一笔真实支付并点进「支付成功」页
    python tool/probe_notify_lifecycle.py --seconds 300 --out .workbuddy/qa-f716/lifecycle.jsonl

    # 2) 汇总（也可在运行中随时 Ctrl-C 触发）
    python tool/probe_notify_lifecycle.py --summarize .workbuddy/qa-f716/lifecycle.jsonl

## 采集两条独立证据

- **dumpsys 轮询**（系统真相）：`dumpsys notification --noredact` 里该通知的**在场/消失**。
- **logcat**（行为真相）：`AutoBookListener` 标签的判定链输出 + 系统 cancel 日志。

⚠️ dumpsys 一次约 0.6–2s，**轮询有盲区** —— 极短的通知可能被整个跳过。
故本工具只对「曾经出现过 → 后来消失了」下结论（**有证据**）；
「没出现过」一律标注为 `MISSED_BY_POLL`（**无证据**，不能据此说通知不存在）。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse_notif_dump import WANTED, parse  # noqa: E402

DEFAULT_PKGS = ("com.tencent.mm", "com.eg.android.AlipayGphone")

# 支付相关关键词 —— 只用来「挑出值得追踪的那条」，判定是否支付仍由 Dart 侧规则负责。
PAY_HINT = re.compile(r"支付|付款|收款|到账|已付|支出|收入|交易|订单|¥|元|余额|转账")


def _adb(serial: str | None, *args: str, timeout: int = 40) -> str:
    cmd = ["adb"]
    if serial:
        cmd += ["-s", serial]
    cmd += list(args)
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return ""
    return out.stdout.decode("utf-8", errors="replace")


def is_payment_like(rec: dict[str, str]) -> bool:
    """看起来像一条支付/交易通知（含中文或金额线索）。"""
    body = " ".join(rec.get(k, "") for k in WANTED)
    return bool(PAY_HINT.search(body))


def fingerprint(rec: dict[str, str]) -> str:
    """跨轮次稳定的身份：去掉折叠前缀这类**显示层**装饰，只留实质内容。

    MIUI 会给正文加 `[3条]` 前缀，且同一条通知的 title/text 组合可能随展开态变化；
    用 pkg+全部文案做键，会把「同一条通知」误判成多条。
    """
    body = " ".join(rec.get(k, "") for k in WANTED)
    body = re.sub(r"\[\d+条\]\s*", "", body)
    return rec.get("pkg", "") + "|" + body.strip()


class LogcatWatcher(threading.Thread):
    """后台持续抓 logcat，只留与自动记账 / 通知取消有关的行。"""

    KEEP = re.compile(r"AutoBook|autobook|NotificationManagerService|NotificationService|cancel")

    def __init__(self, serial: str | None, out_path: Path) -> None:
        super().__init__(daemon=True)
        self.serial = serial
        self.out_path = out_path
        self.stop_flag = threading.Event()
        self.lines: list[str] = []

    def run(self) -> None:  # pragma: no cover - 走查工具
        cmd = ["adb"]
        if self.serial:
            cmd += ["-s", self.serial]
        cmd += ["logcat", "-v", "time", "-T", "1"]
        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=1
            )
        except Exception as e:  # noqa: BLE001
            print(f"[logcat] 启动失败：{e}")
            return
        assert proc.stdout is not None
        try:
            for raw in proc.stdout:
                if self.stop_flag.is_set():
                    break
                line = raw.decode("utf-8", errors="replace").rstrip()
                if self.KEEP.search(line):
                    self.lines.append(line)
        finally:
            proc.kill()

    def dump(self) -> None:
        try:
            self.out_path.write_text("\n".join(self.lines), encoding="utf-8")
        except Exception:  # noqa: BLE001
            pass


def read_app_state(serial: str | None) -> dict[str, str]:
    """读本App 的队列与诊断（区分「没抓到」与「抓到了没入队」）。"""
    q = _adb(serial, "shell", "run-as", "com.teacodeman.yanxin",
             "cat", "files/autobook_queue.jsonl")
    d = _adb(serial, "shell", "run-as", "com.teacodeman.yanxin",
             "cat", "files/autobook_diag.json")
    try:
        diag = json.loads(d.strip() or "{}")
    except Exception:  # noqa: BLE001
        diag = {}
    return {"queueLines": len([x for x in q.splitlines() if x.strip()]), "diag": diag}


def summarize(path: Path) -> int:
    if not path.exists():
        print(f"[summary] 找不到 {path}")
        return 2
    seen: dict[str, dict] = {}
    order: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except Exception:  # noqa: BLE001
            continue
        kind = rec.get("_event")
        fp = rec.get("fp", "")
        if kind == "seen":
            if fp not in seen:
                seen[fp] = {"first": rec, "last": rec, "gone": False}
                order.append(fp)
            else:
                seen[fp]["last"] = rec
        elif kind == "gone":
            if fp in seen:
                seen[fp]["gone"] = True
                seen[fp]["goneAt"] = rec
    print("=" * 74)
    print(f"抓取记录 {len(order)} 条去重后的微信/支付宝通知")
    print("=" * 74)
    vanished = 0
    for fp in order:
        it = seen[fp]
        f, l = it["first"], it["last"]
        dur = (l["_ms"] - f["_ms"]) / 1000.0
        print("-" * 74)
        print("pkg    :", f.get("pkg"))
        print("title  :", f.get("android.title", ""))
        print("text   :", f.get("android.text", ""))
        if f.get("android.bigText"):
            print("bigText:", f["android.bigText"])
        print(f"在场   : {f['_time']} → {l['_time']}（约 {dur:.0f}s，轮询 {l['_poll']} 次）")
        if it["gone"]:
            vanished += 1
            g = it["goneAt"]
            print(f"★ 撤回 : 最后一次见到 {l['_time']}，{g['_time']} 起 dumpsys 里不见了")
        else:
            print("存活   : 到抓取结束仍在通知栏")
    print("=" * 74)
    print(f"出现过又消失 = {vanished} 条；始终存在 = {len(order) - vanished} 条")
    if vanished:
        print("→ 结论：这些通知**被撤回**了 → catchUp 补抓在撤回之后捞不到（前提成立）")
    else:
        print("→ 结论：本次抓取窗口内**没有观察到撤回**（可能支付未发生，或轮询没赶上）")
        print("         不能据此否定前提 —— 换更短间隔重跑，或用 --poll-interval 0.3。")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", default=None)
    ap.add_argument("--seconds", type=int, default=300)
    ap.add_argument("--out", default=".workbuddy/qa-f716/lifecycle.jsonl")
    ap.add_argument("--pkg", default=",".join(DEFAULT_PKGS))
    ap.add_argument("--poll-interval", type=float, default=0.8)
    ap.add_argument("--summarize", default=None, help="只对已有文件做汇总，不连设备")
    args = ap.parse_args()

    if args.summarize:
        return summarize(Path(args.summarize))

    pkgs = {p.strip() for p in args.pkg.split(",") if p.strip()}
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    log_path = out_path.parent / "logcat.txt"

    watcher = LogcatWatcher(args.serial, log_path)
    watcher.start()
    print(f"[probe] 轮询 {args.seconds}s，过滤 {sorted(pkgs)} → {out_path}")
    print("[probe] **现在请在手机上做一笔真实支付，然后点进「支付成功」页，再回到桌面**")
    print(f"[probe] 起始状态：{read_app_state(args.serial)}", flush=True)

    seen: dict[str, dict] = {}
    poll = 0
    t0 = time.time()
    try:
        while time.time() - t0 < args.seconds:
            poll += 1
            text = _adb(args.serial, "shell", "dumpsys", "notification", "--noredact")
            now_ms = int(time.time() * 1000)
            now_t = time.strftime("%H:%M:%S")
            if text:
                tmp = out_path.parent / "_probe_dump.txt"
                tmp.write_text(text, encoding="utf-8")
                now_seen: set[str] = set()
                for rec in parse(str(tmp)):
                    if rec.get("pkg") not in pkgs or not is_payment_like(rec):
                        continue
                    fp = fingerprint(rec)
                    now_seen.add(fp)
                    rec.update({"_event": "seen", "_ms": now_ms, "_time": now_t, "_poll": poll, "fp": fp})
                    with out_path.open("a", encoding="utf-8") as fh:
                        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
                    if fp not in seen:
                        seen[fp] = rec
                        body = rec.get("android.text") or rec.get("android.title", "")
                        print(f"[{now_t}] ➕ 新通知 {rec.get('pkg')}: {body[:40]}", flush=True)
                # 检测「曾出现、这轮没了」
                for fp in list(seen.keys()):
                    if fp in now_seen:
                        seen[fp]["_last_ms"] = now_ms
                        seen[fp]["_last_time"] = now_t
                        seen[fp]["_last_poll"] = poll
                    elif not seen[fp].get("gone"):
                        seen[fp]["gone"] = True
                        gone_rec = {
                            "_event": "gone", "_ms": now_ms, "_time": now_t,
                            "_poll": poll, "fp": fp,
                            "last_seen": seen[fp].get("_last_time") or seen[fp]["_time"],
                        }
                        with out_path.open("a", encoding="utf-8") as fh:
                            fh.write(json.dumps(gone_rec, ensure_ascii=False) + "\n")
                        print(f"[{now_t}] ➖ 消失 {fp[:40]}…（最后见到 {gone_rec['last_seen']}）", flush=True)
            time.sleep(args.poll_interval)
    except KeyboardInterrupt:
        print("\n[probe] 收到 Ctrl-C，结束轮询")
    finally:
        watcher.stop_flag.set()
        time.sleep(0.5)
        watcher.dump()
        print(f"[probe] logcat → {log_path}")
        print(f"[probe] 结束状态：{read_app_state(args.serial)}")
        print("[probe] 汇总：")
        return summarize(out_path)


if __name__ == "__main__":
    raise SystemExit(main())
