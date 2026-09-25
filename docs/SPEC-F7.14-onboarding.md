# SPEC — F7.14 新手引导（无文字按钮 / 隐藏手势）

> **状态：✅ 已签字**（2026-09-25 用户裁定四项，见 §7）→ **实现中**
> **版本**：交付后打 tag **`v0.7.14`**（沿用递增；最新已占用 `v0.7.13`）。
> **前置**：F7.13 统计页图表绘制修复已交付（`v0.7.13`，383 全绿 + 走查 0 崩溃）。
> **不动 schema / 零新依赖**（本项目硬约束）。DB 保持 **schemaVersion = 3**。

---

## 1. 要解决的问题

冷启动即进首页、且**没有任何引导**。全站有 17 处「没有文字、只有图标或只有手势」的交互，
其中 6 处连 tooltip 都没有（隐藏手势）。新用户的实际困境：

| 类型 | 具体入口 | 现状 |
|---|---|---|
| 纯图标按钮 | 底栏中央歪 4° 的琥珀方块 | 只有 `Tooltip('记一笔')` —— 手机上要**长按**才现 |
| 纯图标按钮 | 首页 header：搜索 / 报表 / 统计 | 同上，三个 tooltip |
| 纯图标按钮 | 日历 header：菜单 / 报表 / 统计 | 同上 |
| 纯图标按钮 | 资产页 AppBar `+`、账本 & 分类页 `+` | 同上 |
| 纯图标按钮 | hero 卡 `‹ ›` 翻月、预算卡铅笔、统计/报表月份 `‹ ›` | 同上 |
| **无任何提示的手势** | 日历**长按**格子 = 记这一天的账 | 无提示 |
| **无任何提示的手势** | 月历**左右滑** = 翻月 | 无提示 |
| **无任何提示的手势** | 流水行**左滑** = 露出删除（F7.8 新增） | 无提示 |

`Tooltip` 在触屏上必须长按触发，对「不认识这个图标」的用户等于不存在 → **需要一个主动告知的载体**。

**首次使用验收报告的既有结论**（`docs/acceptance-first-run.md` D5 不通过）与本次需求同源。

---

## 2. 目标（DoD）

| # | 可验收行为 |
|---|---|
| D1 | **全新安装**的首次冷启动自动弹出全屏引导（`schema_meta` 无 `onboarding_done` **且** 本次启动前无主账本记录），覆盖首页与底栏 |
| D2 | 引导共 **7 页**，横向可滑，也可点「下一步」；顶部有 7 点进度（**可点跳页**）、右上角「跳过」 |
| D3 | 7 页内容 = §3.2 表，一页一件事；每页配**照真实 UI 画的迷你示意图**（含高亮圈 + 指引箭头） |
| D4 | 点「开始记账」（末页）/「跳过」/ **系统返回** 三条路径都关闭引导，并写 `onboarding_done = '1'` |
| D5 | 已写过标记后，冷启动**不再**弹 |
| D6 | **老用户（从旧包覆盖安装上来的）不弹** —— 只能在「我的 → 新手引导」主动看（用户裁定） |
| D7 | 「我的」页新增**可点**条目「新手引导」→ 随时重看（重看不改任何数据，只再写一次同一个键） |
| D8 | 引导页全程不触碰业务数据：不改账本 / 账户 / 流水 / 预算；只看不写 |
| D9 | 视觉 100% 走 `Tok.*` 令牌 + 现成 `Toon*` 件，**无裸色值**；不再新增主题令牌 |
| D10 | 既有 **9 个 `pumpApp` 测试文件**行为不变（首启弹窗不得打断它们）—— 见 §5 的基建改动 |

---

## 3. 交互规格

### 3.1 触发与关闭

**「该不该弹」= 两个条件同时成立**（`onboardingPromptProvider`，见 §5）：

| # | 条件 | 真源 |
|---|---|---|
| 1 | `schema_meta` 里**没有** `onboarding_done` | 该键只在引导页关闭时写入 → 为空 = 从未看过 |
| 2 | 本次启动前**库里没有主账本记录** = **全新安装** | `ActiveBookIdController.isFreshInstall`（`getActiveBookId() == null`） |

