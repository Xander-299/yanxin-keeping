# F7.7 D / E 批 真机走查记录

> **日期**：2026-09-24 · **执行**：AI（经 adb 全包，MuMu 12）
> **被验版本**：F7.7 C 批 + D 批 + E 批（工作区最新）· **基线**：`v0.7.9`
> **设备**：MuMu 12 @ `127.0.0.1:16384`，900×1600 @320dpi（竖屏，逻辑 450×800）
> **判读手段**：`uiautomator` 语义树（可信真值）+ 截图交叉验证；抓取脚本 `.workbuddy/ui_dump.py`
> **构建方式**：见文末「构建路径（本机 Dart 管道故障下的变通）」

---

## 1. 装包与数据保持

| 操作 | 看到的反馈 | 判定 |
|---|---|---|
| `adb install -r -t app-debug.apk`（**不** `pm clear`） | `Performing Streamed Install` → `Success` | ✅ |
| 冷启动 → 首页 | `9月 · 支出 ¥286.88`（与升级前一致） | ✅ 老数据不丢 |
| 与 C 批走查数据比对 | 支出 286.88 / 结余 -286.88 / 预算 1000 28.7% 全部一致 | ✅ |
| 走查结束后复核 | 账户数回到 **2**、净资产回到 **¥-235.48**（走查造的数据已软删还原） | ✅ |

> D / E 两批**不动 schema**（复用既有 `schema_meta` KV），所以「覆盖安装验迁移」不是本批重点；
> 但仍按规矩做了覆盖安装 + 老数据比对（schema 停在 v3）。

## 2. D 批：搜索增强

| 操作 | 看到的反馈 | 判定 |
|---|---|---|
| 首页 header 点「搜索」 | 浮层打开：类型 chips（仅支出/仅收入/转账）+ **独立一行「时间：全部/本月/近3月」** + 引导文案（含「账户名（招行 / 支付宝）」）+ 示例 chips（餐饮/房租/88/工资） | ✅ 区间行是新增项，独立成行未挤压 |
| 点示例词「餐饮」 | `共 2 笔 支出 101.18`；两行分别是 9月18日 / 8月1日，分类名「餐饮」 | ✅ |
| 截图放大看命中处 | 「餐饮」四字带 **暖黄底色**（`brandTint2`） | ✅ 关键词高亮生效 |
| 回车提交（`keyevent 66`）→ 点清空 | 引导态下方出现 **「最近搜过」** 块 + 历史 chip「餐饮」+「清空历史」 | ✅ 历史记录 |
| 查库 `schema_meta` | `search_history \| ["餐饮"]` | ✅ 真落库（KV 复用，无新表） |
| 点历史 chip「餐饮」 | 关键词回填输入框并出结果（`共 2 笔`） | ✅ 一点即搜 |
| 只点区间「本月」（不输关键词） | `共 5 笔 支出 286.88` + 结果条后缀 **`· 本月`**；8月那笔被排除 | ✅ 区间可单独生效（= 与首页月支出口径一致） |
| 输 `PayPal` | `没有匹配「PayPal」的账单` | ✅ **正确**：该账户属于已软删的 `QA-Temp` 账本，本账本不该命中 |
| 输 `50` / `QABank`（新记的 ¥50 流水） | 两次都落空 → 重启 App 后 `QABank` 立即命中 `共 1 笔 / 50.00 / 今天·购物` | ❌→✅ **抓到真 bug**（见第 4 节） |

## 3. E 批：日历增强

| 操作 | 看到的反馈 | 判定 |
|---|---|---|
| 日历 tab | `2026年9月` 网格 + 月结余 + 选中日区 | ✅ |
| **长按** 9月10日 格子（`input swipe x y x y 800`） | 直接落到「记一笔」页，**日期 = `2026年9月10日 周四`** | ✅ 长按带上那一天 |
| 返回日历 | 下方选中日区变成 **`9月10日 周四`**（顺带把那天选中了） | ✅ |
| 左滑（700→200） | 顶部 `2026年9月` → **`2026年10月`** | ✅ |
| 右滑（200→700） | 回到 `2026年9月`，下方日列表同步为 `今天 9月24日 周四` | ✅ 年月与日列表同源 |
| 小幅横拖 150px | **翻月了**（阈值 = 1/3 格宽 ≈ 42 物理 px ≈ 21 逻辑 px，与 SPEC §E.1.2 一致，不是 bug） | ✅ 符合 SPEC |
| 网格上**竖向**滑动 | 月份不变 ✅；当屏内容恰好一屏放下（内容底 ≈1400 < 导航栏 1532），故无位移属正常 | ✅ / ⚠️ 见下 |

