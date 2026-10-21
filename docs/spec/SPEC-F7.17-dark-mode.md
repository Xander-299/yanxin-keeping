# SPEC — F7.17 深色模式（浅色 / 深色 / 跟随系统）

> **状态**：需求由用户 2026-10-20 直接下达（三条：三选项 · 默认跟随系统 · 放设置里）→
> **✅ 已交付（2026-10-20 转正 `v0.7.17`）**
> **门禁**：`flutter analyze` 等效 `No issues found!` · `flutter test` **525 passed / 6 skipped / 0 failed**
> （本批新增 17 例 + 深色对比度护栏 14 例）
> **真机走查**：2026-10-21 MuMu 12 全包完成（23 个页面 / 弹层逐页截图 + 语义树），
> 记录见 [`docs/acceptance-F7.17.md`](acceptance-F7.17.md)
> **版本**：交付后打 tag **`v0.7.17`**（沿用 `tag = v0.7.<N>` ↔ `F7.<N>` 规则；最新已占用 `v0.7.16`）
> **前置**：F7.6 起全站**只有卡通浅色一套主题**（深色在 F7.6 被删），色值一律静态常量 `Tok.*`
> **约束**：**不动 schema**（DB 仍 schemaVersion 3）· **零新 pub 依赖**（复用 `schema_meta` KV）

---

## 1. 要解决的问题

用户要「深色模式」，且必须能自己选：

| # | 需求 | 现状 |
|---|---|---|
| 1 | 三种选择：**浅色 / 深色 / 跟随系统** | 只有一个 `ThemeData`（`buildToonTheme()`），无切换 |
| 2 | **默认跟随系统** | 无「模式」概念，恒定浅色 |
| 3 | 入口在**设置**里 | 「我的 → 设置」是**占位灰条**（`_Entry(onTap: null)`，显示「建设中」） |

### 1.1 为什么这不是「加个 `themeMode` 开关」那么简单（根因）

F7.6 卡通改版时把色值做成了**编译期常量**：

```dart
abstract final class Tok {
  static const Color ink = Color(0xFF2A2A35);
  ...
}
```

全仓 **613 处** `Tok.*` 引用 / **64 个文件**。`const Color` 无法随主题变化，
而 Dart 的 `const` 表达式又要求参数是常量 —— 所以：

- **只改 `MaterialApp(themeMode:)` 不生效**：页面里的 `TextStyle(color: Tok.ink)` 仍是浅色常量；
- **把 `Tok.ink` 改成读全局变量的 getter 也不行**：`const` 构造的 widget 实例被规范化复用，
  Element 判定 `identical(old, new)` 直接跳过重建 → 切主题后不刷新（且会连带 1000+ 处 `const` 报错）；
- 唯一正确解 = **让颜色变成随 `BuildContext` 解析的实例数据**（Flutter 标准做法：`ThemeExtension`），
  逐处把 `Tok.ink` 换成 `p.ink`。

→ 本批的**主要工作量是令牌体系改造**（视觉层重构），不是设置页。

---

## 2. 目标（DoD）

| # | 可验收行为 |
|---|---|
| D1 | 「我的 → 设置 → 外观」提供**三选一**：浅色 / 深色 / 跟随系统；当前项有选中态 |
| D2 | **默认 = 跟随系统**（`schema_meta` 里**没有**该键时）；选择立即生效，无需重启 |
| D3 | 选择**持久化**（KV 键 `theme_mode`，值 `light` / `dark` / `system`），冷启动沿用 |
| D4 | **跟随系统**时，系统切深浅 App 立即跟随（`MediaQuery.platformBrightness` 变化即重绘） |
| D5 | 深浅两套主题**全部走令牌**：产品代码 0 处裸 `Color(0x…)`（`lib/core/theme/` 内除外） |
| D6 | 深色下**每个页面**都可读：首页 / 日历 / 资产 / 我的 / 记一笔 / 统计 / 报表 / 导入 / 导出 / 账本 / 分类 / 自动记账 / 新手引导 / 搜索浮层 / 各弹层 |
| D7 | 冷启动**不闪浅色**：首帧前已取到持久化模式（`main()` 预热） |
| D8 | 状态栏图标随主题反色（浅色主题深图标 / 深色主题浅图标） |
| D9 | 既有测试**全绿**（`flutter test` 0 failed）；新增用例覆盖模式解析 / 持久化 / 设置页切换 / 深色生效 / 深色对比度护栏 |
| D10 | `flutter analyze` 等效 `No issues found!`；无新增 pub 依赖；DB 仍 v3 |