- **为什么条件 2 用 `active_book_id`**：该键自 F1 起每次冷启动都会落库（`ensureDefaultBook` + `setActiveBookId` 成对执行）
  → **老用户（含从旧包覆盖安装上来的）必然有值**，是「这份 App 数据本机是否第一次用」的**唯一真源**。
  外部另找判据（如「表里有没有流水」「账本 `created_at` 多久之前」）会与默认数据的创建时机打架：
  全新安装首启也会立刻建账本 + 现金账户 + 15 预置分类，读完就分不清新老。
- ⚠️ **不可以用「本次是否走了 `ensureDefaultBook` 分支」当判据** —— 「当前账本被软删」等边缘情况也会命中该分支
  （此时 `active_book_id` 其实有值），会把老用户误判成新装。故判据取「读到的瞬间 `stored == null`」。
- **触发点**：`AppShell` 首帧后（`addPostFrameCallback`）`await ref.read(onboardingPromptProvider.future)`；
  `true` → `context.push('/onboarding')`。**不阻塞首帧**：首页照常构建，引导盖在其上。
  - 只检查一次（State 里 `_checked` 防重）。
  - 读库异常 → **不弹**、静默（引导是锦上添花，不能因它阻断冷启动）。
- **关闭路径**（三条，行为一致）+ **标记落库位置**：
  三条路径都是 `pop()`，而 pop 后页面即从树上摘掉 → **「写标记」统一收口在 `dispose()`**，
  不必在跳过 / 完成 / 系统返回三处各写一遍。
  - 写失败（一次 IO 抖动 / 库已关）→ **静默吞掉**： 用户不该被引导页困住，也不该冒出未捕获异常。
  - **不需要 `PopScope`**：不拦截返回，`pop` 正常发生，标记由 `dispose` 补写。
  - ⚠️ `dispose()` 里**不能再用 `ref`** → 仓储在 `initState/字段初始化`时取出（`ref.read(appMetaRepositoryProvider)`）留存。
  - ⚠️ 若用户在引导页**直接杀掉 App**（没 pop）→ 标记不写 → 下次启动再弹一次。可接受（也确实没看完）。
- **手动重看**（D7）：从「我的」`push('/onboarding')`，页内行为完全相同（退出时再写一次同一个键）。
- **老用户**（D6，用户裁定）：条件 2 不成立 → **不弹**，且**不写标记**（`onboarding_done` 只表示「看过引导」，
  老用户没看过，数据上不该被标记成看过 —— 也便于将来排查）。代价 = 老用户每次冷启动多 2 次 KV 读（<5ms，一次性）。

### 3.2 七页内容（逐页定稿文案）

| # | 标题 | 正文 | 迷你示意图 |
|---|---|---|---|
| 1 | 认识一下颜芯记账 | 有几个**没有文字的按钮**和**藏起来的手势**，30 秒看完，以后不会找不到。随时可点右上角跳过。 | 小猪（`PigMascot`，歪 6°）+ 两颗 `Sparkle` |
| 2 | 中间歪着的方块 = 记一笔 | 底栏正中那个**歪 4° 的琥珀方块**是全局记账入口，四个页面都在。它故意做得跟旁边图标不一样，就是让你一眼看到。 | 复刻真实底栏：白条 + 4 个 `_NavItem` 图标 + 中央琥珀方块（歪 4°）；圈注中央 + 向上指引 |
| 3 | 右上角这三个图标 | 放大镜 = **搜流水**（分类 / 备注 / 金额都能搜）；单据 = **报表**（明细 / 分类 / 账户三档）；柱状图 = **统计**（分类占比 + 近 6 月趋势）。 | 复刻首页 header：左账本名胶囊 + 右 3 个 boxed 图标；三个圈 + 三条指引线分别标注 |
| 4 | 月份可以往回翻 | 琥珀卡右上的 `‹ ›` 换月份（**不能翻到未来**）；预算卡标题行的**铅笔**点了改本月预算，没设预算时点卡片本身也能设。 | 上：琥珀卡右上两个白色圆钮 `‹ ›`（圈注）；下：预算卡标题行 + 铅笔（圈注） |
| 5 | 三个藏起来的手势 | 日历上**长按某一天** → 直接记那天的账；月历**左右滑** → 翻月；流水行**向左滑** → 露出「删除」，**点了才删**。 | 三行 mini 示意：① 日历格 + 触碰图标 ② 月历 + 左右双向箭头 ③ 流水行左滑露出红块「删除」 |
| 6 | 还有两个页面的用法 | 资产页右上角的 **+** 加账户，**点账户行**就是编辑；报表页顶部 **明细 / 分类 / 账户** 换视角看同一批流水。 | 左：资产页 AppBar + `+`（圈注）+ 账户行（带 `›`）；右：报表页 `ToonSeg` 三档骨架 |
| 7 | 可以开始记账了 | 想再看一遍：**我的 → 新手引导**。 | 小猪 + `Sparkle` + 「我的 → 新手引导」示意条 |

