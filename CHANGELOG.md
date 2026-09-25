# 变更日志

本项目变更记录格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

> **版本号规则（2026-09-23 起执行）**：迁移期直接拿 **F 阶段号当版本号** —— `v0.7.<N>` 对应 `F7.<N>`，
> 同阶段内的多批交付（如 F7.6 的 P1/P2/P3）**合并成一个版本**，批次写在 CHANGELOG 段落里。
> 每个版本一次：CHANGELOG 段落带版本号 → `git tag -a v0.7.<N> -m '…'` → `git push --tags`。
> **回滚**：`git checkout v0.7.5`（看/跑旧版）或 `git revert <commit>`（在 master 上撤某次改动）。
> 首个正式对外版本起改回常规语义化版本号（`v1.x`）。

| tag | 阶段 / 内容 | 里程碑提交 |
|---|---|---|
| `v0.7.1` | F7.1 日历页（月历标注 + 日账单 + 月份选择 + 按日期记账） | `c17abfd` |
| `v0.7.2` | F7.2 统计 · 报表页 | `0fa12fa` |
| `v0.7.3` | F7.3 预算实装（schema v2）+ 移除示例数据 | `de67377` |
| `v0.7.4` | F7.4 流水搜索（分类 / 备注 / 金额） | `c6b616e` |
| `v0.7.5` | F7.5 搜索浮层化 + 资产页（含真机走查） | `e06d23a` |
| `v0.7.6` | F7.6 卡通浅色视觉改版（P1 底座/首页/记一笔 · P2 日历/统计/资产 · P3 我的/账本/分类/导入/弹层/搜索） | 本段所在提交 |
| `v0.7.7` | F7.7 A 批 报表明细清单 `/reports`（含 A.0 记一笔选账户 + 4 处占位点亮）+ 首次使用验收 F1 阻断修复 | `2f6db4c` / `47e1bf6` |
| `v0.7.8` | F7.7 B 批 数据导出（流水 CSV + 备份 JSON，SAF 免权限；真机走查 AI 经 adb 全包完成） | 本段所在提交 |
| `v0.7.9` | F7.7 C 批 账户图标 / 颜色选择（schema v3）+ widget 测试视口修复 | 本段所在提交 |
| `v0.7.10` | F7.7 D 批 搜索增强（高亮 / 账户名 / 历史 / 时间区间）+ E 批 日历增强（长按记账 / 左右滑翻月） | 本段所在提交 |
| `v0.7.11` | F7.8 流水左滑删除（长按 → 左滑露出按钮；首页 / 日历日账单 / 搜索结果 3 处） | 本段所在提交 |
| `v0.7.12` | F7.9 记一笔双保存入口收敛（删顶部 + 底部吸底常驻）+ 启动图标 adaptive icon + `signingConfigs` 构建阻塞修复 | 本段所在提交 |

## [v0.7.12] — 2026-09-25 · F7.9 记一笔保存入口吸底常驻 + 启动图标 adaptive icon

> **门禁**：`flutter test` **372 passed / 0 skipped**（2026-09-25 用户终端全量；
> = `test()` **292** + `testWidgets` **80**，本批 **+1**）；`flutter analyze` 等效 **0 issue** ✅；
> 真机走查（MuMu 12 / 900×1600 @320dpi，AI 经 adb 全包）**通过、0 崩溃** →
> `docs/acceptance-F7.9-record-sticky-save.md`。**回滚**：`git checkout v0.7.11`。
> **本版含两个独立需求** —— A = F7.9 记一笔双保存入口收敛；B = 启动图标补 adaptive icon；
> 另有 1 处**构建阻塞修复**（`signingConfigs` 声明顺序，连 `./gradlew assembleDebug` 都挂）。

### A · F7.9 记一笔保存入口吸底常驻

> **诉求**：记一笔页**顶部 AppBar 有「保存」、底部又有主按钮「记一笔」** —— 两个保存入口。
> 造型来源是原型 1:1 复刻（`screens.js` 两处挂同一动作 `data-act="save-record"`），
> F7.7 P5 又为「大屏 / 横屏下底部按钮被折叠到视口外」加了顶部兜底 → 用户要求收敛成一处。
> **裁定（2026-09-25）**：**底部主按钮改吸底常驻 + 删掉顶部入口**（否掉「去底部、只留顶部」）。
> **口径**：吸底栏放 body 内 `Column(Expanded(滚动区) + 吸底栏)` —— ⚠️ **不能用 `Scaffold.bottomNavigationBar`**：
> 它按 `size.height - h` 贴**屏幕**底、**不随键盘上移**，键盘弹起会被盖住；body 才会被 `viewInsets.bottom` 压缩。
> 顶部墨色描边（`Tok.ink` / `Tok.bw`）与 AppBar 底边对称。
> **走查覆盖**：D1 无顶部入口 / D2 未滚动即在视口内 / D3 滚动后位置不变 / D5 保存链路写入成功 /
> D6 编辑态文案「保存修改」/ D8 0 崩溃；**D4 键盘项**受 MuMu 无软键盘限制，改矮视口做等价验证。
> **零新依赖、不动 schema（仍 v3）**。

#### 变更

- `lib/features/record/presentation/record_page.dart`：删除 AppBar `actions` 的「保存」；
  `body` 改为 `Column(Expanded(滚动区) + 吸底栏)`，滚动区 bottom padding `24 → 16`，
  提示文案留在滚动区末尾（不进吸底栏）。
- 测试口径同步（**吸底按钮是滚动区的兄弟节点、不在 `Scrollable` 内** → `tester.ensureVisible`
  会因 `Scrollable.of` 返回 null 直接抛错）：删 3 处 `ensureVisible`（`widget_test` ×2、
  `calendar_page_test` ×1）；`record_account_test` 的 `_tapSave` 改点吸底按钮。

#### 新增

- `docs/SPEC-F7.9-record-sticky-save.md`（含 **SPEC 前提修正**记录：初稿的 `bottomNavigationBar`
  方案不成立）+ `docs/acceptance-F7.9-record-sticky-save.md`（走查报告）。
- `test/features/record/record_save_entry_test.dart` **重写**为矮视口（逻辑 800×400）口径：
  ① AppBar 与全页无「保存」；② 吸底按钮唯一且在视口内；③ 滚动 400px 后按钮 y 不变；
  ④ 吸底按钮走同一套校验（金额空 → 「请输入金额」）。

#### 修复

- `test/features/ledger/home_empty_state_test.dart`（**首轮回归失败**）：仍断言
  `find.widgetWithText(AppBar, '保存')`，而该入口已删 → 改判据为「AppBar 标题 `记一笔`」+
  「AppBar 无 `保存`」+「吸底 `ToonButton` 在位」（用 `ToonButton` 定位可避开首页空态 cta 与底栏中央
  Tooltip，与下层路由是否仍在树上无关）。
- `pubspec.yaml`：`dev_dependencies` 按字母序重排（`sort_pub_dependencies` 1 条 info）。

### B · 启动图标（adaptive icon）

> **背景**：`flutter_launcher_icons` 只产 legacy 的 `mipmap-*/ic_launcher.png`，
> **默认不产 adaptive icon**（`mipmap-anydpi-v26/ic_launcher.xml`）→ Android 8.0+（API 26+）
> 拿不到 adaptive 资源就回落 legacy 路径，由系统给图标**套白底 + 圆形遮罩**（真机上一圈白边）。
> 本次补齐 adaptive 三层资源；同时把 `flutter_launcher_icons` 从 `dependencies` 移回
> `dev_dependencies`（构建期工具，重复声明会让 `pubspec.lock` 标成 `direct main`）。
> **不动 schema、零新依赖**（生成脚本纯 Python 标准库 —— 本机 `dart run` 起不了管道子进程，见 `HANDOFF.md`）。
> **验证**：`python tool/inspect_icons.py` 全绿 + `python tool/check_pubspec.py` 全绿 +
> 构建 debug APK 成功（资源过 aapt2）+ 装机后 MuMu 桌面图标 = 黄底圆角方 + 「记账」，**无白底白圈**。
> 构建 debug APK 成功（资源过 aapt2）+ 装机后 MuMu 桌面图标 = 黄底圆角方 + 「记账」，**无白底白圈**。

#### 新增

- **adaptive icon 三层资源**：`mipmap-anydpi-v26/ic_launcher.xml`（声明）+
  `values/ic_launcher_background.xml`（背景色 `#FFD81B`，取自源图主色）+
  5 个 `mipmap-<density>/ic_launcher_foreground.png`（108/162/216/324/432）。
- **前景源图** `assets/icon/app_icon_foreground.png`（1024²，透明底 + 图形缩进 66% 安全区），
  连同 `pubspec.yaml` 的 `adaptive_icon_background` / `adaptive_icon_foreground` 一起入库 ——
  以后重跑 `dart run flutter_launcher_icons` 能原样复现。

#### 新增（工具 · `tool/`）