## 3. 交互与口径

### 3.1 三种模式

| 值 | 中文 | 行为 |
|---|---|---|
| `light` | 浅色 | 恒浅色，忽略系统 |
| `dark` | 深色 | 恒深色，忽略系统 |
| `system`（默认） | 跟随系统 | `ThemeMode.system`：系统深浅变化立即跟随 |

- **默认值**：`schema_meta` 无 `theme_mode` 键 → `system`。**不写库**（只有用户显式选择才落盘），
  这样「从旧版覆盖安装」的老用户自然得到「跟随系统」而不是被写死成浅色。
- **非法值**（手工改库 / 未来新增枚举）：按 `system` 处理，不抛错。
- **写入时机**：点选即写（`insertOnConflictUpdate`，与 `onboarding_done` / `search_history` 同表）。
  写失败 → **本次会话仍生效**（先切 UI），下次冷启动回落到旧值；不弹错误、不阻断交互。

### 3.2 设置入口

- 新路由 **`/settings`**（全屏页，`AppBar('设置')`），从「我的 → 设置」`push`。
  「我的」里那条从**占位灰条**变为**可点**（去掉「建设中」），副标题保持「主题、默认账户、货币单位」。
- 设置页本批**只有「外观」一节**：`ToonSectionTitle('外观')` + 一张 `ToonCard` 内三行单选。
  - 每行：`图标 + 标题 + 说明 + 右侧选中标记`（`check` 圆点），点整行即切换。
  - 说明文案：浅色「一直浅色」/ 深色「一直深色」/ 跟随系统「跟随手机系统的深浅色」。
  - 选中标记**不只靠颜色**（图标 + 语义），满足「不以颜色单独传达状态」。
- 「默认账户 / 货币单位」等仍是**未做**（不本批），设置页里不放占位行，避免假入口。

### 3.3 深色视觉方向（卡通夜灯）

保留 F7.6 的卡通语言（**粗描边 + 硬阴影 + 圆胖形体**），只把「纸」换成「夜色」：

| 角色 | 浅色 | 深色 |
|---|---|---|
| 画布 `canvas` | `#FFF7EA` 暖白 | `#17151D` 夜墨 |
| 卡片 `paper` | `#FFFFFF` | `#26242F` |
| 主文字 / 描边 `ink` | `#2A2A35` 近黑 | `#F6F0E4` 暖白 |
| 次级 / 三级 | `#6C6C7C` / `#9C9CAD` | `#BDB6C7` / `#A098AE` |
| 品牌 `brand` | `#FFB627` | **不变**（琥珀是品牌锚点） |
| 品牌浅底 `brandTint` | `#FFF1D4` | `#3A2C10` |
| 品牌底上的字 `onBrand` | `#4A3103` | `#33230A`（琥珀仍亮，字仍深） |
| 浅底上的品牌字 `brandInk` | `#4A3103` | `#FFD98C` |
| 硬阴影 `shadow` | 与 `ink` 同色 | **纯黑**（浅色描边下不能用浅色阴影，否则像发光） |
| hero 主卡 | 琥珀 | **仍是琥珀**（夜里唯一的「灯」；`heroInk` 恒深棕） |

- 语义色（红 / 绿 / 蓝 / 紫）**提亮一档**（深底上更跳），对应 tint **压暗**（成为深色底）。
- 分类饼图色板**两套共用**（本就高饱和，深底上可读），账户自选色是用户数据，不动。
- 新增 3 个令牌解决「一色两用」的冲突：`onBrand`（亮琥珀底上的字）、`shadow`（硬阴影）、
  `onRed`（实心红底上的字 / 图标）；另加 `veil`（品牌底上的半透明白胶囊，深浅都用白）、
  `decorInk`（**恒深**的插画描边 —— 小猪 / 星星画在品牌底上，不能跟着 `ink` 反色）。