- **进度指示**：7 个小圆点，当前页为品牌色实心 + 墨色描边，其余为 `Tok.line`。**可点跳页**（省得连点 6 次）。
- **底部按钮**：第 1–6 页 = `ToonButton(label: '下一步')`；第 7 页 = `ToonButton(label: '开始记账')`。
- **返回键语义**：不提供「上一页」按钮（可横向滑动回退），避免底部三按钮拥挤。

### 3.3 视觉规格

- 页面背景 `Tok.canvas`（暖白画布）；内容区固定宽 **288** 居中（窄于任何机型的可用宽度，平板/横屏不拉长）。
- 结构：`SafeArea` → 顶行（7 点进度 + 「跳过」，固定）→ `Expanded(PageView)`（每页内容可滚）→ 底部主按钮（固定）。
- **迷你示意图**（本批主要工作量）：
  - 外壳 `MiniScreen` = `ToonCard`（白底 + `Tok.bw` 墨色描边 + 硬阴影 + 圆角 `Tok.rLg`），内放简化版真实控件。
  - **高亮圈** `HighlightBox` = 品牌色 2px 圆角/圆形实线框 + `Tok.brandTint2` 40% 底 → 圈住目标控件。
  - **指引线** `Callout` = 2px 墨色折线 + 实心三角箭头（`CustomPainter`，约 30 行）+ 品牌浅底标签文字。
  - 迷你控件**复刻真实尺寸比例**（底栏高 68、图标 22、中央方块 54×48、header 图标 40×40），
    颜色与图标 `IconData` **与真实代码一致**（直接复用同一组常量/图标，不另造一套）。
- 不引图片资源（纯矢量）—— 免去多分辨率 assets 与后续 UI 改版同步成本。
- **矮屏 / 横屏**：**中间区（示意图 + 标题 + 正文）可滚动**，顶行与底部主按钮固定
  —— 矮视口下先把示意图挤成可滚内容，按钮始终可点（实测 800×600 视口下不溢出）。

---

## 4. 不做

- ❌ **不做遮罩高亮真实控件**（在真页面上挖洞 + 气泡）：需逐控件取真实坐标、跨 tab 切页、处理滚动/键盘边界，
  实现与真机走查成本显著更高（用户已裁定走全屏分页导览）。
- ❌ 不做「截真图」当示意图（纯矢量手绘，便于跟 UI 改版同步）。
- ❌ 不做自动跨页巡演（不自动帮用户切 tab / 打开弹层）。
- ❌ 不做多语言 / 不做分步骤强制（每页都能跳过）。
- ❌ **不动「我的 → 设置」那行灰显**（它承诺「主题 / 默认账户 / 货币单位」，属另一待办 F4）。
- ❌ 不加「重置引导」的开发入口；不提供「不再提示」开关（本来就是一次性）。
- ❌ 不引新依赖、**不动 schema**、不新增主题令牌、不加路由外的第二套导航。

---

## 5. 文件清单

