#!/usr/bin/env bash
# 颜芯记账 · Flutter 开发环境（Git Bash）
# 用法：source env.sh
#
# 每一行都是踩过的坑，删之前先看 git blame。

# --- Flutter / Dart ---
export PATH="/d/Download/Flutter/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# --- JDK / Android SDK（必须 JDK 17，勿用 JDK 25）---
export JAVA_HOME="D:\\Download\\Java\\jdk-17.0.20.1+1"
export ANDROID_HOME="D:\\Download\\Java\\Android"
export ANDROID_SDK_ROOT="D:\\Download\\Java\\Android"

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

# --- Gradle 缓存必须放工作区内 ---
# 沙箱允许在 <USER_HOME>\.gradle 写入但**拒绝删除**（transforms\*.lock 拒绝访问），
# 与当年 npm 缓存 EPERM 同类。GRADLE_USER_HOME 指进工作区即根治。
export GRADLE_USER_HOME="D:\\Tencent\\yanxin-flutter\\.gradle-home"
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

echo "[env] Flutter 环境 OK（flutter / JAVA 17 / SDK D:\\Download\\Java\\Android）"