- `png_util.py` —— 纯标准库 PNG 编解码 + 面积平均缩放（沙箱无 Pillow）。
- `gen_launcher_icons.py` —— 生成上述 adaptive 资源；`--probe` 看源图特征，
  默认还会出**圆形遮罩合成预览**（`.workbuddy/qa-icons/`）供肉眼核验安全区；
  路径已参数化（`--root` / `--source` / `--fg-source` / `--res` / `--preview`）→ 可项目外调用，
  已固化为用户级技能 `~/.workbuddy/skills/flutter-adaptive-icon-offline`。
- `inspect_icons.py` —— 图标资源体检（源图 / legacy / 前景层的像素尺寸 + adaptive 资源齐备度）。
- `check_pubspec.py` —— `pubspec.yaml` / `pubspec.lock` 一致性体检（YAML 卫生 +
  构建期工具不得待在 `dependencies` + lock 的 `dependency` 字段与声明位置一致 + 配置引用的图片存在）。
  本机跑不了 `flutter pub get`，用它补这个缺口。

#### 修复（构建阻塞）

- `android/app/build.gradle.kts`：`signingConfigs { }` 必须声明在 `buildTypes { }` **之前** ——
  `buildTypes.release { }` 的 lambda 在**配置阶段立即执行**，其中 `signingConfigs.getByName("release")`
  会在注册前求值 → 报 `SigningConfig with name 'release' not found.`。
  **它连 `./gradlew assembleDebug` 都挂**（与 debug/release 无关）。同时：无 `key.properties` 时
  回退 debug 签名（保证 clone 仓库、未配签名的机器也能出包）+ 修 `create("release")` 缩进。
- `.gitignore`：补 `key.properties` 兜底规则 + `__pycache__/` / `*.pyc`。

## [v0.7.11] — 2026-09-25 · F7.8 流水左滑删除

> **诉求**：删除入口原是**长按**（无视觉提示，且与日历页「长按空格子记一笔」语义撞车）→ 用户要求改为**左滑**。
> **三项裁定（2026-09-25，详见 `docs/SPEC-F7.8-swipe-delete.md` §7）**：
> ① **长按取消**、只留左滑；② **滑出红色「删除」按钮 → 点按钮才删**（不采用「滑走即删」）；
> ③ 作用范围 = **首页 + 日历日账单 + 搜索结果** 3 处（报表页流水行仍只读）。
> **不动 schema、零新依赖**（手写滑动件，不引 `flutter_slidable`）。
>
> **门禁全闭合**：`flutter analyze` 等效 **0 issue** ✅；`flutter test` **371 passed / 0 skipped**
> （用户终端全量，2026-09-25；= `test()` **292** + `testWidgets` **79**，本批新增 **+10**）。
> **真机走查（MuMu 12）由 AI 经 adb 全包完成** ✅：左滑行内金额节点 x `450 → 363` / 点动作区弹
> 「删除这笔」/ 取消回弹且数据不动 / 多行单开（滑第二行时第一行回 450）/ 点已展开行只收起不跳编辑 /
> 竖向滚动与月历翻月不受影响 / **报表页左滑零位移、无「删除」节点**（只读保持）→ `logcat -b crash`
> **0 崩溃**，记录见 `docs/acceptance-F7.8-swipe-delete.md`。
> 标签日 = 2026-09-25；**回滚**：`git checkout v0.7.10`。
>
> ⚠️ 走查抓到 1 个**只有真机能发现的视觉 bug**（见「修复」段）：未滑开时红色动作区透过行露出来。

### 新增

- **左滑露出删除按钮**：新通用件 `lib/features/ledger/presentation/widgets/swipe_action_row.dart`
  （`SwipeActionRow` + 纯函数 `resolveSwipeOpen`）。行内容**只向左移**，右侧钉一个 84px 红色动作区
  （白垃圾桶图标 + 「删除」）；松手按「行程 ≥ 45% **或** 向左甩 ≥ 350 px/s」吸附开合，动画 160 ms。
- **单开协调**：同一列表同时只允许一行展开 —— 滑开另一行、或点已展开的行任意处 → 当前行收起。
- **3 处接入**：首页「本月账单」（`TxGroupList`）、日历页选中日账单（`_SelectedDaySection`）、
  搜索浮层结果（走 `TxGroupList`）。

### 修复

- **未滑开时红色动作区透过行露出来**（真机走查抓到，**只有真机能发现**）：`TxTile` 自身没有背景色
  （行的白由外层白卡 `Container(decoration: cardDeco())` 提供），而 `SwipeActionRow` 的 `Stack` 底层
  钉着红色动作区 → 透明的行把红底直接透出来，视觉上像「已经滑开了」。
  修法：`Transform.translate` 内给行包一层 `ColoredBox(color: Tok.paper)`（`swipe_action_row.dart`）。
  widget 测试断言的是结构 / 行为，看不出「颜色透过」，故这条只能靠真机走查。

### 变更

- **长按删除移除**：`TxTile` 不再有 `onLongPress`（长按**保留**给日历格子「记这一天的账」，不受影响）。
- 删除确认框**不变**：仍走既有 `confirmDeleteTx`（「删除这笔」）—— 取消 = 行回弹、数据不动。

### 测试

- **改 2 例**（原长按口径 → 左滑口径）：`test/widget_test.dart`「左滑删除 → 列表消失回到空态」、
  `test/features/search/search_overlay_test.dart`「左滑结果可删」。确认框里的「删除」改用
  `find.widgetWithText(ToonButton, '删除')` 区分（动作区的那个是裸 `Text`）。
- **新增 10 例**（`test/features/ledger/swipe_action_test.dart`）：`resolveSwipeOpen` 纯函数 5
  （行程不足 / 过半 / 甩速 / 反向 / 宽度为 0）+ 行行为 5（左滑触发 action 并自动收起 /
  未滑开点行走 child onTap / 滑开后点行收起且不跳编辑 / 多行只开一行 / `enabled=false` 纯展示）。

## [v0.7.10] — 2026-09-25 · F7.7 D 批（搜索增强）+ E 批（日历增强）

> **门禁全闭合**：`flutter analyze` 等效 **0 issue** ✅；`flutter test` **361 passed / 0 skipped**
> （用户终端全量，2026-09-25；= `test()` 287 + `testWidgets` 74，本批新增 **+32**）。
> **真机走查（MuMu 12）由 AI 经 adb 全包完成** ✅：高亮暖黄底 / 账户名命中 / 历史 chip 一点即搜 /
> 只点「本月」= `共 5 笔 支出 286.88 · 本月` / 长按 9月10日 → 记一笔页日期 `2026年9月10日` /
> 左滑 9月→10月、右滑回退且日列表同步、竖向未误翻月 → `logcat -b crash` **0 崩溃**，
> 记录见 `docs/acceptance-F7.7-DE.md`。
> 标签日 = 2026-09-25；**回滚**：`git checkout v0.7.9`。
>
> **本批不动 schema**（⚠️ 又一处 SPEC 前提修正）：§D.3 原计划新建 `app_meta` KV 表并把 schema
> 推到 v4，但 `schema_meta`（`key` + `value`）本来就是 PRD 登记的 KV 元数据表，
> `docs/SPEC-F7.3-budget.md` §3 也把它列为「零迁移」备选 → **复用现有表，schema 仍是 v3**。
> 另一处：§E.1 写「`/record?date=YYYY-MM-DD`」，实际约定是**毫秒**（`app.dart` 里
> `int.tryParse(queryParameters['date'])` → `occurredAtMs`）→ 按毫秒传。
> ⚠️ 走查抓到 1 个**真 bug**（搜索快照过期，见「修复」段）——D 批新增的「账户名命中」正好踩在它上面。

### 新增

- **D 批 · 搜索增强**（入口与关闭手势不变）
  - **关键词高亮**：命中的分类名 / 备注 / **账户名** / 金额子串标 `brandTint2` 底色（`TxTile` 可选参数）。
  - **账户名命中**：新增一路命中口径，搜「招行」「支付宝」也能搜到流水（账户查不到回退空串，不会误命中）。
  - **搜索历史**：最近 10 条关键词，落在**已存在**的 `schema_meta` KV（`search_history`，JSON 容错解析）；
    引导态下方 `ToonChip` 一点即搜，可「清空历史」；记录时机 = 回车提交 / 点历史词 / 点开某条结果。
  - **时间区间**：类型 chips 下**独立一行**「时间：全部 / 本月 / 近3月」（单选，默认全部）；
    区间与关键词、类型词取**交集**，只选区间也出结果（结果条标「· 本月」；空态点明区间，避免误判搜不到）。
- **E 批 · 日历增强**
  - **长按日历格子 → 直接记这一天的账**（`/record?date=<毫秒>`，并顺带把那天选中，回来即见新流水）。
  - **左右滑动翻月**：阈值 = 1/3 格宽，左滑下一个月、右滑上一个月；年月与下方日列表同源自动同步。
    只注册**横向** drag → 竖向滚动仍归外层（不能出现「上下滚不动」）。

### 变更

- 搜索输入框 hint 与引导文案：「分类、备注或金额」→「分类、**账户**、备注或金额」；日历空态提示改为「长按日历里任意一天，也能直接记这一天的账」。

### 修复