| 文件 | 动作 |
|---|---|
| `lib/features/onboarding/onboarding_keys.dart` | **新增**：`kOnboardingDoneKey = 'onboarding_done'` + `kOnboardingDoneValue = '1'`（风格对齐 `kActiveBookKey` / `kSearchHistoryKey`） |
| `lib/features/onboarding/application/onboarding_prompt.dart` | **新增**：`onboardingPromptProvider`（§3.1 两个条件的判定） |
| `lib/features/onboarding/presentation/onboarding_page.dart` | **新增**：`OnboardingPage`（`PageView` + 进度点 + 跳过 / 下一步 / 开始记账 + `dispose` 落标记 + `Text.rich` 渲染 `**粗体**`） |
| `lib/features/onboarding/presentation/widgets/onboarding_slides.dart` | **新增**：`OnboardingSlide` 模型 + `parseEmphasis` / `emphasisSpans` + `kOnboardingSlides`（7 页文案） |
| `lib/features/onboarding/presentation/widgets/onboarding_art.dart` | **新增**：`MiniScreen` / `HighlightBox` / `Callout` 三个通用件 + 7 页各自的示意图组件 |
| `lib/core/providers/book_providers.dart` | **改**：`ActiveBookIdController` 加 `isFreshInstall`（§3.1 条件 2 的真源） |
| `lib/app.dart` | **改**：新增 `GoRoute('/onboarding')`（全屏，在 shell 之外 → 盖住底栏） |
| `lib/features/nav/presentation/app_shell.dart` | **改**：`AppShell` → `ConsumerStatefulWidget`，首帧后查 `onboardingPromptProvider` → 为 true 则 `push('/onboarding')` |
| `lib/features/profile/presentation/profile_page.dart` | **改**：条目卡**首位**插入可点条目「新手引导」（`分类管理` 补 `dashedTop: true`） |
| `test/helpers/pump_app.dart` | **改**：`pumpApp` 默认**预写** `onboarding_done`（= 既有 9 个文件全部按「已看过」跑，行为不变）+ 新增 `onboardingDone: false` 逃生口给首启用例 |
| `test/features/onboarding/onboarding_slides_test.dart` | **新增**：纯 `test()` —— 页数 = 7 / 标题顺序 / 标记键值与内容 / `parseEmphasis` 4 例 |
| `test/features/onboarding/onboarding_flow_test.dart` | **新增**：`testWidgets` —— 首启自动弹 / 翻页 / 末页按钮文案 / 完成 → 写标记 / 跳过 → 写标记 / 看过不再弹 / 老用户（已有账本）不弹 / 「我的」入口可 push |

**不改**：全部业务页面（引导只读）· `AppMetaRepository`（复用现成 `get`/`set`）· DB schema · 主题令牌 · `env.sh`。

---

## 6. 风险

| 风险 | 处置 |
|---|---|
| 首帧先闪一下首页再弹引导 | 用 `addPostFrameCallback` 不阻塞首帧；首页数据本来就异步加载，视觉上引导直接盖上去 |
| 读 KV 慢 → 用户已开始操作才弹 | 同一帧后即读，实测 1 次 KV 查询 <5ms；且只在未看过时弹 |
| 引导页被系统返回后标记没写上 → 每次都弹 | 标记收口在 `dispose()`（任何 pop 都会走到），不依赖 `PopScope`；写失败静默吞掉 |
| `dispose()` 里用 `ref` 抛错 | 仓储在字段初始化时 `ref.read` 取出留存 → `dispose` 只用仓储，不碰 `ref` |
| **既有 9 个 `pumpApp` 测试文件被首启弹窗打断**（内存库 = 全新安装 → 会弹） | `pumpApp` 默认预写 `onboarding_done`，既有用例零改动；只有首启专项用例显式传 `onboardingDone: false` |
| 小屏 / 横屏示意图被挤扁 | 中间区可滚 + 底部按钮固定；真机走查补一档矮视口验证不溢出 |
| 引导页的页面切换在 800×600 测试视口下 `find.text` 搜到非当前页 | `PageView` 默认 `cacheExtent = 0` → 只建当前页；断言用「当前页标题 `findsOneWidget`、他页标题 `findsNothing`」双向锁 |
| widget 测试里 `push` 到 shell 之外的路由 | 断言「引导页出现」+「pop 后回到首页」；不依赖 `push().then`（壳下不兑现） |
| 引导文案与真实 UI 脱节 | 文案里的按钮名 / 图标 / 手势写死在本 SPEC §3.2；后续改 UI 入口时**必须同步回看本 SPEC 与本页文案** |
| 与「首次使用验收」的既有 F3–F6 待办混淆 | 本批**不**顺手修 F3–F6（不扩范围） |

---

## 7. 签字

**2026-09-25 用户裁定（四项，全部确认）**：

1. **形式 = 全屏分页导览**（不做遮罩高亮真实控件、不做首页常驻提示卡）。
2. **覆盖范围 = 四项全要**：① 底栏中央按钮 + 首页三图标 ② 三处隐藏手势 ③ 翻月箭头 + 预算铅笔
   ④ 资产页 `+` 与账户行 + 报表三档 → 落成 **7 页**（§3.2）。