### 3.4 状态栏 / 启动

- `AppBarTheme.systemOverlayStyle`：浅色主题 → `SystemUiOverlayStyle.dark`（深图标），
  深色主题 → `.light`（浅图标）。
- Android 已有 `values-night/` 启动主题（系统深色时用 `Theme.Black.NoTitleBar`），
  **系统级**深色启动不变；**App 内强制深色 + 系统浅色**时，系统启动白屏无法从 Dart 侧改，
  仅靠 `main()` 预热把首帧前的空窗压到最短（D7）。

---

### 3.5 对比度门槛（2026-10-21 追加 · 用户反馈「深色下部分字看不清」）

改之前先**量化**：把两套调色板所有「前景 × 背景」组合按 WCAG 相对亮度算一遍 →
深色**大多数反而优于浅色**。问题不在「整体变差」，在 5 处具体的坑（都跟「底色变了」有关）：

| # | 坑 | 深色修前 | 修后 |
|---|---|---|---|
| 1 | hero 的「收入 / 结余」气泡：减淡层用 `paper@0.55`，深色 `paper` 近黑 → 气泡被压暗 | 2.12 | 7.4 |
| 2 | hero / 主按钮 / 选中 tab / 日历选中日的描边用 `p.ink`（深色下是暖白） | 1.26 | 8.08 |
| 3 | 底栏选中项的**标签**用 `onBrand`（深棕），却画在近黑纸底上 | ≈1.1 | 9.6 |
| 4 | 三级灰 `ink3`（底栏标签 / hint / 8px 辅助字） | 3.96 | 5.52 |
| 5 | 左滑「删除」白字压在提亮后的红上 | 2.78 | 6.35 |

**由此确定三条硬规则**（写进 `HANDOFF.md` 不变量，测试兜底）：

1. **hero（恒琥珀底）只能用 hero 家族色**：减淡层 `veil@α`（白，两套主题都是「变浅」）；
   描边 / 硬阴影 / 插画描边 `inkOn(brand)`（恒深）；字 `heroInk`（恒深棕）。**不许出现 `paper` / `ink`**。
2. **描边跟着底色走**：`p.inkBorder(on: 底色)` —— 亮底自动用 `decorInk`，暗底用 `ink`。
   凡是在琥珀 / 品牌浅底 / 用户自选色上描边，都要传 `on:`。
3. **前景色必须配对的底**：`onBrand` 只能压在 `brand` 上；`brandInk` 用于浅底；`onRed` 用于实心红；
   `redInk` 用于 `redTint`。放错底（如 `onBrand` 放纸底）在浅色下看不出来，深色下直接消失。

**门槛**：正文 / 小字 ≥ **4.5:1**；描边 / 图形 / 大字 ≥ **3.0:1**。
护栏：`test/core/theme/palette_contrast_test.dart`（14 例）。

> 浅色 `ink3` 是 F7.6 遗留的 **2.70:1**（未达 AA）—— 提到 4.5 会让它与 `ink2` 几乎同色、层级丢失，
> 本批**不动**，只钉住下限不更差，待设计侧决定。
> 深色 `ink3` 已从 `#857F91` 提亮到 `#A098AE`（3.96 → 5.52），因为深色下它是「能定高一点」的。

---

## 4. 不做

- ❌ 不做「自定义配色 / 主题色选择 / 纯黑 AMOLED / 定时切换（日落到日出）」
- ❌ 不做主题切换动画（`ThemeData` 渐变会带来额外重建；Material 默认即时切换）
- ❌ 不做「跟随系统字体大小」等无关设置（设置页只做外观一节）
- ❌ 不改数据库（不新增表 / 不升 schema / 不写迁移）
- ❌ 不引第三方主题包（零新依赖）

---

## 5. 文件清单

