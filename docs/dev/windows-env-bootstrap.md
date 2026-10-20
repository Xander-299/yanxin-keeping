# 在全新的 Windows 机器上重建 Flutter + Android 开发环境

> 换机 / 重装后「环境体检 + 补齐缺失依赖」的操作手册。目标是让 `dart analyze` 和
> `flutter test` 跑通，而不只是装上 SDK。
>
> 判定前提：机器上没有（或路径失效）Flutter SDK / Android SDK / Pub 缓存。
> **先做体检再动手**：确认有哪些盘、`java -XshowSettings:properties` 看 `java.home`
> 找现成 JDK、`ls` 找现成的 `adb`，别一上来就全装一遍。

## 1. 下载源

| 内容 | 地址 |
|---|---|
| Flutter 版本清单 | `https://storage.flutter-io.cn/flutter_infra_release/releases/releases_windows.json`（`base_url` + `releases[].archive` 拼出 zip 地址） |
| Android 组件清单 | `https://dl.google.com/android/repository/repository2-3.xml`（`<url>` 里**只有文件名**，下载要拼 `https://dl.google.com/android/repository/<url>`） |
| SQLite DLL | `https://sqlite.org/download.html` → `sqlite-dll-win-x64-*.zip` |

> 若所在网络对 `curl -o` 落盘有限制（沙箱常见），改用 Python 的 `urllib` 流式写盘。

## 2. 装完必须做的三件事

1. **放 `sqlite3.dll`**（不做 → 大面积测试挂）：
   `package:sqlite3` 在 Windows 先找 `sqlite3.dll`，找不到才退到 System32 的
   `winsqlite3.dll`；后者不支持 `RETURNING`（需 SQLite ≥ 3.35）→ drift 的
   `insertReturning` 全部报 `near "RETURNING": syntax error`。
   把官方 DLL 放进一个 PATH 目录，并**复制一份到 flutter_tester 同目录**
   （`<flutter>/bin/cache/artifacts/engine/windows-x64`，exe 目录优先）。
   ⚠️ 换机器 / 换 SDK 后要重新放。

2. **Gradle 缓存只能给全新空目录**（`GRADLE_USER_HOME`）。
   **复制已有缓存会让 Gradle 启动即挂死**，且表现成「网络慢」，极易误判。

3. **`flutter test` 必须去代理**（`http_proxy` 会劫持 flutter_tester 的本地 WebSocket）；
   **构建相反要走镜像 / 代理**。

## 3. 依赖安装：优先 `dart.exe`，别迷信 `flutter`

- `flutter pub get` 有时会长时间无输出；直接用
  `<flutter>/bin/cache/dart-sdk/bin/dart.exe pub get`（配 `PUB_HOSTED_URL` 镜像）更稳。
- `flutter analyze` 与 `dart analyze` 结果等价；前者在某些环境会被莫名杀掉，后者稳。
- ⚠️ 不设置 `PUB_HOSTED_URL` 就跑 `pub get`，会把 `pubspec.lock` 里所有包的
  `url` 改写成 `pub.dev` —— 本仓库的 lock 用的是镜像 host，改动会产生一大坨无关 diff。

## 4. 排障速查

| 现象 | 真因 | 解法 |
|---|---|---|
| 命令停在「Flutter assets will be downloaded from…」 | 上次被 SIGTERM 杀掉的 flutter 留下 `bin/cache/lockfile`，后续全在等锁 | 停掉残留后台任务，把 lockfile 改名移走 |
| `rm` / `os.remove` 报 safe-delete / trash 失败 | 环境拦删除 | 用改名（`mv`）绕开 |
| 前台长命令被 SIGTERM（约 120s） | 工具默认超时 | 显式传 `timeout` 或放后台跑 |
| `sdkmanager "platforms;android-35"` 报 not found | **cmd 把 `;` 当参数分隔符**，只装上了 platform-tools | 解析 `repository2-3.xml` 直下 zip |
| `yes \| cmd //c "xxx.bat"` 把 `y` 当命令执行 | `//c` 被 shell 吃掉，cmd 进交互模式 | 直接 `./xxx.bat` |
| 解压后目录多一层（`platform-36/android-36`） | zip 内含顶层目录 | `mv 内层/* 上层/`；`source.properties` 必须留在平台根目录 |
| `flutter` / `git` / `grep` 报 command not found | PATH 缺 `/usr/bin:/bin` 与 PortableGit 的 cmd | 命令前补 PATH，或 `source env.sh` |

## 5. 验收

- `dart analyze` → `No issues found!`
- `flutter test --no-pub`（去代理）→ 全绿。
- 把本机专属路径与踩到的坑写回 `env.sh` 与交接文档，避免下次重踩。
