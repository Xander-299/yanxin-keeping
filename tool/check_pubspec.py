"""pubspec.yaml / pubspec.lock 一致性体检（纯标准库，不依赖 pyyaml）。

本机 Dart 起不了管道子进程（`CreateFile failed 231`）→ `flutter pub get` 跑不了，
改完 pubspec 后没有办法让 pub 自己校验。这个脚本补上那个缺口。

检查项：
1. YAML 卫生：tab 字符、行尾空白、CRLF、末尾换行
2. `flutter_launcher_icons` **只能**在 dev_dependencies（构建期工具放 dependencies
   会被当运行时依赖，lock 里标成 `direct main`，且会打进发布包的依赖图）
3. pubspec.lock 里该包的 `dependency` 字段与 pubspec 声明位置一致
4. `flutter_launcher_icons:` 配置段引用的图片文件真实存在

用法：python tool/check_pubspec.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
LOCK = ROOT / "pubspec.lock"

# 只允许出现在 dev_dependencies 的包（构建期工具）
DEV_ONLY = {"flutter_launcher_icons", "build_runner", "drift_dev", "flutter_lints", "flutter_test"}


def parse_sections(text: str) -> dict[str, list[str]]:
    """把顶层段（缩进 0 的 `key:`）映射到它的**直接子项**名（缩进 2 的 `name:`）。"""
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if indent == 0:
            m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", stripped)
            current = m.group(1) if m else None
            if current:
                sections.setdefault(current, [])
            continue
        if indent == 2 and current:
            m = re.match(r"^([A-Za-z_][\w-]*):", stripped)
            if m:
                sections[current].append(m.group(1))
    return sections


def main() -> int:
    problems: list[str] = []
    notes: list[str] = []

    raw_bytes = PUBSPEC.read_bytes()
    text = raw_bytes.decode("utf-8")

    # 1) YAML 卫生
    if b"\r\n" in raw_bytes:
        problems.append("pubspec.yaml 含 CRLF（项目统一 LF）")
    if not text.endswith("\n"):
        problems.append("pubspec.yaml 末尾缺换行")
    for i, line in enumerate(text.splitlines(), 1):
        if "\t" in line:
            problems.append(f"pubspec.yaml 第 {i} 行含 tab（YAML 不允许）")
        if line != line.rstrip():
            problems.append(f"pubspec.yaml 第 {i} 行有行尾空白：{line!r}")

    sections = parse_sections(text)
    deps = set(sections.get("dependencies", []))
    dev = set(sections.get("dev_dependencies", []))
    print(f"dependencies      ({len(deps):>2})：{', '.join(sorted(deps))}")
    print(f"dev_dependencies  ({len(dev):>2})：{', '.join(sorted(dev))}")

    # 2) 构建期工具不得出现在 dependencies
    for pkg in sorted(DEV_ONLY):
        if pkg in deps:
            problems.append(f"`{pkg}` 是构建期工具，却被声明在 dependencies（应移到 dev_dependencies）")
    for pkg in sorted(DEV_ONLY & deps & dev):
        problems.append(f"`{pkg}` 在 dependencies 与 dev_dependencies 里**重复声明**")

    # 3) lock 的 dependency 字段与声明位置一致
    lock_text = LOCK.read_text(encoding="utf-8")
    for pkg in sorted(DEV_ONLY):
        m = re.search(
            rf"^  {re.escape(pkg)}:\n(?:.*\n)*?    dependency: \"([^\"]+)\"",
            lock_text,
            re.MULTILINE,
        )
        if not m:
            continue
        declared = m.group(1)
        if pkg in deps:
            expected = "direct main"
        elif pkg in dev:
            expected = "direct dev"
        else:
            expected = None
        if expected and declared != expected:
            problems.append(
                f"pubspec.lock 里 `{pkg}` 标为 `{declared}`，"
                f"但 pubspec 声明在 {'dependencies' if pkg in deps else 'dev_dependencies'}"
                f"（应为 `{expected}`）"
            )

    # 4) flutter_launcher_icons 配置段引用的图片要真存在
    cfg = re.search(r"^flutter_launcher_icons:\n((?:[ \t]+.*\n?)*)", text, re.MULTILINE)
    if not cfg:
        problems.append("pubspec.yaml 缺 `flutter_launcher_icons:` 配置段")
    else:
        for key in ("image_path", "adaptive_icon_foreground"):
            m = re.search(rf"^\s+{key}:\s*[\"']?([^\"'\n#]+)", cfg.group(1), re.MULTILINE)
            if not m:
                if key == "adaptive_icon_foreground":
                    notes.append(
                        "配置段未设 `adaptive_icon_foreground` → 不会生成 adaptive icon，"
                        "Android 8.0+ 会给图标套白底/白圈"
                    )
                continue
            rel = m.group(1).strip()
            if not (ROOT / rel).exists():
                problems.append(f"`{key}` 指向的文件不存在：{rel}")
            else:
                print(f"{key:<26}→ {rel}  ✅")

    print("\n=== 汇总 ===")
    for n in notes:
        print(f"  ℹ️ {n}")
    if problems:
        for p in problems:
            print(f"  ⚠️ {p}")
        return 1
    print("  全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