| 文件 | 动作 |
|---|---|
| `lib/core/theme/palette.dart` | **新增**：`ToonPalette extends ThemeExtension`（浅 / 深两套）+ `context.toon` + `hard / inkBorder(on:) / cardDeco / inkOn` 助手 |
| `lib/core/theme/tokens.dart` | 改：删掉颜色常量，只留几何（`bw` / `rXl` / `rLg` / `rMd` / `rSm`）；`buildToonTheme(ToonPalette, Brightness)` |
| `lib/core/theme/toon/*.dart` | 改：默认参数由常量改为 `null` + build 内解析调色板（保持 `const` 构造可用）；自定义画笔颜色改由构造注入 |
| `lib/core/theme/theme_mode.dart` | **新增**：`ToonThemeMode`（`light/dark/system`）+ `parse` / `storageValue` / `materialMode` 纯函数 |
| `lib/features/settings/application/theme_controller.dart` | **新增**：`themeModeProvider`（AsyncNotifier，读 KV / 点选写 KV，失败回落 system） |
| `lib/features/settings/presentation/settings_page.dart` | **新增**：设置页（外观三行单选，行带 `themeMode_<name>` key） |
| `lib/app.dart` | 改：`ConsumerStatefulWidget`，`theme` / `darkTheme` / `themeMode`；新增 `/settings` 路由 |
| `lib/main.dart` | 改：`ProviderContainer` 预热主题后 `UncontrolledProviderScope` |
| `lib/features/profile/presentation/profile_page.dart` | 改：「设置」条目从**占位灰条**点亮 → `push('/settings')`；版本号升 `v0.7.17` |
| 其余 ~60 个 `lib/features/**` 文件 | 改：`Tok.<颜色>` → `p.<颜色>`（调色板实例），`const` 就地收敛；琥珀底描边补 `on:` |
| 测试 | **新增 5 个文件 / 31 例**：`theme_mode_test`（解析）· `toon_theme_test`（两套主题 + 跟随系统）· `theme_controller_test`（默认 / 落库 / 冷启动 / 容错）· `settings_page_test`（三行单选）· `palette_contrast_test`（WCAG 护栏） |

---

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| 613 处替换漏改 → 深色下局部仍白底 | **不给 `Tok` 留颜色常量**：编译期报错即清单；analyze 归零才算完 |
| `const` 去掉后 lint `prefer_const_constructors` 反弹 | 只对「表达式内含 `p.`」的 `const` 就地收敛，其余保持 const |
| 深色对比度不足（尤其 tint 上的字） | 逐令牌定 `onXxx` 语义色；深色 tint 压暗 + 前景提亮；**WCAG 量化 + 14 例护栏测试**（见 §3.5） |
| 自定义绘制（小猪 / 饼图 / 趋势柱 / 虚线）拿不到 context | 画笔颜色改由构造函数注入（`ink` / `track` 等参数），build 里从调色板取 |
| 切主题后页面不刷新 | 全部颜色经 `context.toon`（= `Theme.of`）解析 → 自动建立 InheritedWidget 依赖 |
| 冷启动闪浅色 | `main()` 在 `runApp` 前 `await` 一次主题读取（失败回落 system）；系统级启动图由 Android 深浅决定，Dart 侧改不了（已登记） |

---

## 7. 验收（真机 / 测试）

- [x] 设置页三选一，选中态正确；杀进程重进仍是上次选择（`settings_page_test` / `theme_controller_test`）
- [x] 默认（新装 / 从未选过）= 跟随系统；系统切深色 → App 立即变深（`toon_theme_test`）
- [x] 深色下逐页走查：首页 / 日历 / 资产 / 我的 / 记一笔 / 统计 / 报表 / 导入 / 导出 / 账本 / 分类 / 自动记账 / 新手引导 / 搜索浮层 / 记账键盘 / 各底部弹层
      **（2026-10-21 MuMu 12 全包完成，见 `docs/acceptance-F7.17.md`）**
- [x] 深色下硬阴影为黑、描边为暖白、hero 仍为琥珀且文字可读（`toon_theme_test` 断言令牌级）
- [x] `flutter analyze` 等效 `No issues found!`；`flutter test` 全绿（525 passed / 6 skipped / 0 failed，本批新增 31 例：17 功能 + 14 对比度护栏）
