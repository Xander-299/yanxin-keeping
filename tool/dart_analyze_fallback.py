# -*- coding: utf-8 -*-
"""`flutter analyze` 的等效替代（本机 Dart 起不了子进程时用这个）。

## 为什么需要它

本机（A 机，2026-09-23 起）Dart VM 的 `Process::Start` 必然失败：
stdin 的命名管道客户端以 `GENERIC_READ` 打开时恒返回 `ERROR_PIPE_BUSY (231)`，
于是 `flutter analyze` / `dart analyze` / `flutter test` / `dart pub get` 全部崩。
Python 的 `subprocess` 走 `CreatePipe`（无名管道），**完全不受影响**。

`dart analyze` 的真实实现（`package:dartdev/src/commands/analyze.dart`）就是：
起 `dartaotruntime + analysis_server_aot.dart.snapshot` 子进程 → 通过 stdio 用
**Dart 原生协议**通信。本脚本用 Python 起**同一个 snapshot**、喂**同一套
`analysis_options.yaml`**，因此诊断口径（含全部 lint 规则）与 `dart analyze` 一致。

## 协议要点（三条都踩过坑，别改）

1. **帧格式 = 行分隔 JSON**：`stdin.writeln(json)` / 按行 `json.loads`。
   **不是** LSP 的 `Content-Length: N\\r\\n\\r\\n` 帧 —— 按帧解析会读到 0 条消息且不报错。
2. **`analysis.setAnalysisRoots.included` 必须是 OS 路径**，且**不能有尾斜杠**
   （有尾斜杠服务器报 `INVALID_FILE_PATH_FORMAT` 且不回任何响应 → 表现为「挂死」）。
   传 `file:///…` URI 同样无响应。
3. **完成信号 = `server.status` 通知里 `analysis.isAnalyzing` 由 true 变 false**。
   诊断本身通过 `analysis.errors` 通知推送，**干净文件也会推空数组**
   → 「收到 0 条」与「还没分析」不会混淆。

用法：
    python tool/dart_analyze_fallback.py                # 分析整个项目
    python tool/dart_analyze_fallback.py lib test       # 只分析这两个目录
    python tool/dart_analyze_fallback.py --verbose lib  # 打印进度

退出码：0 = No issues found；1 = 有 issue；2 = 服务器起不来。
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = os.path.join(PROJECT, ".dart_tool", "package_config.json")

SEV_LABEL = {"ERROR": "error", "WARNING": "warning", "INFO": "info"}

# ---------------------------------------------------------------- SDK 定位

SDK_CANDIDATES = [
    r"D:\Download\Flutter\flutter\bin\cache\dart-sdk",   # A 机
    r"C:\src\flutter\bin\cache\dart-sdk",                # B 机
]


def find_dart_sdk(explicit=None):
    """返回 dart-sdk 目录；找不到返回 None。"""
    snap_rel = os.path.join("bin", "snapshots", "analysis_server_aot.dart.snapshot")
    candidates = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("FX_DART_SDK"):
        candidates.append(os.environ["FX_DART_SDK"])
    which = shutil.which("dart")
    if which:
        # <sdk>/bin/dart[.bat] → <sdk>
        candidates.append(os.path.dirname(os.path.dirname(which)))
    candidates.extend(SDK_CANDIDATES)
    for candidate in candidates:
        if candidate and os.path.exists(os.path.join(candidate, snap_rel)):
            return candidate
    return None


def os_canonical(path):
    """绝对 + 解析符号链接 + 去尾分隔符（等价 dartdev 的 trimEnd）。"""
    resolved = os.path.realpath(os.path.abspath(path))
    while resolved.endswith(os.sep) and len(resolved) > 3:
        resolved = resolved[:-1]
    return resolved


# ---------------------------------------------------------------- 服务器


class AnalysisServer:
    def __init__(self, sdk_root, cache_dir):
        sdk_bin = os.path.join(sdk_root, "bin")
        self.cmd = [
            os.path.join(sdk_bin, "dartaotruntime.exe"),
            os.path.join(sdk_bin, "snapshots", "analysis_server_aot.dart.snapshot"),
            "--client-id=dart-analyze",
            "--disable-server-feature-completion",
            "--disable-server-feature-search",
            "--disable-status-notification-debouncing",
            "--disable-silent-analysis-exceptions",
            "--dart-sdk", sdk_root,
            "--cache=" + cache_dir,
            "--packages=" + PACKAGES,
            "--no-plugins",
        ]
        self.proc = subprocess.Popen(
            self.cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, cwd=PROJECT,
        )
        self._id = 0
        self._lock = threading.Lock()
        self._events = []
        self.stderr_lines = []
        self.connected = threading.Event()
        self.dead = threading.Event()
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_stdout(self):
        for line in iter(self.proc.stdout.readline, b""):
            text = line.decode("utf-8", "replace").strip()
            if not text:
                continue
            try:
                msg = json.loads(text)
            except ValueError:
                self.stderr_lines.append("[bad-json] " + text[:200])
                continue
            if not isinstance(msg, dict):
                continue
            with self._lock:
                self._events.append(msg)
            if msg.get("event") == "server.connected":
                self.connected.set()
        self.dead.set()

    def _read_stderr(self):
        for line in iter(self.proc.stderr.readline, b""):
            self.stderr_lines.append(
                "[stderr] " + line.decode("utf-8", "replace").rstrip()[:300])

    def send(self, method, params=None):
        self._id += 1
        msg = {"id": str(self._id), "method": method}
        if params is not None:
            msg["params"] = params
        self.proc.stdin.write(json.dumps(msg).encode("utf-8") + b"\n")
        self.proc.stdin.flush()

    def drain(self):
        with self._lock:
            out, self._events = self._events, []
        return out

    def kill(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        self.proc.kill()


# ---------------------------------------------------------------- 主流程


def run(sdk_root, roots, cache_dir, quiet_after_finish=2.0, timeout=1800, verbose=False):
    """跑一次分析，返回 {file: [error dict]}。"""
    server = AnalysisServer(sdk_root, cache_dir)
    if not server.connected.wait(60):
        server.kill()
        raise RuntimeError("analysis server 未在 60s 内发出 server.connected")

    server.send("server.setSubscriptions", {"subscriptions": ["STATUS"]})
    server.send("analysis.setAnalysisRoots",
                {"included": [os_canonical(r) for r in roots], "excluded": []})

    file_errors = {}
    saw_analyzing = False
    finished_at = None
    last_push = time.time()
    deadline = time.time() + timeout
    started = time.time()

    while time.time() < deadline:
        for msg in server.drain():
            event = msg.get("event")
            params = msg.get("params") or {}
            if event == "server.status":
                is_analyzing = (params.get("analysis") or {}).get("isAnalyzing")
                if is_analyzing is True:
                    saw_analyzing = True
                elif is_analyzing is False and saw_analyzing and finished_at is None:
                    finished_at = time.time()
                    if verbose:
                        print("[info] analysis finished after %.0fs"
                              % (finished_at - started), file=sys.stderr)
            elif event == "analysis.errors":
                path = params.get("file")
                if path:
                    file_errors[path] = params.get("errors") or []
                    last_push = time.time()
            elif event in ("server.error", "server.pluginError"):
                print("[warn] %s: %s" % (event, json.dumps(params)[:300]),
                      file=sys.stderr)
        if finished_at is not None and time.time() - last_push >= quiet_after_finish:
            break
        if server.dead.is_set():
            raise RuntimeError("analysis server 提前退出")
        time.sleep(0.05)

    if finished_at is None:
        raise RuntimeError("未收到 isAnalyzing true→false，分析未完成")
    server.kill()
    return file_errors


def main():
    parser = argparse.ArgumentParser(
        description="flutter analyze 的等效替代（Python 托管 Dart 分析服务器）")
    parser.add_argument("paths", nargs="*", default=None,
                        help="要分析的目录/文件（默认整个项目）")
    parser.add_argument("--sdk", help="显式指定 dart-sdk 目录")
    parser.add_argument("--cache", help="分析服务器缓存目录（默认 .dart_tool/fx_analyze_cache）")
    parser.add_argument("--verbose", action="store_true", help="打印进度")
    args = parser.parse_args()

    sdk_root = find_dart_sdk(args.sdk)
    if not sdk_root:
        print("FATAL: 找不到 dart-sdk（可用 --sdk 指定）", file=sys.stderr)
        return 2
    roots = args.paths or [PROJECT]
    cache_dir = args.cache or os.path.join(PROJECT, ".dart_tool", "fx_analyze_cache")
    os.makedirs(cache_dir, exist_ok=True)

    try:
        file_errors = run(sdk_root, roots, cache_dir, verbose=args.verbose)
    except RuntimeError as exc:
        print("FATAL: %s" % exc, file=sys.stderr)
        return 2

    # 排序 + 输出（模仿 dart analyze 的 default 格式）
    rows = []
    for path, errors in sorted(file_errors.items()):
        for error in errors:
            location = error.get("location") or {}
            rows.append((
                {"error": 0, "warning": 1, "info": 2}.get(
                    SEV_LABEL.get(error.get("severity"), "info"), 3),
                path,
                location.get("offset") or 0,
                error,
                location,
            ))
    rows.sort(key=lambda row: (row[0], row[1], row[2]))

    counts = {"error": 0, "warning": 0, "info": 0}
    for _rank, path, _offset, error, location in rows:
        severity = SEV_LABEL.get(error.get("severity"), "info")
        counts[severity] = counts.get(severity, 0) + 1
        rel = os.path.relpath(path, PROJECT).replace("\\", "/")
        message = (error.get("message") or "").replace("\n", " ")
        correction = error.get("correction")
        if correction:
            message += " " + correction
        print("  %-7s • %s:%s:%s • %s • %s" % (
            severity, rel, location.get("startLine"), location.get("startColumn"),
            message, error.get("code", "?")))

    total = sum(counts.values())
    if total == 0:
        print("No issues found!")
    else:
        print("%d %s found." % (total, "issue" if total == 1 else "issues"))
        print("(%d error, %d warning, %d info)" % (
            counts["error"], counts["warning"], counts["info"]))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
