# 发布记录：v0.7.17 release 包（2026-10-21）

> 记录「怎么在本机出正式签名 release 包并发布」。**关键事实散落在三处，下次先读这份。**
>
> ⚠️ **2026-10-29 安全处理**：keystore 口令已**轮换为随机值**（本文件不再记录实值），
> 证书指纹未变（`d46b65a4…e86567`），已发布包的签名不受影响。

## 1. keystore 与口令（勿再问用户）

| 项 | 值 |
|---|---|
| keystore | `<用户目录>\upload-keystore.jks`（JKS，别名 `upload`，2026-09-25 建） |
| storePassword / keyPassword | **2026-10-29 已轮换为随机口令，向维护者索取**（本机副本在仓库外的 `upload-keystore-password.txt`，请转进密码管理器后删除该文件） |
| keyAlias | `upload` |
| 证书 | `CN=yanxin, OU=Unknown, O=Unknown, L=Shenzhen, ST=Guangdong, C=CN` |
| SHA-256 指纹 | `d46b65a43bcfc6633f5460fb893b6b6e55db66ae16ac650054fb085698e86567` |

- `android/key.properties` 四键按上面写即可（已在 `.gitignore`，**不会入库**）。
- ⚠️ **别用 `<用户目录>\.android\debug.keystore`** —— 那是 `CN=Android Debug`，与 v0.7.16 起
  所有发布包**不是同一把钥匙**，换了签名用户必须卸载重装（丢本地账本）。
- 判断「是不是同一把钥匙」：`apksigner verify --print-certs` 比 SHA-256 指纹即可。
- 口令**不入库**：只保存在仓库外的密码管理器与本机 `android/key.properties`（已 gitignore）；
  需要验证时用 `keytool -list -keystore <ks> -storepass <pw>`（能打开 + 指纹一致 = 对）。

## 2. 本机构建 release 的前置条件

| 项 | 值 / 做法 |
|---|---|
| JDK | `D:\Download\Java\jdk-17.0.20.1+1`（Temurin 17，**勿用 JDK 25**） |
| JAVA_HOME | 必须显式设成上面这个；PowerShell 里 `& "<path>\bin\java.exe"` 可能失败，用 `cmd /c` 验证 |
| Gradle 缓存 | `GRADLE_USER_HOME=<repo>\.gradle-home`（3.7 GB，wrapper 已缓存 gradle-9.3.1-bin） |
| 中文路径 | `.gradle-home/gradle.properties` 已有 `android.overridePathCheck=true` |
| **AOT 编译** | **中文路径下必挂**（`gen_snapshot` 报 `Unable to read file: ...\.dart_tool\flu`，路径被截断）→ 见 §3 |
| 代理 | `http://127.0.0.1:7890`（构建期下载资源需要；`flutter test` 相反要去代理） |

## 3. 绕中文路径：ASCII 副本构建法（v0.7.17 首次采用）

```
1) robocopy <repo> D:\yanxin-build /E /XD build .gradle-home .git __pycache__ /XF *.log
2) cp <repo>\pubspec.lock  D:\yanxin-build\pubspec.lock     # 锁定的依赖版本
3) cp <repo>\.dart_tool    D:\yanxin-build\.dart_tool -Recurse -Force   # 仓库那套解析结果
4) cd D:\yanxin-build && flutter build apk --release --no-pub --split-per-abi
```

**为什么必须 `--no-pub`**：`flutter build apk` 会隐式跑 `pub get`，把 lock 里的依赖**升级 115 个**
（`go_router 18.0.1 → 18.1.1`、`file_picker 12.2.0 → 12.3.0`），直接违反「依赖锁死」硬约束。
`flutter pub get --offline` **也拦不住**（它照样重解析）→ 只有 `--no-pub` 能保证用锁定版本。
副作用只落在副本里，仓库 `pubspec.lock` 零污染（`git status` 可证）。

> universal（fat）包要单独再打一次：`flutter build apk --release --no-pub`（不带 `--split-per-abi`）。
> v0.7.17：universal 64.4 MB / arm64 21.9 MB / armeabi-v7a 20.6 MB / x86_64 23.0 MB。

## 4. 装机前核验（三步，缺一步别装机）

```bash
# 1) 签名指纹必须与 v0.7.16 一致（否则用户覆盖安装会失败/丢数据）
apksigner verify --print-certs <apk>        # 指纹见 §1

# 2) 包里确实是这次的新码（防「装到上一版」误判「改了没用」）
python tool/verify_apk_kernel.py --apk <apk> --grep themeMode_ --grep 跟随系统

# 3) 版本号已进包
python tool/verify_apk_kernel.py --apk <apk> --grep 0.7.17
```

## 5. 发布（GitHub Release）

```bash
python tool/publish_release.py --tag v0.7.17 --name "颜芯记账 v0.7.17" \
    --notes-file docs/release-notes-v0.7.17.md \
    --apk build/app/outputs/flutter-apk/yanxin-v0.7.17-universal-release.apk \
    --apk build/app/outputs/flutter-apk/yanxin-v0.7.17-arm64-release.apk
```

- 令牌从 `git credential fill` 现场取（40 位 classic PAT），**不落盘**；脚本**需要代理**。
- 上传端点是 `upload_url`（`uploads.github.com`），脚本已处理。
- 同 tag 已有 release 会**复用**（幂等）；同名资产会跳过 —— 要覆盖得先在网页删旧资产。
- APK 命名沿用 v0.7.16 规范：`yanxin-v<版本>-{universal,arm64}-release.apk`（README 下载链接写死这两个名字）。

## 6. 本次结果

- Release：https://github.com/Xander-299/yanxin-flutter/releases/tag/v0.7.17
- 两个资产均 200 可下载（64.4 MB / 21.9 MB）
- master 与 origin 已同步（0/0）；`upstream` 远端（旧仓库名残留）已删除