- **搜索结果是过期快照**（真机走查抓到，**F7.4 起就存在**的老问题）：`searchProvider` 是常驻
  provider（非 autoDispose，浮层关掉再打开不重建），原先没有任何失效信号 → **「刚加完账户 /
  刚记一笔」后回搜索是搜不到的**（实测：新账户名、新流水金额都命中不到，杀进程重启 App 才出现；
  走查中搜新账户 `QABank` 与新账 `66` 均落空，重启后立刻命中，据此定位）。
  修法：`SearchController.build()` 里 `ref.watch(dataEpochProvider)` —— 复用项目既有的
  「写操作版本号」（所有写操作成功后都会 bump），一处接入即自动作废重取，不必在 N 个写入口补
  `refresh()`。回归测试 `test/features/search/search_freshness_test.dart`（去掉该 watch 即失败，已验证）。

### 测试

- 新增 **+32**（`test()` +24 / `testWidgets` +8）：`search_history_test` 9、
  `search_query_test` +14（账户名命中 / 区间窗口 / 高亮区间）、`search_freshness_test` 1、
  `search_overlay_test` +5、`calendar_page_test` +3（长按带日期 / 左右滑翻月 / 竖向不吃手势）。
- 全量 **361**（287 `test()` + 74 `testWidgets`）。

## [v0.7.9] — 2026-09-24 · F7.7 C 批 账户图标 / 颜色选择

> **门禁全闭合**：`flutter analyze` 等效 **0 issue**；`flutter test` **329 passed / 0 skipped**
> （用户终端全量，2026-09-24；= `test()` 263 + `testWidgets` 66，其中 C 批新增纯测试 **+14**）。
> **真机走查（MuMu 12）由 AI 经 adb 全包完成**：v0.7.8 老库**覆盖安装**验迁移 —— 老数据 ¥286.88 原样、
> 新列落默认空串；改图标（存钱罐）+ 改颜色（粉红）→ 头像即时变更 → 重启后仍持久 ✅ → logcat 0 崩溃。
> **schema v2 → v3**：`accounts` 新增 `icon` / `color`（TEXT NOT NULL DEFAULT ''）。
> ⚠️ SPEC §C.1 前提有误（两列原以为已存在，实际在 books/categories 上）→ 本批带迁移。
> 标签日 = 2026-09-24；回滚：`git checkout v0.7.8`。

### 新增

- 账户表单（新增 / 编辑）加「图标」「颜色」两块：8 个语义图标 + 8 色（取 `Tok.pie` 前 8），
  均可「跟随账户类型」（存空串，默认）；新增账户默认跟随类型。
- 资产页账户头像：自选图标优先；自选色做底色（前景墨色）；空串 / 非法值行为与老版本完全一致。
- `schema v3`：`accounts.icon` / `accounts.color` 迁移（`ALTER TABLE ADD COLUMN`，带存在性防御）。

### 变更
- 我的页 `_BrandTip` 版本角标 `v0.7.8` → `v0.7.9`（等宽字符串替换，无布局变化）。

### 修复
- 账户表单「跟随类型」chip 在 `Wrap` 宽松约束下被 `Container.alignment` 撑满整行（真机走查发现）→ 去掉 `alignment`，靠 padding 收紧。
- widget 测试适配加高后的账户表单（`assets_page_test` 3 例）：「删除账户」折到折线以下 → tap 前 `ensureVisible`；
  「点遮罩关弹窗」用例改**竖屏视口**（默认 800×600 太矮，弹窗顶边会贴到 y=0 使遮罩无缝可点），并加 `sheet.top > 100` 几何硬断言。

## [v0.7.8] — 2026-09-23 · F7.7 B 批 数据导出

> **门禁全闭合**：`flutter analyze` 等效 **0 issue**；`flutter test` **315 passed / 0 skipped**
> （用户终端全量，2026-09-23 傍晚；= test() 249 + testWidgets 66，其中 B 批新增纯 31 + widget 3）；
> **真机走查（MuMu 12）由 AI 经 adb 全包完成、无阻断**——`gradlew assembleDebug` 直连构建绕开本机 Dart 231
> （已验 kernel_blob 含 B 批代码），CSV / JSON 两路径 + SnackBar + 取消静默 + 报表回归全过。
> 标签日 = 2026-09-23；回滚：`git checkout v0.7.7`。

### 新增
- **数据导出**：「我的 → 数据导出」→ 底部弹层，两条路径
  - **导出流水 CSV**：表头 `日期,类型,金额,分类,账户,备注,来源`；日期 `YYYY-MM-DD HH:mm`；金额元两位小数无符号；RFC4180 转义 + UTF-8 BOM + CRLF（Excel 直开不乱码）；转账行分类留空；来源列原样英文。
  - **导出备份 JSON**：`schemaVersion 2`，`{book, accounts, categories, transactions, budgets}` 全量，金额整数分（可无损还原）；不导软删。
  - 保存走系统 SAF（`file_picker.saveFile`，**免存储权限**）；用户取消静默；成功 SnackBar「已导出 N 笔到 {文件名}」。
- 预算仓储补只读 `listByBook(bookId)`（备份 JSON 取数缺口，不改 schema）。

### 变更
- 我的页品牌提示卡 `_BrandTip` 文案更新：「下一站：数据导出 / Backlog」→「已覆盖：…→ 数据导出 / v0.7.8」。

## [v0.7.7] — 2026-09-23 · F7.7 A 批 报表明细清单 + 首次使用验收（F1 阻断修复）

> **门禁全闭合**：`flutter analyze` 0 issue（本机等效手段 `python tool/dart_analyze_fallback.py` → `No issues found!`）；
> `flutter test` 整个套件全部通过（用户在自建终端跑，预期 **289 passed / 0 skipped**）；
> **真机走查（MuMu 12 / 900×1600 / 320dpi）由用户执行、报「通过、无阻断」**。
> 标签日 = 2026-09-23；回滚：`git checkout v0.7.6`。

### 新增 — F7.7 A 批 · 报表明细清单 `/reports`（2026-09-23）

- **范围**：`docs/SPEC-F7.7-backlog.md` §A（**A 批已签字**：A.0 前置做；D.5 拼音 / E.5 农历不做；
  报表页流水行由用户裁定为**只读不可点**，按 A.4）。
- **A.0 前置 —— 记一笔支持选账户**：`record_page.dart` 原先写死 `accounts.first.id`，用户无法选账户
  （不改这条，「按账户报表」永远只有一行）。现加第 4 个 `ToonField`「账户」+ 底部弹层
  `showAccountPicker()`（抓手 + `ToonAvatar` 行列表 + 选中对勾）；**默认仍是列表首个账户**（老行为不变）。
  选中的账户若在编辑态已被软删，自动退回首个账户。
- **新页 `/reports`**：AppBar「报表」+ 右侧月份切换（`‹ 2026年9月 ›`，未来月禁用）；
  `ToonSeg` 三档 **明细 · 分类 · 账户**；**独立记月份**（翻月不带动首页 / 日历 / 统计）。
- **4 处「报表（建设中）」占位全部点亮**：首页 header「报表」→ **分类档**；
  首页「全部账单 ›」→ **明细档**（文案不变）；日历页 header → **明细档 + 月份对齐日历页**；
  月份选择页 header → **明细档 + 月份对齐该页**。
- **口径**：取数用 `transactionRepository.listByMonth()`（与首页 / 日历 / 统计同一句 SQL）；
  分类档分支出 / 收入两段（复用 `categoryBreakdown` 口径）+ 转账单列一段；
  账户档按 `account_id` 聚合支出 / 收入 / 转账 / 笔数；已软删账户或空 `accountId` 归「其他账户」。
- **明细档**：按日倒序分组，组头「今天 / 昨天 / M月D日 周X · N 笔 · 支出 ¥x」。
- **空态**：虚线圆 + `PigMascot` + 「这个月还没有记账」+ 「去记一笔」。
- **展示限制**：每展开组最多 200 行 + 尾注（与搜索浮层同一做法）。
- **只读改造**：`TxTile` 的 `onTap` / `onLongPress` 改为可空（空 = 只读行），新增 `neutral`（转账行配色）；
  首页 / 日历 / 搜索三处既有调用点行为不变。
- **文档**：`docs/SPEC-F7.7-backlog.md` §F 签字表 + §G 实施记录已回写。

### 修复 + 验收 — 首次使用验收（F7.7-a，2026-09-23）

- **修复（阻断级）报表页不随写操作刷新**：`reportsProvider` 是**常驻** provider，且 `/record` 是 push 在
  报表页**上面**的 → 报表页 State 与 provider 都存活、不重建；而 `ReportsController.refresh()`
  （注释写着「记一笔 / 删除后刷新用」）**全库零调用** —— 5 个写点都只刷 ledger / calendar / stats。
  后果：新用户顺着报表空态「去记一笔」记完第一笔，**返回报表仍是「这个月还没有记账」**（三档全空）。
  现改为 `ReportsController.build()` 里 `ref.listen(dataEpochProvider) → refresh()`：一处覆盖全部写点，
  且**保留**用户当前档位与月份（不用 `watch` —— `watch` 会让 build 重跑、把月份与档位重置回
  「当月 + 明细」，等于吞掉 SPEC §A.2「报表页独立记月份」）。
