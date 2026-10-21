# HANDOFF — 颜芯记账（Flutter）

本地优先的个人记账 App，目标平台 **Android**。本文件是**接手入口**：现状、硬约束、
去哪找细节。历史过程与完整参考都在 `docs/handoff/`，不必通读。

## 现状

| 项 | 值 |
|---|---|
| 交付状态 | F1–F7.17 **全部交付**，最新 tag **`v0.7.17`**，无未收口批次 |
| 下一步 | 等新需求；新功能走「小 SPEC 签字 → 实现 → 门禁 → 文档」 |
| 技术栈 | Flutter 3.47.2 / Dart 3.13.2 · drift 2.31.0 · Riverpod 3 · go_router 18 |
| 数据库 | schema **v3**（v2 加 `budgets`，v3 加 `accounts.icon` / `accounts.color`） |
| 门禁 | `flutter analyze` + `flutter test`，已在 CI 自动跑（`.github/workflows/ci.yml`） |

## 开始工作前

```bash
cp env.example.sh env.sh     # env.sh 不入库；按本机改路径或用环境变量覆盖
source env.sh
fx-qa                        # = flutter analyze && flutter test（去代理）
```

依赖版本**锁死，不要随手升**：`drift 2.31.0` / `sqlite3 2.9.4` / `build_runner 2.15.1`。
`sqlite3 3.x` 起带 native-assets 构建钩子（Windows 上需要 MSVC），
`build_runner 2.16+` 要求 analyzer ≥13 与 `drift_dev` 冲突。

改了 `lib/core/db/tables.dart` 必须重跑 `dart run build_runner build --delete-conflicting-outputs`
并提交 `database.g.dart` —— CI 有一条硬检查会因此失败。

**出 APK（2026-10-21 起可直接用 flutter 命令）**：本仓库在**中文路径**下，AGP 会直接拒绝构建
（`Your project path contains non-ASCII characters`）。前置一步，写在**不入库**的
`$GRADLE_USER_HOME/gradle.properties`（本仓库 `GRADLE_USER_HOME=.gradle-home`）：

```
android.overridePathCheck=true
```

然后 `flutter build apk --debug` 即可（本机实测约 8 分钟首构、增量 1.5 分钟）。
装机后**必跑** `python tool/verify_apk_kernel.py <本次新增字符串>` 核验包是新码。

## 必须守住的不变量

这几条每条都有回归测试兜着，改动前先看测试为什么这么写：

1. **drift 是唯一 DB writer** —— Kotlin 侧只落盘 JSONL，不碰数据库。
2. **常驻 provider 要 `ref.watch(dataEpochProvider)`** —— 否则「刚记一笔后搜索搜不到」
   这类过期快照 bug 会回来（`test/features/search/search_freshness_test.dart`）。
3. **纯函数优先** —— 解析、金额、命中口径、聚合统计都是无副作用纯函数，`test()` 直接覆盖。
4. **金额一律 `int` 分**，禁止浮点。
5. **go_router 实例放在 App State**，不能是顶层 `final`；且 `context.push().then`
   在 `StatefulShellRoute` 壳下**不兑现** → 保存后刷新由被推页面自己在 pop 前做。
6. **色值一律走调色板 `context.toon`（`p.xxx`）**，产品代码里不出现裸 `Color(0x…)`。
   F7.17 起 `Tok` **只剩几何量**（描边宽 / 圆角）；颜色是 `ThemeExtension<ToonPalette>` 的
   **实例字段**，靠 `Theme.of` 建立依赖 —— 这样才能随浅/深主题切换重建。
   **别把颜色改回 `const`**：`const` widget 会被 Element 判 `identical` 跳过重建，切主题不刷新。
7. **对比度三条硬规则（F7.17 起，护护栏 `test/core/theme/palette_contrast_test.dart`）**
   - **hero（恒琥珀底）只能用 hero 家族色**：减淡层 `veil@α`、描边 `inkOn(brand)`、字 `heroInk`。
     用 `paper@α` 当减淡层会在深色下把气泡压暗（实测 2.12:1）。
   - **描边跟着底色走**：`p.inkBorder(on: <底色>)`，亮底自动取 `decorInk`。
     直接在琥珀底上写 `p.ink` 描边 → 深色下 `ink` 是暖白，描边整条消失（1.26:1）。
   - **前景必须配对的底**：`onBrand`→`brand`、`brandInk`→浅底、`onRed`→实心红、`redInk`→`redTint`。
     放错底（如 `onBrand` 放纸底）浅色看不出来，深色下直接看不见。
   门槛：正文小字 **4.5:1**、描边/图形 **3.0:1**。

## 最容易踩的坑（完整清单见 [`docs/handoff/pitfalls.md`](docs/handoff/pitfalls.md)）

- `flutter test` 必须**去代理**（`http_proxy` 会劫持 flutter_tester 的本地 WebSocket）；
  `flutter build` 相反要走镜像。
