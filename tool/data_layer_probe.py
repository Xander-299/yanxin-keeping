"""在不依赖 Flutter 的纯 Dart VM 里跑数据层的「首次使用」验收探针。

背景（见 HANDOFF.md「未解决问题」第 1 条）：本机 Dart VM 起不了「需要管道
stdio」的子进程（命名管道 `CreateFile failed 231`）→ `flutter test` 不可用。
但 `lib` 的数据层（drift 仓储 + 报表聚合）不依赖 `package:flutter`；唯一把
`dart:ui` 拖进来的是 `lib/core/db/database.dart` 里的 drift_flutter
（→ path_provider → flutter）。

做法：复制一份 `lib/` 到 `.dart_tool/data_layer_probe/` 下的临时包 →
把该文件的 drift_flutter 换成 `drift/native` 的内存库 → 跑 `data_layer_probe.dart`。
临时包整个落在 `.dart_tool/`（已在 .gitignore 里），不碰工作区、不碰任何真实数据。

用法：
    python tool/data_layer_probe.py            # 用 PATH 上的 dart
    python tool/data_layer_probe.py --dart <path-to-dart.exe>
    python tool/data_layer_probe.py --keep     # 保留临时包便于排查
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / ".dart_tool" / "data_layer_probe"

OLD_IMPORT = "import 'package:drift_flutter/drift_flutter.dart';"
NEW_IMPORT = "import 'package:drift/native.dart';"
OLD_FACTORY = "AppDatabase openAppDatabase() => AppDatabase(driftDatabase(name: 'yanxin'));"
NEW_FACTORY = "AppDatabase openAppDatabase() => AppDatabase(NativeDatabase.memory());"


def patch_database(path: Path) -> None:
    src = path.read_text(encoding="utf-8")
    for old, new in ((OLD_IMPORT, NEW_IMPORT), (OLD_FACTORY, NEW_FACTORY)):
        if old not in src:
            sys.exit(f"[probe] 补丁锚点没找到，database.dart 可能已改动：{old}")
        src = src.replace(old, new)
    path.write_text(src, encoding="utf-8", newline="\n")


def build_package() -> Path:
    if WORK.exists():
        shutil.rmtree(WORK)
    shutil.copytree(ROOT / "lib", WORK / "lib")
    (WORK / ".dart_tool").mkdir(parents=True)
    shutil.copy2(ROOT / ".dart_tool" / "package_config.json",
                 WORK / ".dart_tool" / "package_config.json")
    shutil.copy2(ROOT / "tool" / "data_layer_probe.dart", WORK / "data_layer_probe.dart")
    patch_database(WORK / "lib" / "core" / "db" / "database.dart")

    # 包配置里 yanxin 的 rootUri 是相对 `.dart_tool` 的 `../` → 正好指向临时包，
    # 其余依赖仍是 pub cache 的绝对路径，所以无需改任何一条。
    cfg = json.loads((WORK / ".dart_tool" / "package_config.json").read_text(encoding="utf-8"))
    yanxin = next(p for p in cfg["packages"] if p["name"] == "yanxin")
    if yanxin["rootUri"] != "../":
        sys.exit(f"[probe] yanxin.rootUri 不再是 '../'（{yanxin['rootUri']}），需改脚本")
    return WORK / "data_layer_probe.dart"


def resolve_dart(explicit: str | None) -> str:
    """定位真正的 dart 可执行文件。

    PATH 上的 `dart` 在 Flutter 安装里是 `dart.bat`，Python 的 CreateProcess
    起不了 .bat（WinError 2）→ 从它旁边的 `cache/dart-sdk/bin/dart.exe` 取。
    """
    for cand in (explicit, os.environ.get("DART"), shutil.which("dart.exe"),
                 shutil.which("dart")):
        if not cand:
            continue
        p = Path(cand)
        if p.suffix.lower() == ".exe" and p.is_file():
            return str(p)
        if p.suffix.lower() in (".bat", ".cmd"):
            # flutter/bin/dart.bat → flutter/bin/cache/dart-sdk/bin/dart.exe
            for base in (p.parent, p.parent.parent):
                exe = base / "cache" / "dart-sdk" / "bin" / "dart.exe"
                if exe.is_file():
                    return str(exe)
    sys.exit("[probe] 找不到 dart.exe —— 用 --dart <path-to-dart.exe> 指定")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dart", default=None,
                    help="dart.exe 路径（默认自动定位 Flutter 的 dart-sdk）")
    ap.add_argument("--keep", action="store_true", help="保留临时包")
    args = ap.parse_args()

    dart = resolve_dart(args.dart)
    entry = build_package()
    print(f"[probe] dart：{dart}")
    print(f"[probe] 临时包：{WORK}")
    proc = subprocess.run([dart, str(entry)], cwd=str(ROOT),
                          text=True, encoding="utf-8", errors="replace")
    if not args.keep:
        shutil.rmtree(WORK, ignore_errors=True)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
