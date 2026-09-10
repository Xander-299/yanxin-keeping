# 颜芯记账（Flutter 版）

本地优先的个人记账 App。Flutter 3.47.2 / Dart 3.13.2，当前目标平台 **Android**。

> 这是 uni-app 版的**重写**。旧仓库 `Tea-Codeman/yanxin-bookkeeping`（uni-app Vue3 + Vite）已归档为只读，不再开发。

## 为什么要重写

| 旧栈痛点 | Flutter 后 |
|---|---|
| `plus.android` 桥接地狱（运行时 Java 实例须 `invoke` 直调） | `file_picker` 插件一行拿字节 |
| `plus.sqlite` **无参数绑定**，所有值手工转义（旧 ADR-5） | drift 编译期生成参数绑定 |
| HBuilderX 手工打包，无 CI | `flutter build apk` + CI 自动化 |
| x86_64 模拟器必然白屏，只能真机 | 官方模拟器可用（含 MuMu 等第三方模拟器） |
| 自研 `xlsx.js`（fflate + 手写解码） | `archive` 解压 + 手写正则解析器（**不用 `excel` 包**：数值过 double 会丢 31 位单号精度） |

## 技术选型

| 关注点 | 选型 |
|---|---|
| 数据库 | **drift 2.31.0** + `drift_flutter 0.2.8` + `sqlite3 2.9.4`（编译期参数绑定，类型安全） |
| 状态管理 | Riverpod 3 |
| 路由 | go_router 18（`StatefulShellRoute.indexedStack` 壳 + 底栏 4 tab） |
| 金额 | `int` 分（ADR-2） |
| 主键 | UUID v4，客户端发号（ADR-1） |
| 入账指纹 | `crypto 3.0.7` SHA-1（纯 Dart，无 native 钩子） |
| 文件选择 | `file_picker 12`（Android SAF，免存储权限） |
| xlsx 读取 | `archive`（ZIP 解压）+ `bill_xlsx.dart` 手写正则解析器 |
| CSV / GBK | 自研逐字符状态机 + `gbk_codec`（纯 Dart 映射表，回环校验判坏件） |

> ⚠️ **drift/sqlite3 版本锁死的理由**：sqlite3 3.x 起带 C 构建钩子（native-assets），Windows 上 `flutter test` 需要本机 MSVC 编译器，本机无 VS 会失败。因此锁 `drift 2.31.0 / drift_flutter 0.2.8 / sqlite3 2.9.4 / build_runner 2.15.1`（build_runner 2.16+ 要求 analyzer >=13，与 drift_dev 2.31 冲突）。装了 VS Build Tools 后可整体升级。

## 目录结构

```
lib/
  core/
    db/          drift database / tables / migrations
    utils/       money / id / fingerprint / date
    constants/   preset_categories
  data/
    repositories/
  features/
    ledger/  record/  category/  book/  import/
  app.dart  main.dart
test/
```

## 本地开发

每次开终端先加载环境（Windows / Git Bash），它把本机所有踩坑配置都收拢了：

```bash
source env.sh
```

常用命令：

```bash
flutter pub get                                              # 走 env.sh 里的 7890 代理
dart run build_runner build --delete-conflicting-outputs     # drift 代码生成
fx-qa                                                        # analyze + test（自动去代理/补 VS 环境变量）
fx-test                                                      # 只跑单测
flutter build apk --debug
```

> ⚠️ **`flutter test` 直接跑会踩两个坑**（env.sh 已处理）：
> ① 沙箱吞掉了 `PROGRAMFILES(X86)`，VS 探测直接抛错 → 需手动注入；
> ② 代理会劫持测试进程的 WebSocket（`Invalid WebSocket upgrade request`）→ 跑测试必须去代理。

## 迁移进度

见 [`SPEC-flutter-migration.md`](SPEC-flutter-migration.md) 与 [`tasks/todo-flutter.md`](tasks/todo-flutter.md)。

| 阶段 | 内容 | 状态 |
|---|---|---|
| F0 | 环境搭建 | ✅ |
| F1 | 空壳 + 依赖 | ✅ |
| F2 | core/utils | ✅ |
| F3 | 数据层（drift schema v1 + repositories） | ✅ |
| F4 | UI 基础（M1 等价） | ✅ 真机验收通过 |
| F4.5 | 首页改版 + 底部导航 | ✅ |
| F5 | 账单导入（M2 等价） | ✅ 代码 + MuMu 走查通过 |
| F6 | 真机验收 + 文档收尾 | ✅ |
| F7.1 | 日历页（月历标注 + 日账单 + 月份选择子页） | ✅ |
| F7.2 | 预算实装 / 统计·报表·搜索 / 资产 / 数据导出 | ⬜ 待排期 |

**验收基线**：M1/M2 首次使用验收报告 → [`docs/acceptance-M1-M2.md`](docs/acceptance-M1-M2.md)（MuMu 12 隔离环境实走）。

**变更历史**：见 [`CHANGELOG.md`](CHANGELOG.md)。

## 架构红线

- ❌ 手写 SQL 字符串拼接（一律走 drift 生成的参数绑定）
- ❌ 用浮点表示或计算金额（一律 `int` 分）
- ❌ 物理 DELETE 业务数据（一律软删 `deleted_at`）
- ❌ 绕过 `importTransaction()` 直接写 `transactions` 表
- ❌ xlsx 数值经 `double` 中转（会丢 31 位单号精度，解析器必须按字符串走）

## 开发规范

- **首次使用验收**：新增功能、改动入口文案/默认值/授权流程后，重跑 `first-run-acceptance`。
  规则与验收标准见 [`docs/acceptance-M1-M2.md`](docs/acceptance-M1-M2.md)（M1/M2 基线报告）。