3. **重看入口 = 「我的」页新增「新手引导」条目**（不点亮现有「设置」灰行）。
4. **老用户不弹** —— 从旧包覆盖安装上来的用户**不做首启弹窗**，只在「我的 → 新手引导」主动查看。
   → 因此「该不该弹」需要区分全新安装与老用户，真源与实现见 §3.1。

**同批确认的技术载体**：首启弹层用 `GoRoute('/onboarding')` 独立全屏路由（不用 `showGeneralDialog`）
—— 「我的」页可直接 `push` 同一页、测试可直接 pump、「走查路径与手动入口完全一致」。

---

## 8. 实施记录（2026-09-25）

**实现**（提交 `02f9041`）

- 新增 `lib/features/onboarding/`：`onboarding_keys.dart`（`kOnboardingDoneKey` / `kOnboardingDoneValue`）、
  `application/onboarding_prompt.dart`（`onboardingPromptProvider`）、
  `presentation/onboarding_page.dart`（`PageView` + 7 点进度（可点）+ 跳过 + 下一步 / 开始记账 + `dispose` 落标记）、
  `presentation/widgets/onboarding_slides.dart`（`OnboardingSlide` + `parseEmphasis` / `emphasisSpans` + 7 页文案）、
  `presentation/widgets/onboarding_art.dart`（`MiniScreen` / `HighlightBox` / `Callout` + 7 页画面，全矢量）。
- `app.dart` 加 `/onboarding`；`app_shell.dart` → `ConsumerStatefulWidget` + 首帧后查一次（`_checkedOnboarding` 防重）
  失败静默；`book_providers.dart` 加 `isFreshInstall`；`profile_page.dart` 条目卡首位插「新手引导」
  （`分类管理` 补 `dashedTop: true`）。
- 布局：顶行（进度点 + 跳过）固定 / 中间 `PageView` 每页可滚 / 底部主按钮固定 —— 800×600 视口不溢出。

**门禁**

- `flutter analyze` 等效（`python tool/dart_analyze_fallback.py`）：
  - 本次新增文件单独跑（`lib/features/onboarding test/features/onboarding`）→ **`No issues found!`** ✅
    （含全部 lint：首轮报出的 1 个 `unused_import` + 14 个 `prefer_const_constructors` 已全部修掉）。
  - ⚠️ **全项目仍报 5 个 error**，全为 `D:\` / `d:\` 同文件双身份的**既有环境假阳性**，与本批无关 ——
    对照实验：未改动的 `lib/features/ledger` 单独作根跑即复现 3 个。
    详见 `CHANGELOG.md` §门禁备注；**待用户终端 `flutter analyze` 复核**。
- `python tool/dart_test_fallback.py test/features/onboarding/onboarding_slides_test.dart`
  → **passed=10 failed=0 skipped=0** ✅（纯 `test()` 部分本机可验）。
- **用户终端全量 `flutter test` → 400 passed / 0 skipped** ✅
  = `test()` **312** + `testWidgets` **88**（本批 **+17**：`test()` +10 / `testWidgets` +7）。
- **真机走查：D1–D10 全部通过、0 崩溃** ✅（MuMu 12 / 900×1600 @320dpi，AI 经 adb 全包）
  → 报告 `docs/acceptance-F7.14-onboarding.md`。
  重点项实测：① 全新安装首启自动弹；② 已看过冷启动不弹；
  ③ **老用户（有 `active_book_id`、无标记）不弹且不被误写标记**；④ **系统返回也写标记**；
  ⑤「我的 → 新手引导」可重看；⑥ 矮视口（逻辑 450×500）不溢出；
  ⑦ 引导前后业务数据完全一致（`0 tx / 1 acct / 15 cat`）。
  ⚠️ 走查踩坑：`uiautomator dump` 写到固定 `/sdcard/_ui.xml`，在 App 切换的瞬间会 `cat` 到**陈旧内容**
  —— 一度看着像「首启没弹」，曾误判为功能 bug。处置 = 换独立文件名落盘 + 截图交叉验证（已回写 skill）。

**版本**：已交付 —— 代码提交 `02f9041`、CHANGELOG 转正 `c5ea1b5`，
tag **`v0.7.14`**（tag 对象 `b3c08c2` / 提交 `c5ea1b5`）已推远端。
**回滚**：`git checkout v0.7.13`。
