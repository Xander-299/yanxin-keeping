# SPEC — F7.9 记一笔：底部吸底保存 + 去顶部保存入口

> **状态：已签字（2026-09-25）** —— 用户在四个候选方案中明确裁定，见 §7。
> **版本**：实现走查通过后打 tag **`v0.7.12`**（沿用递增：F7.7 五批占 `v0.7.7`–`v0.7.10`，F7.8 占 `v0.7.11`）。
> **前置**：F7.8 左滑删除已交付（`v0.7.11`，371 全绿 + 走查 0 崩溃）。
> **不动 schema / 零新依赖**（本项目硬约束）。

## 1. 要解决的问题

记一笔页当前有**两个保存入口**，都调 `_save()`：

| 位置 | 实现 | 形态 |
|---|---|---|
| AppBar 右上角 | `record_page.dart:251-263` `TextButton('保存')` | 文字链接（弱化） |
| 表单底部 | `record_page.dart:367-371` `ToonButton(block: true)` | 全宽主按钮（强化） |

这是原型 1:1 的结果（`modao/yanxin/screens.js:182` 与 `:221` 都挂 `data-act="save-record"`）。
顶部入口的存在理由是**兜底**（实现注释：大屏 / 横屏下底部按钮会被折叠到视口外）——
但代价是页面上出现两个语义相同的入口，用户会疑惑「这算不算重复」。

用户裁定：**把底部按钮改成悬浮吸底（常驻视口）+ 去掉顶部入口**。
吸底后「底部按钮被折叠到视口外」这一前提不成立 → 顶部兜底入口失去存在理由，可安全移除。

## 2. 目标（DoD）

| 编号 | 验收点 | 判定方式 |
|---|---|---|
| D1 | AppBar 里**不存在**「保存」 | `find.widgetWithText(AppBar, '保存')` → `findsNothing` |
| D2 | 底部主按钮**未滚动时**即在视口内 | `tester.getRect` 的 `top/bottom` 落在视口高度内 |
| D3 | 内容**滚到底**之后按钮位置不变 | 滚动前后两次 `getRect().top` 相等且仍在视口内 |
| D4 | 备注聚焦、键盘弹起时按钮**仍可见** | 真机走查（widget 测试测不了真实键盘） |
| D5 | 点按钮 = `_save()` | 金额空 → 「请输入金额」；正常 → 落库 + `pop(true)` |
| D6 | 文案随模式切换 | 新建「记一笔」/ 编辑「保存修改」 |
| D7 | `_saving` 期间按钮禁用 | `onPressed == null` |
| D8 | 零新依赖 / 不动 schema / 无裸色值 / 0 崩溃 | analyze + 走查 |

## 3. 交互口径（实现前定的硬数字）

- **载体**：**`body` 内 `Column` = `Expanded(SingleChildScrollView) + 吸底栏`**。
  ⚠️ **前提核查（实现时修正 SPEC）**：初稿写的是 `Scaffold.bottomNavigationBar`，**不成立** ——
  Flutter 的 `_ScaffoldLayout` 把 `bottomNavigationBar` 定位在 `size.height - h`（贴屏幕底），
  只有 **body** 会被 `viewInsets.bottom`（键盘）压缩 → **键盘弹起时吸底栏会被键盘盖住**，
  反而比原来更差。而 body 内的 `Column` 会随 body 一起被压缩 → 吸底栏自动落在键盘上方。
  也**不用** `Stack` + `Positioned`（会遮内容、还得手算补偿 padding）。
- **容器**：`Container(color: Tok.paper, border: Border(top: BorderSide(color: Tok.ink, width: Tok.bw)))`
  —— 与 AppBar 底部描边（`tokens.dart` 的 `appBarTheme.shape`）对称，视觉上像一页的页脚。
- **内边距**：吸底栏 `Padding(EdgeInsets.fromLTRB(16, 12, 16, 12))`（底部安全区由外层 `SafeArea` 兜）。
- **按钮**：`ToonButton(block: true)`，`label = _isEdit ? '保存修改' : '记一笔'`。
- **内容区**：`SingleChildScrollView` 的 bottom padding `24 → 16`（按钮已移出，无需再留空间）。
- **提示文案**：`「保存后首页 / 日历 / 统计 / 资产同步刷新」`保留在**滚动内容末尾**，不进吸底栏（吸底栏只放按钮，保持干净）。
- **键盘**：靠 Scaffold 默认 `resizeToAvoidBottomInset: true` 压缩 body 实现（见上「载体」）。

## 4. 不做

- ❌ 不做「向下滚动时自动收起 / 向上滚动才出现」的滚动联动吸底（复杂度不值，收益低）。
- ❌ 不改 `_save()` 的业务逻辑（校验、写库、刷新链路一行不动）。
- ❌ 不动备注 / 日期 / 账户 / 分类字段与金额键盘。
- ❌ 不给其他页面（账户表单弹层、预算弹层、导出弹层）套同一套吸底 —— 它们本来就是弹层，天然贴底。

## 5. 文件清单

| 文件 | 改动 |
|---|---|
| `lib/features/record/presentation/record_page.dart` | 删 AppBar `actions`；body 末尾移出 `ToonButton`；新增 `bottomNavigationBar` |
| `test/features/record/record_save_entry_test.dart` | **重写**：口径由「AppBar 常驻」改为「吸底常驻 + AppBar 无保存」 |
| `test/features/record/record_account_test.dart` | `_tapSave()` 改点吸底按钮（`find.widgetWithText(ToonButton, …)`） |
| `test/widget_test.dart` | **删掉**两处 `ensureVisible(find.widgetWithText(ToonButton, '记一笔'))` |
| `test/features/calendar/calendar_page_test.dart` | **删掉**一处同款 `ensureVisible` |

## 6. 风险

| 风险 | 处置 |
|---|---|
| ⚠️ **键盘弹起时吸底栏被盖住**（初稿的 `bottomNavigationBar` 方案必踩） | 改走 **body 内 `Column`**（body 会被 `viewInsets.bottom` 压缩）；走查实测备注聚焦后的截图 |
| ⚠️ **`tester.ensureVisible` 对不在 `Scrollable` 内的元素会抛错**（`Scrollable.of` 返回 null → 断言失败） | 吸底按钮**不在 `Scrollable` 内**（它在 `Expanded` 的兄弟节点） → 所有指向它的 `ensureVisible` **必须删除**（这是本批最容易漏的坑，§5 已逐处列出） |
| 吸底栏占用高度 → 小屏可视内容变少 | 走查重点：MuMu 12 / 900×1600 @320dpi（逻辑 450×800）下 4 个字段 + 键盘是否全可见、是否需要滚动 |
| 内容不再被按钮挤压 → 视觉重心变化 | 走查截图留档对比 |
| `_saving` 禁用态在吸底栏里的视觉反馈 | 走查确认禁用时按钮变淡、不可点 |

## 7. 签字

**用户裁定（2026-09-25，本轮对话）**：在「保持现状 / 去掉顶部 / 去掉底部 / 底部改悬浮吸底 + 去顶部」四个候选中，明确选择
→ **「底部改悬浮吸底（sticky）+ 去顶部」**。

即：底部主按钮**常驻视口**，顶部 AppBar 的「保存」入口**删除**。

## 8. 实施记录

（实现 + 门禁 + 走查完成后回填）
