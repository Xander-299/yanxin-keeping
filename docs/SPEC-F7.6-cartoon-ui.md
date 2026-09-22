# SPEC — F7.6 卡通浅色视觉改版（对齐页面原型）

> 状态：**已签字并全部交付**（2026-09-18 用户确认三项决策）· P1 / P2 / P3 **均已交付 + 真机走查通过**
> 起草：2026-09-18 · 原型：`D:\new file\modao\yanxin\`（`index.html` + `styles.css` + `data.js` + `screens.js` + `app.js`）
> 关联：`docs/PRD-yanxin-flutter.md`（口径不动）、`app_template/*.jpg`（旧参考图，本次起被原型取代）

---

## 1. 要解决的问题

当前 App 的视觉是 F4.5 定的**深色**（`#0C0C0C` + 琥珀橙），而页面原型是**卡通浅色**
（暖白画布 + 白卡 + 2.5px 墨色描边 + 4px 硬阴影 + 糖果色）。两者不是「微调」关系，
是**两套视觉体系**；且当前配色散在 15 个文件里硬编码，没有令牌层，改一处漏三处。

本次把全站视觉**硬替换**为原型风格，并把颜色/圆角/描边/阴影收进统一的**设计令牌**。

## 2. 范围与决策（用户 2026-09-18 已确认）

| # | 决策项 | 结论 |
|---|---|---|
| 1 | 主题策略 | **全站硬替换为原型浅色**（深色不做保留、不做切换） |
| 2 | 交付切片 | **分 3 批**（见 §6），每批独立门禁 + 真机走查 |
| 3 | 图形落地 | **零新依赖**：能用 Material 图标的用 Material，小猪存钱罐 / 四角星用 `CustomPainter` 按原型坐标复刻 |

**不做**（本次范围外）：深浅双主题、`flutter_svg`、原型里的**手机状态栏**（那是原型外壳，不是 App 内容）、
原型里的「未选中示例态」演示开关（`report-mode` 那种纯演示切换）。

## 3. 设计令牌（从原型 `styles.css` 的 `:root` 1:1 搬运）

| 用途 | 令牌 | 值 |
|---|---|---|
| 墨色描边 / 主文字 | `ink` | `#2A2A35` |
| 次级 / 三级文字 | `ink2` / `ink3` | `#6C6C7C` / `#9C9CAD` |
| 卡片纸 / 画布 / 画布次级 | `paper` / `canvas` / `canvas2` | `#FFFFFF` / `#FFF7EA` / `#FFFCF6` |
| 品牌 | `brand` / `brandDeep` / `brandInk` / `brandTint` / `brandTint2` | `#FFB627` / `#E1810A` / `#4A3103` / `#FFF1D4` / `#FFE1AC` |
| 支出 / 深色文字态 | `red` / `redTint` | `#FF5D5D` / `#FFE5E5` |
| 红底提示条文字 | `redInk` | `#A8321F`（与 `brandInk` 同思路；`red` 在 `redTint` 上对比不足） |
| 收入 | `green` / `greenTint` | `#2FC98A` / `#D9F7E9` |
| 辅助 | `blue` / `purple` / `pink` / `lemon`（含各自 tint） | `#4DA8FF` / `#A98BFF` / `#FF7FAB` / `#FFE066` |
| 分割线 | `line` | `#F0E7D8`（虚线分割用 `rgba(42,42,53,.2)`） |
| 描边宽 | `bw` | `2.5px` |
| 硬阴影 | `sh` / `shSm` / `shLg` | `4px 4px 0 ink` / `2.5px 2.5px 0` / `6px 6px 0` |
| 圆角 | `rXl` / `rLg` / `rMd` / `rSm` | 28 / 22 / 16 / 12 |
| 分类占比调色板 | `pie` | `#FFB627 #FF6B8A #4DC9C0 #5A8DFF #B18CFF #5FD068 #FF8A3D #F06FC0 #9AA5B1` |
| 字体 | — | 沿用系统字；金额 `tabular-nums`（等宽数字） |

**约束**：产品代码里**不再出现裸 `Color(0x…)`**（除令牌文件本身），一律引用令牌。

## 4. 通用控件（新增，全站复用）

| 控件 | 规格 |
|---|---|
| `ToonCard` | 白底 + `2.5px ink` 描边 + 硬阴影 + 圆角 22；可选 `pad` / `flat`（无阴影） |
| `ToonButton` | 四态：`primary`（品牌底 + 描边 + 硬阴影）/ `tonal`（品牌浅底）/ `ghost`（白底描边）/ `danger`（红底）；按下位移「陷进去」 |
| `ToonIconButton` | 40×40 圆形/方形命中区，1.9px 线性图标 |
| `ToonChip` | 胶囊，选中 = 品牌浅底 + 描边；**无 checkmark**（沿用 F7.5-a 教训：选中变宽会挤位移） |
| `ToonSeg` | 支出/收入分段控件（原型 `.seg`，非 Material `SegmentedButton`） |
| `ToonField` | `label + value + chevron` 的行式表单字段（记一笔用） |
| `PigMascot` | 小猪存钱罐 `CustomPainter`：三角耳 ×2 + 圆脸 + 椭圆鼻 + 眼 ×2 + 鼻孔 ×2 + 腮红 ×2，参数化尺寸/配色 |
| `Sparkle` | 四角星贴纸 `CustomPainter`，用于 hero 装饰 |

## 5. 图标映射（原型 → Material，近似优先）

| 原型 | Material | 原型 | Material |
|---|---|---|---|
| home / cal / wallet / user | `home` / `calendar_today` / `account_balance_wallet` / `person` | search / receipt / chart / plus | `search` / `receipt_long` / `bar_chart` / `add` |
| chev-d / l / r / back | `expand_more` / `chevron_left` / `chevron_right` / `arrow_back` | edit / trash / close / check | `edit` / `delete_outline` / `close` / `check` |
| backspace | `backspace_outlined` | card / bank / cash / coins / phone | `credit_card`/`account_balance`/`payments`/`savings`/`smartphone` |
| tag / doc / dl / settings / menu / book / grid / info | `label_outline`/`description_outlined`/`download_outlined`/`tune`/`menu`/`menu_book`/`grid_view`/`info_outline` | note | `sticky_note_2_outlined` |

> 图标描边宽度无法用 Material 控制（原型 1.9px）；接受近似，不引 SVG。

## 6. 交付切片

### P1 —— 主题底座 + 底栏 + 首页 + 记一笔（本次交付）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `lib/core/theme/tokens.dart` **新增** | §3 全部令牌 + 硬阴影/描边 helper |
| 2 | `lib/core/theme/toon.dart` **新增** | §4 通用控件 + 小猪 + 四角星 |
| 3 | `lib/app.dart` | `_buildTheme()` 换浅色（画布 / 卡片 / AppBar / 分割线 / 文本三阶） |
| 4 | `lib/features/nav/presentation/app_shell.dart` | 底栏白底 + 顶部描边；中央「记一笔」品牌圆钮 + 硬阴影 |
| 5 | `lib/features/ledger/presentation/home_page.dart` | header（账本名胶囊 / 搜索 / 报表占位 / 统计）+ 分组胶囊标签 + 空态 |
| 6 | `.../widgets/month_hero.dart` | 渐变改 `#FFF0D6→#FFD79B→#FFC178`，字色 `#3F2B06`，**加小猪 + 星贴纸**，收入/结余两列 |
| 7 | `.../widgets/budget_card.dart` | 白卡描边 + 环形 58px（墨色外描边技巧）+ 指标两列 + 虚线分割 + 日均两行 dot |
| 8 | `.../widgets/tx_group_list.dart` | 流水行改原型样式（头像 40 圆角 14、金额 ± 配色、按压缩进） |
| 9 | `.../widgets/tx_delete_dialog.dart` | 卡通 dialog |
| 10 | `lib/features/record/presentation/record_page.dart` | **结构改造**：seg 收支 → 金额大字 → 键盘 → 三个 `ToonField`（分类 / 日期 / 备注）→ 底部主按钮 |
| 11 | `lib/features/record/presentation/widgets/amount_keyboard.dart` | 卡通键盘（白键 + 描边 + 硬阴影） |
| 12 | `lib/features/record/presentation/widgets/category_picker.dart` | **内联宫格 → 底部弹层宫格**（原型 `sheet-category`） |
| 13 | `lib/features/ledger/presentation/widgets/book_drawer.dart` | 抽屉卡通化 |

### P2 —— 日历 / 统计 / 资产
日历页（tint 底 + 日金额标注 + 月汇总卡 + 空态吉祥物）、月份选择页（4×3 迷你月 + pill 翻年）、
统计页（汇总三列卡 + 148px 粗描边 donut + 图例 + 双柱趋势）、资产页（净资产卡 + 账户行 + 口径脚注）。

### P3 —— 我的 / 账本 / 分类 / 导入 / 全部弹层
我的页（头像卡 + 4 条目 + 品牌提示卡）、账本管理、分类管理（seg + 字母头像列表）、
导入三步（步骤条 + 勾选列表 + 报告卡）、分类选择 sheet、日期选择 sheet、预算 sheet、
账户 sheet、搜索浮层（chips + 结果条 + 吉祥物空态）。

## 7. 门禁与验收

1. `flutter analyze` **0 issue**；`flutter test` **全绿**（基线 269，改结构导致的用例同步改）。
2. **产品代码零裸色值**：`grep -rn "Color(0x" lib/ | grep -v core/theme` 只允许出现白/透明类。
3. 真机走查（MuMu 12，`mumu-flutter-ui-smoke`）：P1 覆盖 首页记账 → hero/预算卡数字变 → 记一笔三字段 → 删一笔。
4. 视觉核对：与原型同屏并排比对（截图对拍，允许图标与字体的近似差）。

## 8. 风险 / 取舍

| 风险 | 处理 |
|---|---|
| **改结构会打挂现有 widget 测试**（记一笔的 inline 宫格、首页断言） | 用例同步改；**先保证语义文案不变**（`已新增「X」`、`保存` 等）以减少改动面 |
| 硬阴影在 Flutter 里 blur=0、offset 正下右——`BoxShadow` 做不出「硬」边 | 用 `BoxShadow(offset, blurRadius: 0, spreadRadius: 0)` + `border`，实测即为硬边 |
| Material 图标画不出原型 1.9px 描边质感 | 接受近似（用户已确认不加依赖） |
| 浅色下红绿对比降低 | 语义色直接取原型糖果色（`#FF5D5D`/`#2FC98A`），比旧值更亮 |
| 一次改 13 个文件，中间态不可用 | 令牌与控件先落地、页面逐个换（编译不过就先不提交）；**每批一个 commit** |
| 深色主题彻底消失 | 用户已确认；后续若要深色需单开 SPEC |

## 9. 签字

| 角色 | 结论 | 日期 |
|---|---|---|
| 用户 | ✅ 同意（浅色硬替换 / 分 3 批 / 零新依赖） | 2026-09-18 |

---

## 10. 实施记录

### P1 已交付（2026-09-18）

| 文件 | 状态 |
|---|---|
| `lib/core/theme/tokens.dart` **新增** | ✅ 令牌 + `buildToonTheme()`（含 `onSurfaceVariant → ink2` 的映射，旧页面「次要文字」自动变灰） |
| `lib/core/theme/toon.dart` **新增** | ✅ `ToonPress / ToonCard / ToonButton / ToonIconButton / ToonChip / ToonSeg / ToonField / ToonAvatar / ToonDashedLine / ToonRing / ToonSectionTitle` + `PigMascot` `Sparkle` 手绘 |
| `lib/app.dart` | ✅ 换 `buildToonTheme()`；`kBrandOrange` 变成 `Tok.brand` 别名 |
| `app_shell.dart` | ✅ 白底 + 顶部墨色描边；选中 tab 图标变品牌色描边方块；中央「记一笔」歪 4° |
| `home_page.dart` | ✅ header 三图标改描边方块（报表=虚线灰占位）、区头改「圆点 + 胶囊全部账单」、空态改原型单行 |
| `month_hero.dart` | ✅ 实心琥珀 + 3px 描边 + 6px 硬阴影 + 装饰圆 + 小猪（歪 6°）+ 双星贴纸；金额加白色硬投影 |
| `budget_card.dart` | ✅ 白卡 + `ToonRing`（墨色外描边技法）+ 指标两列 + 虚线 + 描边圆点 |
| `tx_group_list.dart` | ✅ 分组气泡「今天 · 2 笔」+ 白卡描边列表 + 虚线分隔 + 描边头像 |
| `tx_delete_dialog.dart` | ✅ 卡通 dialog（顺带修掉「回收站在哪」的误导文案 → 改成「软删除，不再出现在统计里」） |
| `book_drawer.dart` | ✅ 白底 + 右侧描边 + 圆角 + 选中行品牌浅底 |
| `record_page.dart` / `amount_keyboard` / `category_picker` | ✅ `ToonSeg` + 金额框 + 卡通键盘 + 三个 `ToonField` + 胶囊主按钮；分类弹层改抓手 + 4 列宫格 |
| **全站取色清剿** | ✅ 日历 / 月份选择 / 统计 / 资产 / 我的 / 两个 sheet 的写死深色值全部换成令牌（原本白底白字不可见） |

**门禁**：`flutter analyze` **0 issue**；`flutter test` **269 通过 0 skip**。

**测试同步改动（3 处，均为控件类型变化所致）**：

1. 删除确认框的「删除」从 `TextButton` → `ToonButton` → 用例改 `find.text('删除')`（`widget_test` / `search_overlay_test`）。
2. 记一笔主按钮从 `FilledButton` → `ToonButton` → 用例改 `find.widgetWithText(ToonButton, '记一笔')`（`widget_test` ×2 / `calendar_page_test`）。

**与原型的有意偏离**：

| # | 偏离 | 原因 |
|---|---|---|
| 1 | **hero 小猪不做摇摆循环动画** | 无限动画会让 widget 测试的 `pumpAndSettle` 永不收敛 |
| 2 | 分类弹层内不放「支出 / 收入」seg | 收支切换属页面级状态，放弹层里要回传 kind，收益低；页面上已有 seg |
| 3 | 图标用 Material 近似 | 用户已确认零新依赖，Material 无法复刻 1.9px 描边质感 |
| 4 | 原型顶部状态栏不实现 | 那是原型外壳，不是 App 内容 |

### P2 已交付（2026-09-19，门禁绿 + **MuMu 12 真机走查已过**）

**真机走查（用户报告 1 项 → 修完复验）**：

| # | 问题（用户/走查发现） | 根因 | 修法 |
|---|---|---|---|
| 1 | **日历下半部分没有居中**（用户报告） | `_SelectedDaySection` 外层 `Column` 用 `CrossAxisAlignment.start`，空态块只占「最宽子项」宽度 → 块内居中、整块偏左 | 外层改 `stretch`（原型 `.empty-block` 是块级 div 占满宽）；两行文案补 `textAlign.center`；小猪按原型改 52px |
| 2 | 月份选择页迷你月缺星期表头 + 月名左对齐 | P2 只改了取色，漏了原型 `.m-wk` 与 `.m-name` 的居中/灰阶/当前月圆点 | 补 8px 星期表头行；月名居中改 `ink2`（当前月 `brandDeep` + 圆点）；格子按 `.mark`/`.today` 规则（品牌底深棕字 / 墨底白字） |

走查覆盖：日历（空态居中 / 有账日列表 + 「昨天 9月18日 周五 · 1 笔 · 支出 ¥88.88」）、
月份选择、统计（三列汇总 + donut + 图例 + 双柱）、资产（净资产卡 + 账户行 + 口径脚注）。
**结论：阻断 0**；2 处体验摩擦记入待办（见下）。

**实施明细**：

| 文件 | 状态 |
|---|---|
| `lib/core/theme/toon.dart` | ✅ 补 `ToonIconButton` 的 muted 变体（虚线灰占位图标）+ 新增 `ToonDashedBorder`（虚线描边容器，用于日历空态圆） |
| `lib/core/theme/tokens.dart` | ✅ `appBarTheme` 加底部墨色描边（原型 `.appbar`）；`snackBar` / `dialog` / `bottomSheet` / `input` 描边统一到 `Tok.bw` |
| `calendar_page.dart` | ✅ header 换描边方块图标；日汇总选 `N 笔 · 支出 ¥x`；空态改虚线圆 + 小猪 + 文案；流水列表去 `Card`（避免描边翻倍） |
| `widgets/month_grid.dart` | ✅ 格子描边 = 选中态墨色 2px；tint 底改 `Tok.redTint`/`greenTint`；今天用 `brandDeep` |
| `month_picker_page.dart` | ✅ appbar 扁平 + 只留 muted 报表占位；`‹ 上一年` / `下一年 ›` 换 `_PillButton` 描边胶囊；迷你月补星期表头与 mark/today 规则 |
| `stats_page.dart` | ✅ 月份切换换 `ToonIconButton`；收支切换 `SegmentedButton` → `ToonSeg`；汇总三列 / 图例 / 占比行统一令牌色 |
| `widgets/trend_bars.dart` | ✅ 柱改原型参数：宽 13、圆角 `6 6 3 3`、2px 墨色描边（+4px 补偿 content-box 差）；轴标签 `Tok.ink2` w800 |
| `assets_page.dart` | ✅ 净资产卡改品牌浅琥珀底（`.networth`）+ 32px 大号金额；账户行换 `ToonPress` 描边卡 |
| `widgets/account_form_sheet.dart` | ✅ 错误提示 / 删除按钮色改 `Tok.red` |
| `budget_card.dart` | ✅ 「未设预算」态不再渲染整行占位，改为日均单行 |
| `record_page.dart` | ✅ 页面 body 改纯白（原型 `pbody` 用 `--surface`，不是全局暖白画布） |

**门禁**：`flutter analyze` **0 issue**；`flutter test` **269 通过 0 skip**。

**剩余裸色值**（留 P3）：`import/presentation/import_page.dart`、`search/presentation/search_overlay.dart`。

### P3 已交付（2026-09-19 代码 · 门禁绿 + **MuMu 12 真机走查已过**）

| 文件 | 状态 |
|---|---|
| `profile/presentation/profile_page.dart` | ✅ 重写：头像卡（62 品牌圆角方块 + `PigMascot`）+ 4 条目卡（38 描边图标方块 / `ToonDashedLine` 分隔 / 未实现项「建设中」灰字）+ 品牌提示卡（`brandTint` 底 + `brandInk` 字） |
| `book/presentation/book_manage_page.dart` | ✅ 重写：FAB → AppBar `ToonIconButton`；账本行 = `ToonAvatar`（首字）+ `币种 · 类型` + 选中「品牌浅底 + 墨色描边 + 硬阴影 + 对勾」 |
| `category/presentation/category_manage_page.dart` | ✅ 重写：`SegmentedButton` → `ToonSeg`；字母头像（支出 `redTint` / 收入 `greenTint`）+ 预置标记；删除确认框换 `ToonButton` |
| `import/presentation/import_page.dart` | ✅ **报告 `AlertDialog` → 第 3 步页面**：`_StepBar` 步骤条（虚线连接 / 完成打勾）+ 虚线投放区 + 自定义勾选行（可单条取消，联动计数）+ 报告卡（44 图标方块 + 42px 大数字 + 虚线 kv 列表）；裸色值清零 |
| `search/presentation/search_overlay.dart` | ✅ `ChoiceChip` → `ToonChip`、结果条玻璃层 → `ToonCard`、引导态与无结果态按原型重写（小猪 + 「清空输入」）；裸色值清零 |
| `record/presentation/widgets/date_picker_sheet.dart` **新增** | ✅ 卡通日期弹层（抓手 + 「上限为今天，不能记未来的账」+ `MonthGrid`）；`MonthGrid` 加 `maxDate` 参数（超期格子灰显 0.3 且不可点） |
| `ledger/presentation/widgets/budget_edit_sheet.dart` | ✅ 重写：抓手 + ¥ 描边输入框（内嵌清空钮）+ 预设 `ToonChip` + 「删除预算」linkbtn + `ToonButton`（ghost / primary） |
| `assets/presentation/assets_page.dart` | ✅ 空态改卡通（虚线圆 + 小猪 + `ToonButton`）；AppBar `+` 换 `ToonIconButton`（原型 `.hdr .iconbtn`）；错误态换 `ToonButton` |
| `assets/.../widgets/account_form_sheet.dart` | ✅ **补做**（见下）；`calendar/presentation/calendar_page.dart` ✅ 网格左右 padding 10→8、月历与月结余卡留白改由卡 margin 承担（对齐原型 12px） |
| `core/theme/tokens.dart` | ✅ 补 `redInk`（原型 `#A8321F`，红底提示条上的深红文字） |
| `features/shared/name_dialog.dart` | ✅ `TextButton` → `ToonButton` |

**SPEC 自纠**：P2 记录里的「账户 sheet 已由 P2 复核」不成立 —— `git show 3d4e749` 对该文件**只有取色**（formatter + 红字改令牌），结构仍是 Material：浮动 label 的 `OutlineInputBorder`、`DropdownButtonFormField`、`TextButton` / `FilledButton`、无抓手无副标题。**P3 真机走查时发现并当场补做**：抓手 + `.s-sub` 副标题 + 小标 + 墨色描边裸输入框 + 类型改 6 个 `ToonChip` + 「当前余额 ¥x」+ 红底流水提示条（`txCount > 0` 时，省得点了删除才被拦）+ `删除账户` linkbtn + `ToonButton`。

**门禁**：`flutter analyze` **0 issue**；`flutter test` **269 通过 0 skip**。

**产品代码裸色值**：已清零。`grep -rn "Color(0x" lib/ | grep -v core/theme` 只剩 `month_hero.dart` 的 `Color(0xD9FFFFFF)` —— hero 金额的白色文字投影，属白/透明类例外。

**真机走查（MuMu 12 · 900×1600 · 320dpi · 竖屏）**：

| 页面 | 结论 |
|---|---|
| 我的页 / 分类管理 / 账本抽屉 + 账本管理 | ✅ 与原型一致 |
| 预算 sheet + 保存链路 | ✅ 预设 1000 → 保存 → 卡片变 `1,000.00` / `8.9%` / 剩余 `911.12` |
| 搜索浮层（引导 / 结果条 / 无结果小猪） | ✅ |
| 导入三步（步骤条 / 解析结果 / 单条取消联动 / 报告卡 / 「去看账单」跳转） | ✅ |
| 记一笔的日期弹层 | ✅ 抓手 + 「上限为今天」；23 日之后（24–26、27–30 及下月 1–3）灰显**且点不动**；点 20 日回填 `2026年9月20日 周日` |
| 资产页空态 | ✅ 虚线圆 + 小猪 + 「新建账户」；顺手发现 AppBar `+` 与账户 sheet 未卡通化（已修） |

**结论：阻断 0。**

