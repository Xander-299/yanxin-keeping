# -*- coding: utf-8 -*-
"""`flutter test` 的等效替代（本机 Dart 起不了子进程时用这个）。

## 为什么能这么干

`flutter test` 本体 = flutter_tools 起两个**原生子进程**：
  1. `dartaotruntime + frontend_server_aot.dart.snapshot` 编译测试文件为 dill
  2. `flutter_tester.exe <dill>` 执行这个 dill

Dart 的 `Process::Start` 在本机必失败（stdin 命名管道客户端 `GENERIC_READ`
打开恒返回 `ERROR_PIPE_BUSY (231)`），但 **Python 的 subprocess 走无名管道、
完全不受影响** → 用 Python 直接起这两个原生进程，就能复刻 `flutter test`。

## 与 flutter_tools 的对应关系（别自己发明，抄它）

- 编译参数抄 `flutter_tools/lib/src/compile.dart`（`--sdk-root <patched_sdk>`
  / `--target=flutter` / `--track-widget-creation` / `--packages`）。
- 引导文件抄 `flutter_tools/lib/src/test/flutter_platform.dart:143
  generateTestBootstrap`：先生成 `listener.dart`，内容是
  `import '<测试文件的 file:// URI>' as test;` + `void main() { await Future(test.main); }`。
  （真身的 main 还会连 websocket 拉 test 结果；实测**不连也能跑**：
  flutter_test/package:test_api 在无远程监听器时自己跑完并打印 `+N: ...` 进度。）
- tester 参数抄 `flutter_tools/lib/src/test/flutter_tester_device.dart`：
  `--disable-vm-service --icu-data-file-path=<engine>/icudtl.dat --enable-checked-mode
   --verify-entry-points --enable-software-rendering --skia-deterministic-rendering
   --non-interactive --use-test-fonts --disable-asset-fonts --packages=<...>`。
  环境变量 `FLUTTER_TEST=true`（flutter_test 靠它判断自己跑在测试里）。

## 能力边界（必读）

- ✅ **纯 `test()` 用例**（含真实 drift / SQL 异步）：与 `flutter test` 等价。实测本项目
  35 个文件里 214 例全绿。
- ❌ **`testWidgets` 用例跑不了**：`AutomatedTestWidgetsFlutterBinding` 需要真正的 test
  运行器驱动帧，只给一个 bootstrap 时它会「启动首例后**永不完成**」（计数停在 0、rc 仍为 0）。
  含 widget 的文件因此报「未跑完」而**不会假绿**（终态汇总行 `All tests passed!` 是硬门槛）。
  这类文件仍需在能跑 `flutter test` 的环境验证。

用法：
    python tool/dart_test_fallback.py                      # 跑 test/ 下所有 *_test.dart
    python tool/dart_test_fallback.py test/features/reports # 只跑这些文件/目录
    python tool/dart_test_fallback.py --raw --timeout 90 x  # 逐字看原始输出 / 缩短超时
    python tool/dart_test_fallback.py --keep                # 保留 dill 便于排查

退出码：0 = 全绿；1 = 有用例失败或文件未跑完；2 = 环境/编译问题。
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import time

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = os.path.join(PROJECT, ".dart_tool", "package_config.json")
WORK = os.path.join(PROJECT, ".dart_tool", "dart_test_fallback")

FLUTTER_CANDIDATES = [
    r"D:\Download\Flutter\flutter",  # A 机
    r"C:\src\flutter",               # B 机
]

# 进度行：`00:12 +7 ~2 -1: 组名 用例名`
# ⚠️ 两个坑：① package:test 的顺序是 `+通过 ~跳过 -失败`（不是 + - ~），且只打印非零项；
#   ② 时间戳自带冒号，必须先剥掉 `mm:ss ` 再按冒号切。
PROGRESS = re.compile(r"^\d\d:\d\d ")
STAMP = re.compile(r"^\d\d:\d\d (.*)$")
COUNTER = re.compile(r"([+~-])(\d+)")
# 终态汇总行 —— **只有出现它才算跑完**。
# ⚠️ 千万别只看计数：`testWidgets` 在「无 test 运行器」的封装下会**启动首例后永不完成**
# （AutomatedTestWidgetsFlutterBinding 需要真运行器驱动），此时输出只有
# `00:00 +0: <用例名>`、计数全是 0、而进程 rc=0 —— 极易被误判成「全绿」。
DONE = re.compile(r"All tests passed!|Some tests failed\.|All tests skipped\.|No tests ran\.")


def find_flutter_root(explicit=None):
    """返回 flutter 根目录；找不到返回 None。"""
    candidates = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("FX_FLUTTER_ROOT"):
        candidates.append(os.environ["FX_FLUTTER_ROOT"])
    candidates.extend(FLUTTER_CANDIDATES)
    for root in candidates:
        if root and os.path.exists(os.path.join(
                root, "bin", "cache", "artifacts", "engine", "windows-x64",
                "flutter_tester.exe")):
            return root
    return None


def sdk_paths(root):
    return {
        "runtime": os.path.join(root, "bin", "cache", "dart-sdk", "bin",
                                "dartaotruntime.exe"),
        "frontend": os.path.join(root, "bin", "cache", "dart-sdk", "bin",
                                 "snapshots", "frontend_server_aot.dart.snapshot"),
        "sdk_root": os.path.join(root, "bin", "cache", "artifacts", "engine",
                                 "common", "flutter_patched_sdk"),
        "tester": os.path.join(root, "bin", "cache", "artifacts", "engine",
                               "windows-x64", "flutter_tester.exe"),
        "icu": os.path.join(root, "bin", "cache", "artifacts", "engine",
                            "windows-x64", "icudtl.dat"),
    }


def file_uri(path):
    return "file:///" + os.path.abspath(path).replace("\\", "/")


def make_bootstrap(test_path, index):
    """等价于 flutter_tools 生成的 listener.dart（去掉 websocket 部分）。"""
    os.makedirs(WORK, exist_ok=True)
    bootstrap = os.path.join(WORK, "listener_%03d.dart" % index)
    with open(bootstrap, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            "// 自动生成（tool/dart_test_fallback.py），勿手工编辑。\n"
            "import 'dart:async';\n\n"
            "import '%s' as test;\n\n"
            "Future<void> _testMain() async {\n"
            "  await Future(test.main);\n"
            "}\n\n"
            "void main() => _testMain();\n" % file_uri(test_path))
    return bootstrap


def compile_dill(paths, entry, out_dill):
    cmd = [
        paths["runtime"], paths["frontend"],
        "--sdk-root", paths["sdk_root"],
        "--target=flutter",
        "--no-print-incremental-dependencies",
        "--track-widget-creation",
        "--packages", PACKAGES,
        "--output-dill", out_dill,
        "--verbosity=error",
        entry,
    ]
    proc = subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=1800)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def run_suite(paths, dill, timeout):
    cmd = [
        paths["tester"],
        "--disable-vm-service",
        "--icu-data-file-path=" + paths["icu"],
        "--enable-checked-mode",
        "--verify-entry-points",
        "--enable-software-rendering",
        "--skia-deterministic-rendering",
        "--non-interactive",
        "--use-test-fonts",
        "--disable-asset-fonts",
        "--packages=" + PACKAGES,
        dill,
    ]
    env = dict(os.environ)
    env["FLUTTER_TEST"] = "true"
    env["APP_NAME"] = "yanxin"
    try:
        proc = subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as expired:
        # ⚠️ 超时也要保留已捕获的输出 —— 否则看不到「卡在哪一例」。
        return (124,
                (expired.stdout or b"").decode("utf-8", "replace")
                if isinstance(expired.stdout, bytes) else (expired.stdout or ""),
                "TIMEOUT after %ss" % timeout)
    return proc.returncode, (proc.stdout or ""), (proc.stderr or "")


def last_counts(text):
    """取最后一条进度行的 (passed, failed, skipped)；没有则 None。

    进度行形如 `00:12 +7 ~2 -1: 组名 用例名`，计数器顺序为 `+ ~ -`，
    且只打印非零项，所以要按前缀逐个匹配而不是位置匹配。
    """
    last = None
    for line in text.splitlines():
        stripped = line.strip()
        stamp = STAMP.match(stripped)
        if not stamp:
            continue
        head = stamp.group(1).split(":", 1)[0]
        found = {"+": 0, "~": 0, "-": 0}
        for sign, value in COUNTER.findall(head):
            found[sign] = int(value)
        last = (found["+"], found["-"], found["~"])
    return last


def collect_tests(paths):
    files = []
    for raw in paths:
        target = os.path.join(PROJECT, raw) if not os.path.isabs(raw) else raw
        if os.path.isdir(target):
            files.extend(glob.glob(os.path.join(target, "**", "*_test.dart"),
                                   recursive=True))
        elif os.path.isfile(target):
            files.append(target)
        else:
            print("  [warn] 路径不存在：%s" % raw, file=sys.stderr)
    return sorted(set(files))


def main():
    parser = argparse.ArgumentParser(
        description="flutter test 的等效替代（Python 托管 flutter_tester）")
    parser.add_argument("paths", nargs="*", default=None,
                        help="要跑的测试文件/目录（默认 test/ 全量）")
    parser.add_argument("--flutter-root", help="显式指定 flutter 根目录")
    parser.add_argument("--timeout", type=int, default=600,
                        help="单个测试文件的超时秒数（默认 600）")
    parser.add_argument("--keep", action="store_true", help="保留 dill 与引导文件")
    parser.add_argument("--verbose", action="store_true", help="打印每个文件的完整输出")
    parser.add_argument("--raw", action="store_true", help="逐字打印 tester 的原始 stdout/stderr")
    args = parser.parse_args()

    root = find_flutter_root(args.flutter_root)
    if not root:
        print("FATAL: 找不到 flutter（可用 --flutter-root 指定）", file=sys.stderr)
        return 2
    paths = sdk_paths(root)
    tests = collect_tests(args.paths or ["test"])
    if not tests:
        print("FATAL: 没找到 *_test.dart", file=sys.stderr)
        return 2

    # 注意：**不要**整目录 rmtree —— 本机 safe-delete shim 对「单轮 >50 个文件」的批量删除
    # 一律 fail-closed（`SAFE_DELETE_BULK_CONFIRM_REQUIRED`）。引导文件按固定编号覆盖写，
    # 数量恒等于测试文件数；每次只删本文件的 dill（单轮 <50，可行）。
    os.makedirs(WORK, exist_ok=True)

    print("flutter_test → %s" % root)
    print("测试文件 %d 个\n" % len(tests))

    total_passed = total_failed = total_skipped = 0
    bad = []
    started = time.time()
    for index, test in enumerate(tests, 1):
        rel = os.path.relpath(test, PROJECT).replace("\\", "/")
        bootstrap = make_bootstrap(test, index)
        dill = bootstrap[:-5] + ".dill"
        mark = time.time()
        code, log = compile_dill(paths, bootstrap, dill)
        if code != 0 or not os.path.exists(dill):
            bad.append((rel, "compile", log.strip()[:800]))
            print("[%2d/%2d] %-58s 编译失败" % (index, len(tests), rel))
            if args.verbose:
                print(log[:2000])
            continue
        try:
            _code, out, err = run_suite(paths, dill, args.timeout)
        finally:
            if not args.keep:
                try:
                    os.remove(dill)
                except OSError:
                    pass
        counts = last_counts(out + "\n" + err)
        finished = bool(DONE.search(out + "\n" + err))
        if args.raw:
            print("------ tester stdout ------")
            print(out)
            print("------ tester stderr ------")
            print(err)
        if counts is None or not finished:
            bad.append((rel, "未跑完", (out + err).strip()[:800]
                        or "没有任何输出（既没跑完也没报错）"))
            print("[%2d/%2d] %-58s 未跑完（无终态汇总行：testWidgets 需真运行器）"
                  % (index, len(tests), rel))
            if args.verbose:
                print((out + err)[:2000])
            continue
        passed, failed, skipped = counts
        total_passed += passed
        total_failed += failed
        total_skipped += skipped
        flag = "OK" if failed == 0 else "FAIL"
        print("[%2d/%2d] %-58s +%d-%d~%d  %5.1fs  %s"
              % (index, len(tests), rel, passed, failed, skipped,
                 time.time() - mark, flag))
        if failed or args.verbose:
            for line in out.splitlines():
                if PROGRESS.match(line.strip()):
                    continue
                if line.strip():
                    print("      " + line[:200])

    print("\n---- 汇总 ----")
    print("passed=%d failed=%d skipped=%d 用时 %.0fs"
          % (total_passed, total_failed, total_skipped, time.time() - started))
    if bad:
        print("有下列文件未能跑完：")
        for rel, kind, detail in bad:
            print("  %-58s %s" % (rel, kind))
            print("      " + detail.replace("\n", "\n      ")[:600])
    if total_failed == 0 and not bad:
        print("All tests passed!")
    return 0 if (total_failed == 0 and not bad) else 1


if __name__ == "__main__":
    sys.exit(main())
