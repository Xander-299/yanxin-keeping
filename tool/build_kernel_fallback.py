#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本机 Dart 管道故障下的 kernel 兜底编译（等价 `flutter assemble` 的 kernel_snapshot_program）。

## 为什么需要它

本机有主机级故障：**Dart 作为父进程 spawn 带管道 stdio 的子进程必败**
（`ProcessException: 所有的管道范例都在使用中 (CreateFile failed 231)`，`process_win.cc:744`）。
于是 `flutter build apk` / `gradlew assembleDebug` 里那条
`flutter_tools(dart) → frontend_server(dartaotruntime)` 的 spawn 必挂，APK 构建不出来。

**Python 不受影响**：它的 subprocess 走 `CreatePipe`（匿名管道），不是 Dart 的命名管道。
所以用 Python 当父进程去起**同一个 snapshot** 即可 —— 与
`dart-toolchain-python-fallback` skill 里 analyze / test 的做法同源。

## 它做什么

1. 用 Python 起 `frontend_server_aot.dart.snapshot` 生成 `app.dill`
   （参数照抄 flutter_tools `kernel_snapshot_program` 的日志原文）
2. 把 `app.dill` 复制成 `flutter_assets/kernel_blob.bin`
   （等价 flutter assemble 的 `copy_flutter_bundle`）
3. 打印 sha256 + 大小，供「新码确已进包」核验

之后由调用方跑 `gradlew assembleDebug -x compileFlutterBuildDebug`
（跳过那条必挂的 Dart 链，其余 Gradle 任务照常）。

用法：
    python tool/build_kernel_fallback.py            # 全量编译
    python tool/build_kernel_fallback.py --check    # 只核验产物新鲜度
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import time

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# frontend_server 的产物目录：flutter_tools 用「sdk-root + 参数」算 hash 当目录名。
# 这里不重算 hash（那是 flutter_tools 内部实现），而是**复用它已经建好的目录**——
# 上一次失败构建会留下 `.dart_tool/flutter_build/<hash>/`，名字直接取用。
FLUTTER_BUILD_DIR = os.path.join(PROJECT, ".dart_tool", "flutter_build")
PLUGIN_REGISTRANT = os.path.join(FLUTTER_BUILD_DIR, "dart_plugin_registrant.dart")
PACKAGE_CONFIG = os.path.join(PROJECT, ".dart_tool", "package_config.json")

FLUTTER_ASSETS = os.path.join(
    PROJECT, "build", "app", "intermediates", "flutter", "debug", "flutter_assets"
)


def find_flutter_root() -> str:
    """与 env.sh 同一套判据：看哪台机器的 SDK 目录存在。"""
    candidates = [
        r"D:\Download\Flutter\flutter",
        r"C:\src\flutter",
    ]
    for c in candidates:
        if os.path.isdir(os.path.join(c, "bin", "cache", "dart-sdk")):
            return c
    env = os.environ.get("FLUTTER_ROOT")
    if env and os.path.isdir(env):
        return env
    sys.exit("FATAL: 找不到 Flutter SDK（设 FLUTTER_ROOT 或改 find_flutter_root）")


def find_output_dir() -> str:
    """复用 flutter_tools 已建好的 <hash> 目录；没有就自己建一个。"""
    if os.path.isdir(FLUTTER_BUILD_DIR):
        subs = [
            d
            for d in os.listdir(FLUTTER_BUILD_DIR)
            if os.path.isdir(os.path.join(FLUTTER_BUILD_DIR, d)) and len(d) == 32
        ]
        if subs:
            return os.path.join(FLUTTER_BUILD_DIR, sorted(subs)[0])
    out = os.path.join(FLUTTER_BUILD_DIR, "python_fallback")
    os.makedirs(out, exist_ok=True)
    return out


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只核验产物，不重编")
    ap.add_argument("--timeout", type=int, default=900, help="编译超时秒数")
    args = ap.parse_args()

    root = find_flutter_root()
    dart_sdk = os.path.join(root, "bin", "cache", "dart-sdk", "bin")
    rt = os.path.join(dart_sdk, "dartaotruntime.exe")
    snap = os.path.join(
        dart_sdk, "snapshots", "frontend_server_aot.dart.snapshot"
    )
    sdk_root = os.path.join(
        root, "bin", "cache", "artifacts", "engine", "common", "flutter_patched_sdk"
    )

    out_dir = find_output_dir()
    dill = os.path.join(out_dir, "app.dill")
    depfile = os.path.join(out_dir, "kernel_snapshot_program.d")
    blob = os.path.join(FLUTTER_ASSETS, "kernel_blob.bin")

    for p in (rt, snap, sdk_root, PACKAGE_CONFIG, PLUGIN_REGISTRANT):
        if not os.path.exists(p):
            sys.exit("FATAL: 缺路径 %s" % p)

    if not args.check:
        # 参数逐字照抄构建日志里 kernel_snapshot_program 的命令行，
        # 只去掉 `--incremental --initialize-from-dill`（全量编译，不吃旧 dill）。
        cmd = [
            rt,
            snap,
            "--sdk-root",
            sdk_root + os.sep,
            "--target=flutter",
            "--no-print-incremental-dependencies",
            "-DFLUTTER_APP_FLAVOR=",
            "-Ddart.vm.profile=false",
            "-Ddart.vm.product=false",
            "--enable-asserts",
            "--track-widget-creation",
            "--no-link-platform",
            "--packages",
            PACKAGE_CONFIG,
            "--output-dill",
            dill,
            "--depfile",
            depfile,
            "--source",
            "file:///" + PLUGIN_REGISTRANT.replace("\\", "/"),
            "--source",
            "package:flutter/src/dart_plugin_registrant.dart",
            "-Dflutter.dart_plugin_registrant=file:///"
            + PLUGIN_REGISTRANT.replace("\\", "/"),
            "--verbosity=error",
            "package:yanxin/main.dart",
        ]
        print("[kernel] 起 frontend_server（Python 当父进程）…")
        t0 = time.time()
        try:
            proc = subprocess.run(
                cmd,
                cwd=PROJECT,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=args.timeout,
            )
        except subprocess.TimeoutExpired:
            sys.exit("FATAL: frontend_server 超时 %ds" % args.timeout)
        out = proc.stdout.decode("utf-8", "replace")
        print("[kernel] 退出码 %d，用时 %.1fs" % (proc.returncode, time.time() - t0))
        if out.strip():
            print("------ frontend_server 输出 ------")
            print(out[-4000:])
        if proc.returncode != 0:
            sys.exit("FATAL: kernel 编译失败")

        if not os.path.exists(dill) or os.path.getsize(dill) == 0:
            sys.exit("FATAL: app.dill 未生成或为空")

        # copy_flutter_bundle：app.dill → flutter_assets/kernel_blob.bin
        os.makedirs(FLUTTER_ASSETS, exist_ok=True)
        shutil.copyfile(dill, blob)
        print("[kernel] 已复制 → %s" % blob)

    for p in (dill, blob):
        if not os.path.exists(p):
            sys.exit("FATAL: 缺产物 %s" % p)
        print(
            "[check] %-70s %10d B  %s"
            % (os.path.relpath(p, PROJECT), os.path.getsize(p), sha256(p)[:16])
        )
    print("[check] OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