- **新增测试 2 例**（`reports_page_test.dart` 7 → 9）：空月写账后报表自动刷新且保留档位；翻月后写账仍停在原月。
- **新增工具 `tool/data_layer_probe.py` + `tool/data_layer_probe.dart`**：`flutter test` 不可用时的数据层实跑 ——
  把 `lib/` 复制到 `.dart_tool/` 下的临时包、把 `database.dart` 的 drift_flutter 换成内存库，
  在**纯 Dart VM** 里用真实仓储 + 真实聚合代码跑「冷启动 → 记第一笔 → 首页汇总 → 报表三档 → 边界」，
  **13/13 断言通过**（内存库，不碰任何真实数据）。
- **验收报告**：`docs/acceptance-first-run.md`（新建）。结论：D2 运行前缺项通过（A 类前置 0）、
  D5 不通过（8 处 `加载失败：$e` 无重试）、D6 部分（即上面的阻断项）；另登记 F2（首页报表入口不带月份，
  **待裁定**）/ F4（「设置」副标题承诺未实现项）/ F5（「全部账单」入口 vs「报表」标题）/ F6（记一笔页返回丢输入）。
- **文档修正**：A 批新增用例实为 **18** 例（9 纯函数 + 7 widget + 2 A.0），此前文档写「+20（11+7+2）」有误。
  全仓静态计数 **289** = 基线 269 + A 批 18 + 本次 2 → 门禁预期仍是 **289 passed / 0 skipped**（数字巧合一致）。

### 修复 — 首轮 `flutter test` 反馈（A 批 + F7.7-a，2026-09-23）

> 用户在自己的终端跑通了 `flutter test`（本机沙箱仍被 `CreateFile failed 231` 阻塞），报回 4 个失败用例。
> 逐条定位后：**3 例是测试自身写法问题（已修）**，**1 例无法复现（判定环境 / 缓存，待复跑）**。

- **`record_account_test.dart` 两例（A.0 选账户）** —— 测试写法错误：`tester.tap(find.widgetWithText(AppBar, '保存'))`
  命中的是 **AppBar 自身**，`tap` 取它的**中心点**（标题区），根本点不到右上角那个按钮；`warnIfMissed`
  也不会警告（中心点确实落在 AppBar 内）→ **静默不保存**，库里始终 0 条 → `rows.length` 断言失败。
  改为点按钮里的那段 `Text`（`find.text('保存')`，与既有 `record_save_entry_test.dart` 同款），
  收敛为 `_tapSave()` 助手并把这个坑写进注释。
- **`reports_page_test.dart`「转账单列一段（不计入支出 / 收入）」** —— 目标落在**绘制区之外**：
  `SliverMultiBoxAdaptorElement.debugVisitOnstageChildren`（`packages/flutter/lib/src/widgets/sliver.dart:1289`）
  **只把「落在绘制区内」的子项算 onstage**，而 finder 默认 `skipOffstage: true` → 转账段在分类档最下面，
  800×600 的默认测试视口里正好卡在边缘（分类档内容高度与视口只差几像素）→ `find.text('转账')` 搜不到。
  改为先 `scrollUntilVisible(find.text('转账', skipOffstage: false), 200)` 再断言，
  结果不再依赖字号 / 间距的微小变化。
- **`bill_decode_test.dart`「GBK 字节回退解码不乱码」** —— **未能复现**：用纯 Dart VM 直接跑**真实**
  `decodeBillBytes(<int>[0xd6, 0xd0, 0xce, 0xc4])` → `encoding=gbk`、`text=中文`（`codeUnits=[20013, 25991]`），
  断言逐条成立；同文件的「混合内容（GBK 中文 + ASCII）」用的是**同样 4 个 GBK 字节**且未出现在失败列表。
  在 `gbk_codec` 锁 0.4.0（+ `dependency_overrides`，sha256 固定）的当前状态下该用例**不可能失败**。
  → 建议 `flutter clean && flutter pub get` 后复跑并回贴失败原文。

### 修复 + 工具 — `flutter test` 等效门禁 + `real_bills_test` 加载期加固（2026-09-23）

- **新增 `tool/dart_test_fallback.py`** —— `flutter test` 的等效替代，**推翻此前「本机无解」的结论**：
  `flutter test` 本体就是 flutter_tools 起两个**原生子进程**（`dartaotruntime + frontend_server_aot.dart.snapshot`
  编译测试文件为 dill → `<engine>/windows-x64/flutter_tester.exe <dill>` 执行），两者都能被 Python
  `subprocess` 直接启动 → **绕开本机命名管道 231**。编译 / 引导文件 / tester 三处参数一律抄 flutter_tools 源码。
  **实测全量 35 文件：纯 `test()` 226 例全绿 / 0 失败 / 0 跳过**（约 15min；与静态计数自洽：`testWidgets` 63 + 226 = **289**）。
  ⚠️ **边界**：`testWidgets` 跑不了（`AutomatedTestWidgetsFlutterBinding` 需要真运行器驱动帧）
  → 含 widget 的文件报「未跑完」而**不会假绿**（判绿要求终态汇总行）。**63 个 widget 用例仍需用户终端跑。**
- **修 `test/features/import/real_bills_test.dart`**：用户复跑时报 `loading <路径>`（= 加载失败）。
  三条独立证据（编译干净 / `main()` 体单独跑数字与断言全对（含 `--enable-asserts`）/ 真实 `flutter_tester`
  直接加载 **`+8` 全过**）证明**功能无问题**；唯一可疑点：它是全仓**唯一在加载期做同步 IO + 解析**的文件 ——
  flutter_tools 生成的 listener 会把 `main()` 的异常转成 `IsolateSpawnException`，于是整个文件只剩一句「加载失败」。
  加固：`main()` 里**零 IO** —— 改 `RealBill`（懒读 + 懒解析 + `on Exception` 降级）+ `markTestSkipped`，
  缺件 / 读不出 / 解析失败**只跳过该例**并给出可读原因。复验 **`+8-0~0` 全绿**。
- **文档**：`docs/SPEC-F7.7-backlog.md` §G 补「第二轮反馈」与工具说明；`HANDOFF.md` 未解决问题第 1 条改写
  （`flutter test` 本机自查 + 用户终端复跑）、盲区防护新增 2 条（加载期 IO / `testWidgets` 假绿）。
- **门禁闭合（2026-09-23 下午）**：用户在**自己的 Git Bash 终端**跑 `flutter test` → **整个套件全部通过**
  （预期 **289 passed / 0 skipped** = 基线 269 + A 批 18 + 修 F1 的 2 例），
  首轮报回的 3 个失败用例与第二轮的 `loading` 失败**均已修且未再复现**。
  → **`flutter analyze` + `flutter test` 两条门禁全部闭合**；**仅剩真机走查**（故本段暂留 `[Unreleased]`）。

### 已知环境阻塞 — 本机（A 机）Dart 无法创建子进程（2026-09-23）

- 现象：一切 `flutter` / `dart` 子进程启动失败 → `ProcessException: 所有的管道范例都在使用中
  (CreateFile failed 231)`（`runtime/bin/process_win.cc:744`）。受影响：`flutter analyze`、
  `flutter test`、`dart analyze`、`dart pub get`、`dart run build_runner`。
- 根因（已定位到 Win32 调用级）：Dart 在 Windows 上用命名管道做 stdio，先
  `CreateNamedPipe(PIPE_ACCESS_OUTBOUND | OVERLAPPED, nMaxInstances=1)` 再
  `CreateFileW(pipe, GENERIC_READ, ...)`；本机第二步恒返回 **ERROR_PIPE_BUSY (231)**，
  而 stdin 是第一个建的管道 → **凡需要管道 stdio 的 spawn 立刻死**。复现矩阵（Python ctypes 直调 Win32）：
  只读语义的管道客户端打开被拒，`GENERIC_READ|GENERIC_WRITE` 或 `PIPE_ACCESS_INBOUND`+`GENERIC_WRITE` 正常。
  纯主机行为，与项目代码无关。
  **边界（2026-09-23 实测）**：`ProcessStartMode.inheritStdio` / `detached` 不建管道、**可用**；
  `normal` / `Process.runSync` 不可用。
- **`flutter analyze` 已用等效手段达成**：`python tool/dart_analyze_fallback.py` →
  **`No issues found!`**（全项目 19s，退出码 0）。原理：`dart analyze` 本身就是
  「起 `analysis_server_aot.dart.snapshot` 子进程 + Dart 原生协议」，本脚本用 Python 起**同一个 snapshot**、
  喂**同一套 `analysis_options.yaml`**，故口径一致（含 lint）。已用探针文件校准（能正确报出
  `prefer_single_quotes` / `prefer_const_declarations`），确认 lint 规则**在线**；
  服务器对干净文件也推空数组，故「0 诊断」无歧义。
- **`flutter test` 也已用等效手段跑通**：`python tool/dart_test_fallback.py`（Python 起 `frontend_server`
  编译 + `flutter_tester.exe` 执行）→ **纯 `test()` 226 例全绿 / 0 失败 / 0 跳过**。
  ⚠️ 但 **63 个 `testWidgets` 用例跑不了**（该封装喂不了真运行器）→ 这一半仍需用户在自己终端跑。