- **`flutter build` 会隐式跑 `pub get`，把 `pubspec.lock` 里的 transitive 版本升上去**
  （实测一次 `flutter build apk` 就把 `pubspec.lock` 改了 157 行、4 个包升版本，还顺手把
  registry 从 `pub.flutter-io.cn` 改成 `pub.dev`）。提交前**必看 `git diff pubspec.lock`**；
  变了就 `git checkout -- pubspec.lock` → `flutter pub get`（带 `PUB_HOSTED_URL` 镜像）→
  确认 diff 为空，再用 `flutter build apk --no-pub` 重出包。依赖是**锁死**的，别顺手提交。
- widget 测试里写库是真实异步，`pumpAndSettle` 会早退 → 用轮询等待；
  800×600 视口很矮，断言长页面靠下的元素前先滚动。
- 改了 UI 入口后，**全仓无上限地** grep 旧断言（`保存` / `ensureVisible` /
  `widgetWithText(AppBar`）—— 曾因 grep 加了上限而漏掉一个文件，用户终端直接挂。
- 真机走查见 [`docs/dev/android-ui-smoke.md`](docs/dev/android-ui-smoke.md)：
  语义树是「有没有 / 在哪」的真值，截图才是「颜色 / 遮挡」的真值，**两者交叉验证**。
- **出 release 包必须走 ASCII 副本**：项目在中文路径下，`gen_snapshot` 会因路径含非 ASCII
  直接挂（报 `Unable to read file: …\.dart_tool\flu`）。做法是 robocopy 到 `D:\yanxin-build`
  （排除 `build` / `.gradle-home` / `.git`）+ 带上仓库的 `pubspec.lock` 与 `.dart_tool` +
  `--no-pub` 构建。keystore 口令、核验三步、发布命令见
  [`docs/dev/release-v0.7.17.md`](docs/dev/release-v0.7.17.md)。
- **换签名 = 用户必须卸载重装 = 丢本地账本**：release 签名只用
  `<USER_HOME>\upload-keystore.jks`（`CN=yanxin`），**不是** `~/.android/debug.keystore`。
  装机前先 `apksigner verify --print-certs` 比对指纹。

## 目录导航

```
lib/
├── app.dart                 路由表（go_router：壳路由 + 全屏页）
├── main.dart                入口
├── core/                    基础设施（不依赖任何 feature / data）
│   ├── db/                  drift：tables / database / schema_v1 / schema_v2
│   ├── providers/           data_epoch（写操作后的统一失效信号）
│   ├── theme/               palette.dart（调色板 · 浅/深两套）+ theme_mode.dart（外观三选一）
│   │                        + tokens.dart（几何量 + buildToonTheme）+ toon.dart（卡通通用件）
│   ├── utils/               money / id / fingerprint / date / highlight
│   └── constants/           preset.dart
├── data/
│   ├── providers/           数据层 DI：database + book / account / category 等
│   └── repositories/        6 个仓储
└── features/                按业务垂直切分：application（逻辑）+ presentation（UI）
```

- 纯 UI 的 feature（`book` `category` `profile` `nav`）只有 `presentation/`，
  数据与状态在 `lib/data/providers/` 或对应 controller 里 —— 这是有意的例外，不是漏了。
- `docs/` 下：`spec/` 签字的 SPEC、`dev/` 开发运维手册、`acceptance-*.md` 走查报告、
  `handoff/` 交接档案。

## 档案索引

| 文档 | 内容 |
|---|---|
| [`docs/handoff/reference.md`](docs/handoff/reference.md) | **开工前读**：环境事实 / 架构决策 / 关键资料 / 接手指南 |
| [`docs/handoff/pitfalls.md`](docs/handoff/pitfalls.md) | 盲区防护清单：踩过的坑与判据 |
| [`docs/handoff/open-issues.md`](docs/handoff/open-issues.md) | 未解决问题、待确认事项 |
| [`docs/handoff/history.md`](docs/handoff/history.md) | 已完成的工作、已尝试但放弃的方案（**别重复做**） |
| [`docs/handoff/status-log.md`](docs/handoff/status-log.md) | 逐版本状态流水 + 极简版摘要（历史，不是现状） |
| [`docs/handoff/session-log.md`](docs/handoff/session-log.md) | 逐轮会话记录（根因、取证、验证过程） |
| [`CHANGELOG.md`](CHANGELOG.md) | 版本变更 + tag 表 |
| [`docs/RESUME.md`](docs/RESUME.md) | 简历用项目介绍（规模 / 难点 / 迭代记录） |
| [`docs/spec/`](docs/spec/) | 各阶段签字的 SPEC |
| [`docs/dev/`](docs/dev/) | 真机走查、Windows 环境重建 |
| [`docs/dev/release-v0.7.17.md`](docs/dev/release-v0.7.17.md) | **出 release 包 + 发布**：keystore / 口令 / ASCII 副本构建法 / 核验三步 |
| [`tasks/todo-flutter.md`](tasks/todo-flutter.md) | 迁移任务清单 |