> ⚠️ 「竖向滑动仍能滚动页面」这一条**当屏内容刚好放满，真机测不出位移**。
> 该风险点由 widget 测试兜底：`calendar_page_test.dart` 的
> `滑不够阈值不翻月；竖向滑动仍然滚动页面（不吃竖向手势）`（默认 800×600 视口下内容必溢出，
> 断言 `MonthGrid` 的 y 变小 = 真的滚动了，且月份不变）。实现上也只注册了横向 drag，
> 竖向仍归外层 `SingleChildScrollView`。

## 4. 走查抓到的真 bug：搜索结果是过期快照

**现象**：新记一笔（¥66 / 交通 / 新账户 `QABank`）后**不重启**直接搜索，搜金额 `66`、搜账户名
`QABank` 都命中不到；`kill` 掉再启动立刻能搜到。

**定位过程**（三步排除法，避免误判成「账户名命中没接上」）：

1. 查库确认新账户与新流水**都在当前账本**（`book_id = 03dffb2c`，`deleted_at` 为空）→ 不是跨账本问题；
2. 搜新流水**金额** `50` 也落空 → 说明整个 `items` 快照都是旧的，不只是账户名表；
3. `force-stop` 重启后同关键词立刻命中 → **确认是内存快照过期**，不是匹配口径问题。

**根因**：`searchProvider` 是**常驻** provider（非 autoDispose，浮层关掉再打开不重建），
`build()` 只 `watch` 了 `activeBookIdProvider`，没有任何「数据变了」的信号；
原先只有浮层内部的编辑 / 删除会手工 `refresh()`。**这是 F7.4 起就存在的老问题**，
D 批新增的「账户名命中」把它暴露到了主路径上（加账户 → 想搜，必落空）。

**修法**：`SearchController.build()` 里加 `ref.watch(dataEpochProvider)` —— 项目既有的
「写操作版本号」（`record_page` / `assets_controller` / `import_page` / 各删除入口都会 bump）。
一处接入即自动作废重取，符合 `data_epoch.dart` 里写明的设计意图（「新页面接入零成本」）。

**回归测试**：`test/features/search/search_freshness_test.dart`
（ProviderContainer 造「先取快照 → 加账户 + 记一笔 → bump → 再取」，断言新快照含新流水；
**已实测**：注释掉那行 watch 该用例必失败，加回来通过）。

**真机复验**：改完重新打包覆盖安装 → 不重启，`记一笔 ¥66 → 搜索 66` → `共 1 笔 / 66.00 / 今天·交通` ✅

## 5. 稳定性

| 检查 | 结果 |
|---|---|
| 走查全程 `logcat -b crash` | 无本 App 崩溃（仅一条无关的 Google Play Services 后台服务异常） |
| `E/flutter` / `Unhandled Exception` / `AssertionError` | 无 |
| 进程存活 | `pidof com.teacodeman.yanxin` 有输出 |

---

## 构建路径（本机 Dart 管道故障下的变通）

本机有主机级故障：**Dart 作父进程 spawn 带管道 stdio 的子进程必败**
（`ProcessException: 所有的管道范例都在使用中 (CreateFile failed 231)`，`process_win.cc:744`）。
连 `cd android && ./gradlew assembleDebug` 也会挂 —— 因为 `:app:compileFlutterBuildDebug`
内部是 `flutter.bat → dart → frontend_server`，照样撞 231。

**Python 不受影响**（`subprocess` 走匿名管道 `CreatePipe`）。所以：

```bash
source env.sh                                   # 必须：GRADLE_USER_HOME 指进工作区
python tool/build_kernel_fallback.py            # 用 Python 起 frontend_server 产出 kernel_blob.bin
cd android && ./gradlew assembleDebug -x compileFlutterBuildDebug
```

- `tool/build_kernel_fallback.py`：参数逐字照抄构建日志里 `kernel_snapshot_program` 的命令行，
  再按 `copy_flutter_bundle` 把 `app.dill` 复制成 `flutter_assets/kernel_blob.bin`，打印 sha256 供核验。
- `-x compileFlutterBuildDebug` 跳过那条必挂的 Dart 链；其余 Gradle 任务照常。
- **上线前核验**（防「装到旧包」）：从 APK 里读出 `assets/flutter_assets/kernel_blob.bin`，
  比对 sha256 与盘上一致、并 grep 本次新增文案（如「最近搜过」「近3月」）。