- **仍跑不了**：真机走查（构建链路是多层 spawn：`flutter_tools` → Gradle → 插件里的 `dart`，
  `inheritStdio` 包装器只救第一层）。
- 解除方式见 `HANDOFF.md`「未解决问题」；协议三坑见 `docs/SPEC-F7.7-backlog.md` §G。

## [v0.7.6] — 2026-09-23 · F7.6 卡通浅色视觉改版（P1 + P2 + P3）

> 三批交付合成本版本：P1 主题底座 / 底栏 / 首页 / 记一笔 · P2 日历 / 统计 / 资产 ·
> P3 我的 / 账本 / 分类 / 导入 / 弹层 / 搜索浮层。细分批次见下面各段。

### 新增 — F7.6 P3 卡通视觉改版（我的 / 账本 / 分类 / 导入 / 全部弹层）（2026-09-23）

- **范围**：`docs/SPEC-F7.6-cartoon-ui.md` 第 3 批（末批）。我的页、账本管理、分类管理、
  导入三步、分类/日期/预算/账户四个弹层、搜索浮层、资产页空态、日历留白微调。
- **我的页**：重写为头像卡（品牌圆角方块 + 小猪）+ 4 条目卡（描边图标方块 / 虚线分隔 /
  未实现项「建设中」）+ 品牌提示卡。
- **账本管理**：FAB → AppBar 描边方块按钮；账本行改字母头像 + 选中「品牌浅底 + 墨色描边 + 硬阴影 + 对勾」。
- **分类管理**：`SegmentedButton` → `ToonSeg`；字母头像（支出红 / 收入绿）+ 预置标记。
- **导入**：报告从 `AlertDialog` 改成**第 3 步页面** —— 步骤条（虚线连接 / 完成打勾）+ 虚线投放区 +
  自定义勾选行（可单条取消并联动计数）+ 报告卡（42px 大数字 + 虚线 kv 列表）。
- **搜索浮层**：chips → `ToonChip`、结果条 → `ToonCard`、引导态与无结果态重写（小猪 + 「清空输入」）。
- **日期弹层（新增）**：卡通底部弹层 + `MonthGrid.maxDate` 参数（晚于今天灰显 0.3 且不可点），
  记一笔的日期字段改走它，堵掉「记未来的账」。
- **预算弹层**：重写为抓手 + ¥ 描边输入框（内嵌清空）+ 预设 `ToonChip` + linkbtn 删除预算 + `ToonButton`。
- **账户弹层（P3 走查时补做）**：P2 只对它做了取色，结构仍是 Material。本次补齐抓手 + 副标题 +
  小标 + 墨色描边裸输入框 + 类型改 6 个 `ToonChip` + 当前余额 + **红底流水提示条** + `ToonButton`。
- **资产页**：空态改卡通（虚线圆 + 小猪 + `ToonButton`）；AppBar `+` 换 `ToonIconButton`；错误态换 `ToonButton`。
- **令牌**：新增 `redInk`（原型 `#A8321F`；`red` 铺在 `redTint` 上对比只有约 2.7:1，小字读不清）。
- **裸色值**：产品代码已清零（只剩 `month_hero.dart` 的白色文字投影，属白/透明类例外）。
- **验证**：`flutter analyze` 0 issue；`flutter test` **269 通过 0 skip**。
- **真机走查**（MuMu 12 / 900×1600 / 320dpi）：我的页、分类管理、账本抽屉 + 账本管理、预算弹层与保存链路、
  搜索浮层三态、导入三步全链路、**记一笔日期弹层**（23 日之后灰显且点不动、点 20 日回填）、
  资产页空态、账户弹层新增 / 编辑 / 删除拦截 —— **阻断 0**。

### 修复 — 账户弹层未卡通化（F7.6 P3 走查发现）

- `SPEC-F7.6` 里「账户 sheet 已由 P2 复核」的记录不成立：`git show 3d4e749` 显示 P2 对该文件只有取色，
  结构仍是浮动 label 的 `OutlineInputBorder` + `DropdownButtonFormField` + `TextButton` / `FilledButton`。
  走查时按原型 `ovlAccount` 补做，详见上一条。

### 新增 — F7.6 P2 卡通视觉改版（日历 / 统计 / 资产）（2026-09-19）

- **范围**：`docs/SPEC-F7.6-cartoon-ui.md` 第 2 批。日历页、月份选择页、统计页、资产页 + 3 个共用件。
- **共用件**：`ToonIconButton` 补 muted 变体（虚线灰 → 用于「报表（建设中）」占位）；
  新增 `ToonDashedBorder`（虚线描边容器）；`appBarTheme` 加底部墨色描边（原型 `.appbar`），
  snackBar / dialog / bottomSheet / input 的描边宽度统一到 `Tok.bw`。
- **日历页**：header 图标换描边方块；选中日头部改「**N 笔 · 支出 ¥x**」；空态改**虚线圆 + 小猪** + 卡通文案；
  流水列表去掉外框 `Card`（描边会与行卡翻倍）。
- **月历格子**：选中态描边改墨色 2px（原来只有淡琥珀边）；收支底色改 `Tok.redTint` / `greenTint`；
  「今天」用 `brandDeep`。
- **月份选择页**：appbar 扁平化（仅保留 muted 报表占位）；`‹ 上一年` / `下一年 ›` 换 `_PillButton` 描边胶囊。
- **统计页**：月份切换换 `ToonIconButton`；收支切换从 `SegmentedButton` → `ToonSeg`；
  汇总三列 / 图例 / 分类占比行统一令牌色。
- **趋势柱图**：柱参数按原型重做 —— 宽 13、圆角 `6 6 3 3`、**2px 墨色描边**
  （Container 的 border 画在尺寸内侧，故高度 +4 抵消原型 content-box 的差）；轴标签 `Tok.ink2` w800。
- **资产页**：净资产卡改**品牌浅琥珀底**（原型 `.networth`）+ 32px 大号金额；账户行换 `ToonPress` 描边卡。
- **杂项**：账户 sheet 的错误提示 / 删除按钮色改 `Tok.red`；预算卡「未设预算」态不再渲染整行占位；
  记一笔 body 改纯白（原型 `pbody` 用 `--surface`，不是全局暖白画布）。
- **验证**：`flutter analyze` 0 issue；`flutter test` **269 通过 0 skip**（同步改 `budget_card_test` 一处断言）。
- **真机走查**（2026-09-19，MuMu 12 / 竖屏 900×1600）：日历 / 月份选择 / 统计 / 资产 四页与原型并排对拍，**阻断 0**。
  修掉两处：
  1. **日历下半部分没有居中**（用户报告）—— `_SelectedDaySection` 外层 `Column` 用了
     `CrossAxisAlignment.start`，空态块只占「最宽子项」宽度 → 块内居中、整块偏左；改 `stretch`
     （原型 `.empty-block` 是块级 div 占满宽），顺带两行文案补 `textAlign.center`、小猪改回 52px。
  2. **月份选择页迷你月缺星期表头**（读不出格子是周几）—— 补 8px 表头行；月名居中改三级灰
     （当前月品牌深色 + 圆点）；格子按原型 `.mark` / `.today` 规则（品牌底深棕字 / 墨底白字）。
- **待排期**：P3（我的 / 账本 / 分类 / 导入 / 搜索浮层 + 清掉 `import_page` 与 `search_overlay` 的裸色值）。

### 新增 — F7.6 P1 卡通浅色视觉改版（2026-09-18）

- **背景**：页面原型（`modao/yanxin/`，卡通风格）与本 App 的深色视觉是**两套体系**；
  且配色散在 15 个文件里硬编码，没有令牌层。用户确认：**全站硬替换为原型浅色 / 分 3 批交付 / 零新依赖**。
  小 SPEC：`docs/SPEC-F7.6-cartoon-ui.md`（已签字）。
- **新增主题底座**：
  - `lib/core/theme/tokens.dart` —— 令牌 1:1 取自原型 `:root`（暖白画布 `#FFF7EA`、
    白卡、墨色 `#2A2A35` 描边 2.5px、硬阴影 `4px 4px 0`、四档圆角 28/22/16/12、
    糖果色 `#FF5D5D`/`#2FC98A`、九色分类调色板）；`buildToonTheme()` 并把
    `onSurfaceVariant` 映射到次级灰 —— 旧页面「次要文字用 onSurfaceVariant」的写法自动跟随。
  - `lib/core/theme/toon.dart` —— 通用控件：`ToonCard / ToonButton（primary/tonal/ghost/danger）/
    ToonIconButton / ToonChip / ToonSeg / ToonField / ToonAvatar / ToonDashedLine / ToonRing /
    ToonSectionTitle`，按下「陷进去」的统一反馈 `ToonPress`。
  - **小猪存钱罐 + 四角星**用 `CustomPainter` 按原型坐标（64 / 24 网格）手绘，**未引任何新依赖**。
