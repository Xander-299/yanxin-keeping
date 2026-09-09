# 迁移任务清单（Flutter）

> 配套 `SPEC-flutter-migration.md`（**未签字前不许开工**）
> 每步：实现 → 测试门禁 → 勾选 → 再进下一步

## F0 环境搭建 ✅ 已完成（2026-09-09）

- [x] Flutter 3.47.2 → `D:\Download\Flutter\flutter`（Dart 3.13.2）
- [x] JDK 17.0.20.1+1 → `D:\Download\Java\jdk-17.0.20.1+1`，已 `flutter config --jdk-dir`
- [x] cmdline-tools → `D:\Download\Java\Android\cmdline-tools\latest`
- [x] `flutter doctor --android-licenses` 已全部接受
- [x] 门禁：`flutter doctor` → Flutter ✅ / Android toolchain ✅ / Network ✅；残留告警均为 Windows桌面、web、wmic 沙箱拦截，与 Android 无关
- [x] 真机：Redmi K50 无线 adb 可见
- [ ] 清理 `D:\Tencent\yanxin-flutter\_sdk`（2.1GB 临时 zip，F1 后删）

## F1 空壳 + 依赖（analyze/test 已过，剩 APK 门禁）

- [x] `flutter create --platforms=android --org com.teacodeman --project-name yanxin .`
- [x] 依赖锁定（见 README「版本锁死的理由」）：drift 2.31.0 / drift_flutter 0.2.8 / sqlite3 2.9.4 / drift_dev 2.31.0 / build_runner 2.15.1 / flutter_riverpod 3.4.3 / go_router 18.0.1 / uuid 4.6.0
- [x] `flutter pub get` 通过
- [x] `analysis_options.yaml` 收紧（strict-casts/inference/raw-types + prefer_const + avoid_print 等）
- [x] lib 骨架：main.dart（ProviderScope）+ app.dart（go_router + 占位首页）+ 冒烟测试
- [x] `flutter analyze` → **No issues found!**
- [x] `flutter test` → **All tests passed!**（踩坑：沙箱吞 PROGRAMFILES(X86) + 代理劫持 WebSocket，解法固化在 `env.sh` 的 `fx-test`/`fx-qa`）
- [x] git init + 提交 `ba45fba` + 远端 origin 已配（远端仓库待用户网页创建）
- [x] 门禁：`flutter build apk --debug` 成功（2026-09-09，第 8 次构建，`build/app/outputs/flutter-apk/app-debug.apk` 169MB）
- [x] 已推送 `origin/master`（`git@github.com:Tea-Codeman/yanxin-bookkeeping-flutter.git`）
- [x] F5 再装：excel / csv / gbk_codec / file_picker

> **坑**：`flutter pub add` 本机卡死 20min+ → 改「Python 查 pub API → 手写 pubspec → `pub get`」。
> **坑**：sqlite3 3.x 带 C 构建钩子，无 VS 的 Windows 跑不了 `flutter test` → 锁 2.9.4。
> **坑**：把 `<USER_HOME>\.gradle\caches` 复制到工作区会让 Gradle **启动即挂死**（`--status` 都无响应）→ 必须让 Gradle 用**全新空目录**自行下载（腾讯/阿里云镜像很快）。

## F2 core/utils ✅ 已完成（2026-09-09）

- [x] `money.dart`（整数分，格式化/解析）
- [x] `id.dart`（UUID v4）
- [x] `fingerprint.dart`（入账指纹算法，与旧版逐字节一致）
- [x] `date.dart`（月份边界、月初月末、按天分组）
- [x] 门禁：移植 money/id/date 全部旧用例 + 指纹 golden 向量 → `flutter test` 27/27、`flutter analyze` 0 issue

## F3 数据层 ✅ 已完成（2026-09-09）

- [x] drift tables：books / accounts / categories / transactions / schema_meta（DDL 对齐 schema v1，已对拍 `sqlite_master`）
- [x] 7 条索引原样落地（含 `DESC` 与 `idx_tx_fingerprint` 部分唯一索引，见 `core/db/schema_v1.dart`）
- [x] schemaVersion=1（drift 托管 `PRAGMA user_version`）+ onCreate 建表建索引
- [x] repositories：book / account / category / transaction（含 `active_book_id` 持久化）
- [x] `importTransaction()` 指纹幂等入账（先查后插，`ImportResult` sealed 类）
- [x] 门禁：移植 db + repositories 用例（软删、指纹唯一、迁移幂等、账本隔离、月份边界）→ `flutter test` **56/56**、`flutter analyze` **No issues found**
- [x] `dart run build_runner build` 生成 `lib/core/db/database.g.dart`（已入库）

> **坑**：drift 的 `@TableIndex` 不支持 `DESC` / 部分索引 `WHERE` → 索引一律在 `onCreate` 走原始 SQL。
> **坑**：`Transactions` 表数据类名必须改成 `TxRow`（`@DataClassName`），否则与 drift 自带 `Transaction` 撞名。
> **坑**：`drift` 与 `matcher` 都导出顶层 `isNull` → 测试里 `import 'package:drift/drift.dart' hide isNull`。

## F4 UI 基础（M1 等价）

- [ ] 首页：hero（月切换 ‹ ›，canNext 不超前当前月）+ 流水列表
- [ ] 记一笔：金额键盘 + 分类选择 + 备注 + 时间
- [ ] 分类管理 / 账本管理
- [ ] 门禁：M1 等价验收 8 项（真机）

## F5 账单导入（M2 等价）

- [ ] `gbk_codec` 验证（**第一步**，失败立刻换 charset_converter）
- [ ] CSV 解析 + 微信/支付宝 profiles 别名
- [ ] xlsx 解析（excel 包）+ Excel 序列号时间列换算
- [ ] categorize 关键词规则
- [ ] importer：单事务 + 指纹去重
- [ ] 导入页 UI（选文件 → 预览 → 可取消单条 → 确认导入）
- [ ] 门禁：移植 bill-import 用例 + **真实件对拍，与旧版逐行一致**

## F6 验收收尾

- [ ] M2 等价验收 8 项（真机）
- [ ] README / CHANGELOG 建立
- [x] 旧仓库 README 顶部加「已迁移至 yanxin-flutter」说明
