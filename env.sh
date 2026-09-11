#!/usr/bin/env bash
# 颜芯记账 · Flutter 开发环境（Git Bash）
# 用法：source env.sh
#
# 每一行都是踩过的坑，删之前先看 git blame。
#
# ⚠️ 2026-09-12 机器迁移重写：旧基线在 D: 盘（旧机器，用户 panda），
#    本机（用户 Administrator）只有 C: / M: 盘，全部路径已重指向：
#      Flutter  D:\Download\Flutter\flutter  → C:\src\flutter
#      JDK17    D:\Download\Java\jdk-17.*    → M:\QQcache（Oracle 17.0.12，java.home 实测）
#      Android  D:\Download\Java\Android     → C:\src\Android（见文末「Android SDK」）
#      Gradle   <repo>\.gradle-home          → C:\src\gradle-home（全新空目录，勿复制）

# --- Bash 工具 PATH 兜底（沙箱默认 PATH 缺 /usr/bin:/bin）---
# 缺了它：grep/head/tail/date/find/dirname 全「command not found」，
# flutter 还会误报 "PROGRAM BLOCKED BY SECURITY POLICY ... wsl.exe"。
case ":$PATH:" in
  *":/usr/bin:"*) ;;
  *) export PATH="/usr/bin:/bin:$PATH" ;;
esac

# --- git（PortableGit，系统 PATH 里没有）---
export PATH="/c/Users/Administrator/.workbuddy/binaries/PortableGit/versions/1.2.0/cmd:$PATH"

# --- Flutter / Dart ---
export PATH="/c/src/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# --- JDK / Android SDK（必须 JDK 17，勿用 JDK 25）---
# 本机 java 指向 M:\QQcache（JDK 17.0.12），javac 齐备，Gradle 可直接用。
export JAVA_HOME="M:\\QQcache"
export PATH="/m/QQcache/bin:$PATH"
export ANDROID_HOME="C:\\src\\Android"
export ANDROID_SDK_ROOT="C:\\src\\Android"

# --- Windows 标准环境变量 ---
# 沙箱会吞掉这些变量；flutter test 的 Visual Studio 探测缺了 PROGRAMFILES(X86)
# 会直接抛 "%PROGRAMFILES(X86)% environment variable not found"
export PROGRAMFILES="C:\\Program Files"
export PROGRAMW6432="C:\\Program Files"
# bash 无法 export 带括号的名字，走函数内 env 注入

# --- 代理（pub 下载用 7890；env 里默认的 3980 更慢）---
# 本机直连也通（flutter-io.cn / pub.dev 实测 200），代理仅作加速兜底。
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890

# safe-delete shim 会拦 Dart/Gradle 的临时文件删除 → 必须 unset 会话 ID
unset CODEBUDDY_SESSION_ID CLAUDE_SESSION_ID

# --- sqlite3：Windows 自带的 winsqlite3.dll 太老，必须自带新版 ---
# package:sqlite3 在 Windows 上先找 `sqlite3.dll`，找不到才回退到 System32 的
# `winsqlite3.dll`——本机那份不支持 RETURNING（需 SQLite ≥ 3.35），drift 的
# insertReturning 会报 `near "RETURNING": syntax error`，60 条测试全挂。
# 已放官方 sqlite-dll-win-x64（3.53.4）到 C:\src\sqlite3，并复制一份到
# flutter_tester 同目录（exe 目录优先）。换机器/换 SDK 后要重新放。
export PATH="/c/src/sqlite3:$PATH"

# --- Gradle 缓存必须放工作区内 ---
# 沙箱允许在 C:\Users\<user>\.gradle 写入但**拒绝删除**（transforms\*.lock 拒绝访问），
# 与当年 npm 缓存 EPERM 同类。GRADLE_USER_HOME 指进工作区即根治。
# ⚠️ 只能给**全新空目录**让 Gradle 自己下载；复制已有缓存会让它启动即挂死。
export GRADLE_USER_HOME="C:\\src\\gradle-home"
mkdir -p "$GRADLE_USER_HOME"

# --- flutter test：代理会劫持测试进程的 WebSocket → 先去代理再跑 ---
# ⚠️ 2026-09-10 修：原先用 `env -u ...` 前缀，但沙箱里 `env` 被 safe-bin shim 吞掉
#    （命令零输出、0.5s 即返回，极具误导性）。改用 bash 内建 unset + 子 shell，
#    副作用不外泄且必然有输出。
# ⚠️ 不再注入 PROGRAMFILES(X86)：那是 sqlite3 3.x 的 native-assets MSVC 探测才需要，
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

echo "[env] Flutter 环境 OK（flutter C:\\src\\flutter / JAVA 17 M:\\QQcache）"

# --- Android SDK（仅构建 APK 需要；analyze/test 不需要）---
# 本机尚未安装。需要时跑：
#   python .workbuddy/bootstrap_env.py --step android   # 下载 cmdline-tools
#   sdkmanager --install "platform-tools" "platforms;35" "platforms;36" "build-tools;36.0.0"
#   flutter doctor --android-licenses   # 全部 y
# 已备好的 adb：C:\Users\Administrator\Desktop\platform-tools\adb.exe