- **P1 页面**：底栏（选中 tab 变品牌色描边方块、中央「记一笔」歪 4°）、首页（header 三图标描边方块、
  hero 实心琥珀 + 装饰圆 + 小猪 + 双星贴纸 + 收入/结余气泡、预算卡环形进度加上墨色外描边技法、
  分组气泡「今天 · 2 笔」、空态单行）、记一笔（`ToonSeg` + 金额框 + 卡通键盘 + 三个 `ToonField` +
  胶囊主按钮，分类弹层改抓手 + 4 列宫格）、删除确认框、账本抽屉。
- **全站取色清剿**：日历 / 月份选择 / 统计 / 资产 / 我的 / 预算与账户 sheet 的写死深色值全部换成令牌
  （换浅色后这些文件原本是「白底白字」不可见）。
- **顺带修文案**：删除确认框原写「删除后在回收站保留」——实际没有回收站 UI，改为
  「删除后为软删除（deleted_at），不再出现在任何统计里」。
- **验证**：`flutter analyze` 0 issue；`flutter test` **269 通过 0 skip**。
  测试同步改 3 处（删除按钮 `TextButton`→`ToonButton`、主按钮 `FilledButton`→`ToonButton`）。
- **与原型的有意偏离**：hero 小猪**不做摇摆循环动画**（无限动画会让 `pumpAndSettle` 永不收敛）；
  分类弹层不放收支 seg；图标用 Material 近似；原型顶部状态栏不实现。
- **待排期**：P2（日历 / 月份选择 / 统计 / 资产）、P3（我的 / 账本 / 分类 / 导入 / 搜索浮层）。
  → P2 已于 2026-09-19 交付，见上一条。

### 文档 — 汇总一份《功能需求文档》（2026-09-18）

- 新增 **`docs/PRD-yanxin-flutter.md`**：把散落在迁移 SPEC、4 份小 SPEC、HANDOFF / CHANGELOG 里的
  **已签字需求**合并成按模块分组的 FR 清单（FR-NAV / LEDGER / RECORD / BOOK / CAT / CAL / STATS /
  BUDGET / ASSET / SEARCH / IMPORT / PROFILE 共 12 组），每条带**口径规则 + 状态图例**（✅已真机 /
  🟡仅门禁 / ⛔占位或待排期），另附数据模型、非功能需求 NFR-01–08、累计验收结果与 pending backlog。
- **性质是汇总稿，不是签字件**：不改变任何口径，也不新增需求；新需求仍按「小 SPEC → 签字 → 实现」流程走。
- 同步修正 `HANDOFF.md` 里的过期状态（HEAD `f95ba97` → `e06d23a`、门禁 253/266 → **269**、接手指南补一句
  「资产页已真机走查」），并在「关键资料」「极简版」两处登记本文档入口。

## [v0.7.5] — 2026-09-17 · F7.5 搜索浮层化 + 资产页

### 新增 — F7.5-b 资产页（2026-09-17）

- **背景**：底栏「资产」tab 一直是 `PlaceholderPage`，但**账户数据早已入库**
  （`accounts` 表 + `AccountRepository` 完整 CRUD、新建账本自带「现金」、导入自动建账户、
  记一笔默认写 `accounts.first`）——缺的只是界面。SPEC：`docs/SPEC-F7.5-assets.md`（已签字）。
- **口径**：账户余额 = **初始余额 + Σ收入 − Σ支出**，**transfer 不计**
  （`transfer_group_id` 仍是预留字段，转账的「从哪到哪」没落库语义，硬算必错）。
  净资产 = 各未删账户余额之和，**全时间累计**（资产是存量，不按月筛选）。
- **页面**：净资产卡（≥0 琥珀橙 / <0 红，副行「N 个账户 · 全时间累计」）+ 账户行
  （类型图标 / 名称 / 「类型 · 收 X / 支 Y」/ 余额，负余额红字）+ 无账户空态。
- **账户 CRUD**：AppBar `+` 新增、点行编辑，底部 sheet 三字段（名称 / 类型下拉 / 初始余额元）。
  **有流水的账户禁止删除**（弹「还有 N 笔流水，请先改到别的账户」），防止流水指向不存在的账户。
- **刷新机制改了一处**：新增 `dataEpochProvider`（数据版本号），资产页 watch 它；
  记一笔 / 导入 / 首页删除 / 日历删除 / 搜索删除 5 个写操作点各自 bump 一行即可。
  原因：HANDOFF 记载过「漏刷 `statsProvider` 出 bug」——逐个 provider 手工 `refresh()` 是已知脆弱点，
  新增一个消费方就要补 N 处。**本次不动 stats / calendar / ledger 的既有 refresh 调用**（避免回归）。
- **不改 schema**：无新表无新字段，`schemaVersion` 仍为 2，`database.g.dart` 未变，老库升级零风险。
- **门禁**：`flutter analyze` No issues found；`flutter test` **266 通过 0 skip**
  （新增 13 条：聚合纯函数 10 + 资产页 widget 3）。
- **取舍**：初始余额**不接受负数**（`yuanToCents` 正则不放宽，不松动「金额恒正」铁律）；
  信用卡期初欠款暂由记支出体现。
- **真机走查（MuMu 12 / 900×1600 竖屏，首次使用验收规范）**：15 步全过，
  **阻断 0 / 卡住 0 / 状态丢失 0**；覆盖「空名称拦截」「金额三位小数拦截（弹窗不关、内容不丢）」
  「新增 → 净资产 0→100」「编辑回填」「删除二次确认 → 列表与净资产自动重算」
  「记一笔 88.88 支出 → 净资产 -88.88 红字、账户行支 88.88」「冷启动持久化」
  「有流水的账户禁删（拦截后编辑弹窗保留、账户未被删）」。报告 `docs/acceptance-F7.5b-assets.md`。
  遗留体验摩擦 1 条：账户图标 / 颜色无法设置（`icon` / `color` 列已存在，仅界面未暴露）。
- **本次修正的实走方法**：空 `TextField` 不出现在语义树里，早期按推算坐标点击落到遮罩区，
  表现为「弹窗莫名关闭 + 键盘不拉起」，一度被误判为阻断 bug；用「保存 / 取消」按钮坐标
  反推弹窗边界后复测推翻。坑已写进 `.workbuddy/skills/mumu-flutter-ui-smoke/SKILL.md`。

### 新增 — F7.5-a 搜索浮层化 + 类型筛选建议（2026-09-12）

- **背景**：F7.4 的搜索是**全屏独立路由**（`/search`），进去后首页被完全遮住、像换了个 App；
  且没有任何筛选入口——想「只看支出」只能靠关键词碰运气。用户需求（原话）：
  **「提示块提供搜索建议，比如仅支出，仅收入，转账等，不用提供历史记录，然后搜索功能是显示在
  首页的上层，提示块以下的区域做透明玻璃效果，使其能看见首页」**。
- **浮层化**：`/search` 路由与 `SearchPage` **一并删除**，改为 `showGeneralDialog` 打开
  `SearchOverlay`（`lib/features/search/presentation/search_overlay.dart`，原 `search_page.dart` 改名）——
  首页留在页面栈里当背景（DialogRoute 非 opaque，下层路由不会被 Offstage）。
  **不给同一功能留两条路**：那会变成两份 UI + 两套刷新链路（本项目已因「同一个东西两份状态」踩过坑）。
- **毛玻璃**：`BackdropFilter(blur sigma 12)` 铺满全屏 + 半透明遮罩；**不透明提示块**盖住上半部分
  ——视觉上「提示块以下才是玻璃」，且提示块边缘不会出现接缝。结果列表浮在玻璃之上（条目自带 `Card` 背景）。
- **类型筛选（本次核心）**：「仅支出 / 仅收入 / 转账」这几个字**不在业务字段里**
  （备注 / 分类名 / 金额都匹配不到），直接当关键词搜恒为空 → 改为解析成 `Transactions.type` 条件：
  - `仅支出` → 该账本全部支出；`仅收入` / `转账` 同理。`仅支出 餐饮` → **类型 ∩ 关键词**。
  - 纯函数实现（`search_query.dart` 的 `parsePlan` / `stripTypeWords`）；类型词**须独立成词**
    —— `转账手续费` 不会被误判成指令，仍走普通关键词匹配。
  - 同时出现多个类型词时**以最后出现的为准**。
  - 词是**真的填进输入框**（可见 / 可编辑 / 可一键清空），chip 高亮**由输入框内容推导**
    → 不会出现「chip 亮着但输入框空着」这种双份状态。填入时补**尾随空格**，方便接着敲关键词。
- **交互**：三种关闭方式（关闭按钮 / 点玻璃空白区 / 系统返回键）；无结果态沿用 F7.4 的
  「顶部对齐 + 占屏高 1/5」；结果条目**点=编辑、长按=删除**，删改后浮层内 + 首页 / 日历 / 统计 /
  `yearDayIndex` 全刷。
- **门禁**：`flutter analyze` No issues found；`flutter test` **247 通过 + 6 skip**
  （新增 21 条：类型指令解析 11 + 浮层 widget 10）。
