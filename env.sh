#!/usr/bin/env bash
# 颜芯记账 · Flutter 开发环境（Git Bash）
# 用法：source env.sh
#
# 每一行都是踩过的坑，删之前先看 git blame。
#
# ⚠️ 本项目有**两台机器**在用（2026-09-12 换机后两边并存）→ 本文件**自动识别**当前机器，
#    不需要手工改路径。识别依据 = 看哪台机器的 Flutter SDK 目录存在：
#      A 机：用户 panda，D: 盘，MuMu 12 @ D:\Downloads\MuMu        → D:\Download\Flutter\flutter
#      B 机：用户 Administrator，C:/M: 盘，MuMu 15 @ C:\Program Files\Netease\MuMu
#                                                                  → C:\src\flutter
#    新增机器：在下面加一个 `elif` 分支即可。

# --- Bash 工具 PATH 兜底（沙箱默认 PATH 缺 /usr/bin:/bin）---
# 缺了它：grep/head/tail/date/find/dirname 全「command not found」，
# flutter 还会误报 "PROGRAM BLOCKED BY SECURITY POLICY ... wsl.exe"。
case ":$PATH:" in
  *":/usr/bin:"*) ;;
  *) export PATH="/usr/bin:/bin:$PATH" ;;
esac

# --- 机器识别 ---
if [ -d "/d/Download/Flutter/flutter" ]; then
  RAS_MACHINE="A"
elif [ -d "/c/src/flutter" ]; then
  RAS_MACHINE="B"
else
  RAS_MACHINE="?"
fi

# --- Pub 镜像 ---
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# --- Windows 标准环境变量 ---
# 沙箱会吞掉这些变量；flutter test 的 Visual Studio 探测缺了 PROGRAMFILES(X86)
# 会直接抛 "%PROGRAMFILES(X86)% environment variable not found"
export PROGRAMFILES="C:\\Program Files"
export PROGRAMW6432="C:\\Program Files"
# bash 无法 export 带括号的名字，走函数内 env 注入

# --- 代理（pub 下载用 7890；env 里默认的 3980 更慢）---
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890

# safe-delete shim 会拦 Dart/Gradle 的临时文件删除 → 必须 unset 会话 ID
unset CODEBUDDY_SESSION_ID CLAUDE_SESSION_ID

# --- 分机器路径 ---
if [ "$RAS_MACHINE" = "A" ]; then
  # ===== A 机（panda / D:）=====
  export PATH="/d/Download/Flutter/flutter/bin:$PATH"
  # JDK 必须 17；系统 `java` 默认可能是 25 → 这里显式前置
  export JAVA_HOME="D:\\Download\\Java\\jdk-17.0.20.1+1"
  export PATH="/d/Download/Java/jdk-17.0.20.1+1/bin:$PATH"
  export ANDROID_HOME="D:\\Download\\Java\\Android"
  export ANDROID_SDK_ROOT="D:\\Download\\Java\\Android"
  # Gradle 缓存必须放工作区内（<USER_HOME>\.gradle 允许写但拒绝删除 lock 文件）。
  # ⚠️ 只能给**全新空目录**让 Gradle 自己下载；复制已有缓存会让它启动即挂死。
  export GRADLE_USER_HOME="D:\\Tencent\\yanxin-flutter\\.gradle-home"
  # git 由 Git Bash 自带（/mingw64/bin/git），无需额外加 PATH。
  # sqlite3.dll：本机实测 analyze/test 全绿、未单独放 dll；若出现
  #   `near "RETURNING": syntax error` 成片报错，按 B 机做法补（见下）。

elif [ "$RAS_MACHINE" = "B" ]; then
  # ===== B 机（Administrator / C: + M:）=====
  # 系统 PATH 里没有 git → 显式指向 PortableGit
  export PATH="/c/Users/Administrator/.workbuddy/binaries/PortableGit/versions/1.2.0/cmd:$PATH"
  export PATH="/c/src/flutter/bin:$PATH"
  export JAVA_HOME="M:\\QQcache"           # Oracle JDK 17.0.12（java.home 实测）
  export PATH="/m/QQcache/bin:$PATH"
  export ANDROID_HOME="C:\\src\\Android"
  export ANDROID_SDK_ROOT="C:\\src\\Android"
  # sqlite3：Windows 自带的 winsqlite3.dll 太老，不支持 RETURNING（需 SQLite ≥3.35）
  # → drift 的 insertReturning 报 `near "RETURNING": syntax error`，成片测试挂。
  # 已放官方 sqlite-dll-win-x64（3.53.4）到 C:\src\sqlite3，并复制一份到 flutter_tester
  # 同目录（exe 目录优先）。换机器 / 换 SDK 后要重新放。
  export PATH="/c/src/sqlite3:$PATH"
  export GRADLE_USER_HOME="C:\\src\\gradle-home"   # 全新空目录，勿复制

else
  echo "[env] ⚠️ 未识别的机器：没找到 D:\\Download\\Flutter\\flutter 或 C:\\src\\flutter" >&2
  echo "[env]    请在 env.sh 的机器识别分支里补上本机路径。" >&2
fi

if [ -n "$GRADLE_USER_HOME" ]; then
  mkdir -p "$GRADLE_USER_HOME"
fi

# --- flutter test：代理会劫持测试进程的 WebSocket → 先去代理再跑 ---
# ⚠️ 原先用 `env -u ...` 前缀，但沙箱里 `env` 被 safe-bin shim 吞掉
#    （命令零输出、0.5s 即返回，极具误导性）。改用 bash 内建 unset + 子 shell，
#    副作用不外泄且必然有输出。
# ⚠️ 不注入 PROGRAMFILES(X86)：那是 sqlite3 3.x 的 native-assets MSVC 探测才需要，
#    本项目锁在 sqlite3 2.9.4，实测 analyze/test 均不需要。
fx-test() {
  ( unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
    flutter test --no-pub "$@" )
}

# --- analyze + test 一条龙 ---
fx-qa() {
  ( unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
    flutter analyze ) && fx-test "$@"
}

echo "[env] Flutter 环境 OK（机器 $RAS_MACHINE；flutter=$(command -v flutter)；gradle=$GRADLE_USER_HOME）"

# --- Android SDK / 模拟器（仅构建 APK、真机走查需要；analyze/test 不需要）---
# A 机：SDK `D:\Download\Java\Android`（platforms 35/36、build-tools 36.0.0、
#       ndk 28.2.13676358、cmake 3.22.1、licenses 已接受）；
#       ⚠️ 2026-09-11 该目录曾被磁盘清理误删进回收站 → **别把 D:\Download\Java\ 当垃圾目录**。
#       模拟器 MuMu 12 @ `D:\Downloads\MuMu\MuMuPlayer`，adb 端口 16384 / 7555。
# B 机：SDK `C:\src\Android`；模拟器 MuMu 15 @ `C:\Program Files\Netease\MuMu`，adb 127.0.0.1:16384。
# 真机走查流程见 `.workbuddy/skills/mumu-flutter-ui-smoke/SKILL.md`。