- **真机走查（MuMu 15，覆盖安装老数据零丢失：支出 120.00 / 收入 50.00 / 预算 3,000）**：
  SPEC §6 十条全过。另抓到 **3 个只有真机才暴露**的问题并修掉：
  ① **引导态点提示块以外的空白关不掉浮层**（无结果态却可以）——`_Intro` 当时用
  `SingleChildScrollView`，Scrollable 的 `RawGestureDetector` 以 `HitTestBehavior.opaque`
  命中了整块下方区域，点击传不到底层玻璃的关闭手势 → 改用 `Align(topCenter)`，只占内容高度、空白可穿透；
  ② **选中 chip 的对勾让 chip 变宽，把后面几个整排挤位移** → `showCheckmark: false`；
  ③ **点 chip 后接着敲字拼成 `仅支出11`，指令失效、结果恒为空** → 填入时补尾随空格。
  ①②③ 中 ①③ 已补 widget 回归测试。
- **转账说明**：`Transactions.type` 支持 `transfer`（此时 `categoryId` 为 NULL），但**记账页没有转账入口**，
  现有数据基本为空 —— 该 chip 仍保留：点了走类型筛选，命中为空则显示无结果态。

### 优化 — 搜索页无结果态改为「顶部对齐 + 占屏高 1/5」（2026-09-12）

- **问题**：无结果提示原用 `Center` 垂直居中，四周留大片空白；且提示与输入框离得太远
  ——用户刚敲完词、视线还在输入框附近，提示却飘在屏幕正中。
- **改法**（`lib/features/search/presentation/search_overlay.dart` 的 `_NoResult`；F7.5 已由 `search_page.dart` 改名）：
  - 外层改 `Align(topCenter)` + `SizedBox(height: MediaQuery.sizeOf(context).height / 5)`：
    提示块紧贴输入框下方，高度固定占**整屏** 1/5；
  - 高度按整屏而非 body 计算——本页输入框 `autofocus`，键盘弹起会压扁 body，
    按 body 算的话提示块会跟着一起缩；
  - 内容同步紧凑化（图标 40→32、间距 12→6/4、按钮 `visualDensity.compact` + `tapTargetSize.shrinkWrap`），
    保证塞得进 1/5 高度；极小屏（逻辑高 < 约 550）由 `SingleChildScrollView` 兜底，不会 RenderFlex 溢出。
- **验证**：门禁 analyze 0 issue / test 226 通过 + 6 skip（`_NoResult` 的断言文案未改，测试无需调整）；
  MuMu 15 走查：搜 `zzz` → 提示块落在输入框下方、占屏高约 1/5、下方留白；
  搜 `11` → 有命中态（共 1 笔 · 支出 11.12）不受影响。

## [v0.7.4] — 2026-09-12 · F7.4 流水搜索（分类 / 备注 / 金额）

### 新增 — F7.4 流水搜索（2026-09-12）

- **背景**：首页 header 的搜索图标一直是占位（点了弹「功能建设中」）；账记得越多，找一笔旧账越难
  ——只能按月翻首页/日历。用户需求：**按分类 / 备注 / 金额搜索 + 输入框一键清空**。
- **取数**：新增 `TransactionRepository.listByBook(bookId)`（全时间、未删、`occurred_at` 倒序）。
  搜索页进页**一次性读齐**当前账本流水 + 分类名表（万级行 <10ms），之后**逐键内存过滤**
  ——无需防抖、不逐键查库，输入手感即时。
- **匹配口径**（`lib/features/search/application/search_query.dart`，纯函数可单测）：
  - 查询串预处理：去首尾空白、去 `¥` `￥` 与千分位逗号、英文转小写、限长 50；
  - **分类名**：按 `categoryId` 解析出的名字做子串包含（`categoryId` 为空按「未分类」）；
  - **备注**：子串包含，大小写不敏感；
  - **金额**：格式化为「元.分」文本后子串包含（查 `88` 命中 `88.00 / 188.00 / 88.88`；
    查 `88.8` 命中 `88.80`；查 `0.5` 命中 `10.50`）；
  - 三类取**并集**；空查询不返回全部流水（显示引导）。
- **UI**：新增 `/search` 全屏页（首页 header 搜索图标进入）——
  - `AppBar` 即输入框（`autofocus`），右侧**一键清空**（有输入才出现，点击清空并保持焦点）；
  - 结果按天分组复用 `TxGroupList`（点=编辑、长按=删除，与首页一致）；
  - 顶部结果条：`共 N 笔 · 支出 X · 收入 Y`（复用 `summarize`，与首页/统计页口径一致）；
    超过 200 条只显示最近 200 条并提示补充关键词；
  - 三种状态齐备：未输入（引导 + 示例词可点）、无结果（回显关键词 + 清空）、有结果（列表 + 汇总）；
  - 删除/编辑后的刷新链路与首页对齐：`searchProvider` + 首页/日历/统计 + `yearDayIndex` 全刷。
- **验证**：门禁 `flutter analyze` No issues found、`flutter test` **226 通过 + 6 skip**（新增 27 条：
  匹配纯函数 19 + 搜索页 widget 7 + 仓储 1）；**MuMu 15 真机冒烟**：搜「餐饮」→ 共 2 笔（支出 100.00）、
  搜 `88.88` → 共 1 笔、搜「午餐」（库中无此备注）→ 无结果态、一键清空 → 回引导态、
  记一笔 1.23 + 备注 `coffee` → 搜 `coffee` 命中 1 笔、点结果进编辑页数据正确、
  长按删除 → 无结果态且**首页 / 预算卡回滚到 120.00**（跨页刷新正常）。

## [v0.7.3] — 2026-09-12 · F7.3 月度预算实装（schema v2）

### 新增 — F7.3 月度预算实装（2026-09-12，schema v2）

- **背景**：首页预算卡原是写死的示例数字（`1,000.00 / 101.52 / 10.2%`），与同屏 hero 的
  真实月支出自相矛盾（首用验收 P2）。当时的「示例」chip 只是止损，本次把它做成真功能。
- **数据层（`schemaVersion 1 → 2`）**：
  - 新增 `budgets` 表：`book_id` + `period('YYYY-MM')` + `amount_cents` + 同步元数据五件套，
    与其它业务表同构（软删 / `dirty` / 金额整数分 / 客户端 UUID 主键）。
  - 部分唯一索引 `idx_budget_book_period(book_id, period) WHERE deleted_at IS NULL`：
    同月重复设置走更新；删掉后可重设。
  - `onUpgrade(from < 2)` **只加表 + 建索引**，v1 五张表与 7 条索引一字未改 → 老库升级零数据风险。
  - 新增 `BudgetRepository`（先查后写，不依赖 sqlite 错误消息判重；软删；跨账本隔离）。
- **计算层**：新增 `budget_metrics.dart`（纯函数）——进度（环形封顶 1.0，文案显示真实值可 > 100%）、
  剩余额度（可为负）、本月日均（复用日历页口径：当月按已过天数、历史月按整月）、
  剩余每日可消费（当月含今天；历史月不适用显示「—」；超支归 0）。
- **UI**：
  - `BudgetCard` 替换 `budget_card_placeholder.dart`（占位卡删除，**「示例」chip 与说明文案一并移除**）。
  - 未设预算时给可点的空态引导（「设置N月预算」），**页面上不再出现任何假数字**。
  - 底部弹窗就地设置：常用额度快捷键（1000/2000/3000/5000）+ 金额校验 + 有预算时「删除预算」（二次确认）。
  - 已消费 / 日均直接取首页已加载流水 → 记一笔 / 删一笔后卡片随首页刷新，**无需额外接线**。
- **验证**：门禁 `flutter analyze` No issues found、`flutter test` **199 通过 + 6 skip**（新增 26 条）。
  MuMu 15 真机：**旧版本覆盖安装（v1 库 → v2）数据零丢失**（108.88 / 50.00 全在）、
  设置 2000 → 5.4% / 1891.12 / 每日 99.53、改 100 → **超支态**（108.9% / -8.88 /「已超支」/ 每日 0.00）、
  删除 → 回到未设置、force-stop 重启后 3,000.00 仍在、记一笔 11.12 → 卡片自动变 120.00 / 4.0%。

### 修复 — 统计页不随记账刷新（2026-09-12，MuMu 冒烟发现）

- 现象：记一笔/导入/删除后，首页与日历都会刷新，**统计页仍是旧数据**（收入 50.00 已入账，统计摘要仍显示 0.00）。
- 根因：`statsProvider` 是常驻 `AsyncNotifierProvider`，`build()` 只在首次进页执行一次；
  `refresh()` 虽已预留但**无任何调用方**。
- 修复：与首页/日历的既有刷新模式对齐，补齐四处调用——
  `record_page`（保存后）、`import_page`（导入后）、`home_page` / `calendar_page`（删除后）。
- MuMu 模拟器复验：记 20.00 后统计支出 88.88 → 108.88；门禁复跑 analyze 0 issue、test 173 通过 + 6 skip（skip 为缺真实账单样本，基线一致）。

### 环境 — MuMu 冒烟链路补齐（2026-09-12）

- 补装 **NDK r28c（28.2.13676358）** 与 **CMake 3.22.1**（腾讯镜像 + 7890 代理，8 线程分片下载 ~60s，
  脚本 `.workbuddy/dl_ndk.py`）；`android/gradle.properties` 加 `android.builder.sdkDownload=false`
  绕开新版 cmdline-tools sdkmanager 被 AGP 调用即崩（0xC0000409）的问题。
- `flutter build apk --debug` 本机跑通（177MB，增量 ~32s）；MuMu 15 由平板横屏 2560×1440 切为
  手机竖屏 1080×1920（`MuMuManager.exe setting -k resolution_mode phone.1` + restart）。

## [v0.7.2] — 2026-09-12 · F7.2 统计 · 报表页

### 新增 — F7.2 统计·报表页（2026-09-12）

- **统计页**（`/stats`）：首页 header 的「统计」图标由「建设中」占位改为真实入口。
  - 分类占比：支出 / 收入切换（`SegmentedButton`）+ 自绘圆环（`CustomPainter`，未引图表库）
    + 图例（色块 / 分类名 / 占比 / 金额，千分位）；圆心显示该方向合计。
  - 近 6 个月趋势：每月两根柱（支出红 / 收入绿，中国习惯），缺月补 0，跨年柱标签带年份。
  - 当月汇总：收入 / 支出 / 结余；月份切换 `‹ ›` 与首页同样受「不能超过当前月」约束。
- 新增 `TransactionRepository.listByRange()`（一次取齐跨月 / 跨年区间，避免逐月查询）；
  `StatsController`（`statsProvider`）与首页 `ledgerProvider`、日历 `calendarProvider` 一样独立记月份。
- 测试：新增 13 条（聚合纯函数 9 + 统计页 widget 4）；门禁 `flutter test` **179/179**（166 + 13）。

### 环境 — 换机重装（2026-09-12）

- 新机器（用户 Administrator，只有 C:/M 盘，无 D 盘）重搭环境：Flutter 3.47.2 / Dart 3.13.2 →
  `C:\src\flutter`；JDK 17.0.12 → `M:\QQcache`；Android SDK → `C:\src\Android`；Gradle 缓存 → `C:\src\gradle-home`。
  `env.sh` 路径已全部重指向，并新增两条本机专属坑的说明（sqlite3.dll、bash PATH 兜底）。
- ⚠️ **Windows 自带 `winsqlite3.dll` 太老**：不支持 `RETURNING`（需 SQLite ≥ 3.35），drift 的
  `insertReturning` 全线报 `near "RETURNING": syntax error`，60 条测试挂掉。
  解法：官方 sqlite-dll-win-x64（3.53.4）放到 `C:\src\sqlite3`（进 PATH）+ 复制一份到 flutter_tester 同目录。

## [v0.7.1] — 2026-09-11 · F7.1 日历页

### 新增 — F7.1 日历页（2026-09-11）

- **日历 tab**：`/calendar` 由占位页替换为真实页面 —— 月历网格把每天的支出标负数（红）、
  收入标正数（绿），今天与选中日分别用琥珀色文字 / 描边。
- **月汇总条**：日历下方显示「月结余 / 日均支出」；日均支出当月按已过天数折算、历史月按整月天数，
  全程整数运算取整到分。
- **选中日账单**：下方列出选中日期的流水（点击编辑、长按删除），空态给「这天没有账单哦，赶紧记一笔吧~」
  与「记一笔」按钮。
- **月份选择子页**（`/month-picker`）：按年展示 12 个月的缩略日历，有账的日期标琥珀色，
  点某天即跳到该月并选中该日；底部分页「上一年 / 下一年」。
- **记录某一天的账**：记一笔页新增「日期」字段（可点改、上限今天），路由支持 `/record?date=<毫秒>`，
  日历页「记一笔」自动带入选中日期。
- 新增 `TransactionRepository.listByYear()`（一次查全年，供缩略图索引有账日期）；
  `CalendarController` 与首页 `ledgerProvider` 状态分离，两个 tab 各自记住月份。
- 测试：新增 15 条（聚合纯函数 8、仓储 1、日历 widget 6）；门禁 `flutter test` **166/166**。

### 修复 — 首次使用验收 P3–P6（2026-09-11）

- **P3 二次导入报告自相矛盾**：零新增时标题由「导入完成」改为「没有新增」，正文改为
  「这 N 笔之前已经导入过了，没有重复记账」；`ImportReport.uncategorized` 改为只统计
  **真正入库**的未匹配行（重复跳过的行与分类规则无关，此前会在 0 新增时虚报「未匹配分类 167 笔」）。
- **P4 首页空态不可见**：空态由居中大块改为紧凑单行（图标 + 说明 + 「记一笔」按钮 + 导入指路），
  修复大屏/横屏下 hero + 预算卡占满首屏导致空态被挤到折叠下方、用户只看到一片空白的问题；
  文案从「点底部的 ＋」改为真实存在的「记一笔」入口。
- **P5 保存入口藏在折叠下方**：记一笔页 `AppBar` 新增常驻「保存」按钮（底部按钮保留），
  大屏下填完金额 + 分类后无需滚动即可保存。
- **P6 预览页看不出如何取消单条**：预览顶部补「勾选的条目会导入，点条目可取消它」说明，
  并新增「全选 / 全不选」切换。

### 文档

- 新增 `CHANGELOG.md`；README 迁移进度表更新至 F5 完成，技术选型补全（`archive` 手写正则解析器、
  `file_picker`、`crypto`、`gbk_codec`），纠正 xlsx 选型误记为 `excel` 包的说法。

## [F5] 账单导入（M2 等价） — 2026-09-10

### 新增

- 账单解析五层（旧栈 `bill-import` 移植）：ZIP 魔数识别 → xlsx / CSV 分支 →
  行矩阵化 → 归一化 → 微信 / 支付宝 profile 适配。
- 微信 xlsx：`archive` 解压 + 手写正则解析器（不经 `double`，保住 31 位交易单号精度）；
  Excel 日期序列号按本地时区换算。
- CSV：逐字符状态机解析；支付宝 GBK 走 `gbk_codec`，用重编码回环校验判坏件。
- 分类关键词规则表（39 条有序规则）+ 未命中落「其他」。
- 导入编排 `importRows()`：单事务 + 指纹 `IN` 分批预查（500/批）+ 文件内去重 +
  `dryRun` 哨兵回滚；`importTransaction()` 指纹幂等入账（ADR-7）。
- 导入页 UI：选文件 → 预览（可单条取消）→ 确认导入 → 结果报告。

### 修复 — 首次使用验收 P1/P2（同批次）

- **P1 导入后首页看不到数据**：`ledger_controller` 新增 `jumpToMonth()`（可跳历史月，
  不受 `canGoNext` 限制）；报告对话框「好的」拆为「完成」+「去看账单」，正文说明数据落在哪个月。
- **P2 预算卡假数据与 hero 矛盾**：预算占位卡加「示例」标签与底部说明，明确非真实消费数据。

## [F4.5] 首页改版 + 底部导航 — 2026-09-10

### 新增

- 全局深色主题（近黑底 `#0C0C0C` + 琥珀橙 `#FFAF38`）。
- `StatefulShellRoute.indexedStack` 底栏 4 tab（首页 / 日历 / 资产 / 我的）+ 中央「记一笔」。
- 首页改版：账本 header + 琥珀 hero 月支出卡（`‹ ›` 翻月）+ 预算占位卡 + 「本月账单」分组列表。
- 账本抽屉（全部账本 + 管理账本入口）。

### 性能

- 消除记一笔 push 转场卡顿：去掉异步门闩 + 零重复查询。

## [F4] UI 基础（M1 等价） — 2026-09-09

### 新增

- 首页（hero 翻月 + 按天分组流水列表 + 空态）、记一笔（支出/收入 + 金额键盘 + 分类宫格 + 备注）、
  编辑流水、长按软删、账本管理（新建 / 切换隔离）、分类管理（预置不可删 + 自定义）。

## [F3] 数据层 — 2026-09-09

### 新增

- drift schema v1：`books / accounts / categories / transactions / schema_meta`，7 条索引
  原样落地（含 `DESC` 与 `idx_tx_fingerprint` 部分唯一索引，走 `onCreate` 原始 SQL）。
- 4 个 repository + `active_book_id` 持久化 + `importTransaction()` 指纹幂等入账。

## [F2] core/utils — 2026-09-09

### 新增

- `money`（整数分）、`id`（UUID v4）、`fingerprint`（入账指纹，与旧版逐字节一致）、
  `date`（月份边界 / 按天分组）。移植旧用例 + 指纹 golden 向量。

## [F1] 空壳 + 依赖 — 2026-09-09

### 新增

- `flutter create` 骨架、依赖锁定（drift / sqlite3 / Riverpod / go_router 等）、
  `analysis_options.yaml` 收紧（strict-casts/inference/raw-types）。
- `env.sh` 环境脚本（代理、VS 环境变量注入、`fx-qa` / `fx-test` 门禁命令）。

## [F0] 环境搭建 — 2026-09-09

### 新增

- Flutter 3.47.2 / Dart 3.13.2、JDK 17、Android SDK cmdline-tools、licenses 全部接受。
- Android 构建链路修复（国内镜像、Gradle 缓存策略）。
