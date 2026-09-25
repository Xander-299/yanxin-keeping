# SPEC — F7.8 流水左滑删除

> **状态：已交付（2026-09-25，`v0.7.11` 已打 tag 推远端）** —— 三项关键决策由用户裁定，见 §7；
> 实现 / 门禁 / 走查记录见 §8。
> **版本**：已打 tag **`v0.7.11`**（tag 对象 `6357de1` → 提交 `e984023`；沿用递增：F7.7 五批已占用 `v0.7.7`–`v0.7.10`）。
> **前置**：F7.7 五批全部交付（`v0.7.10`，361 全绿 + 走查 0 崩溃）。
> **不动 schema / 零新依赖**（本项目硬约束）。

## 1. 要解决的问题

流水的删除入口是**长按**（`TxTile.onLongPress` → `confirmDeleteTx`），共 3 处：
首页「本月账单」、日历页选中日账单、搜索浮层结果列表。问题：

1. **手势隐藏**：没有任何视觉提示，新用户不知道长按能删。
2. **语义撞车**：F7.7 E 批把「长按日历格子」定义为**记这一天的账**，而同一页面下方的账单行长按却是**删除** —— 同一屏两个长按两种结果。
3. 用户明确要求：**改成左滑删除**。

## 2. 目标（DoD）

| # | 可验收行为 |
|---|---|
| D1 | 3 处列表行**左滑**（内容向左移动）露出右侧红色「删除」按钮 |
| D2 | 点该按钮 → 弹出既有「删除这笔」确认框 → 确认才软删（复用 `confirmDeleteTx`） |
| D3 | 取消 → 行**回弹关闭**，数据不变（库里 `deleted_at` 仍为空） |
| D4 | **一次只允许一行展开**；点该行任意位置 → 收起（**不**跳编辑页）；点别的行 → 当前行收起 |
| D5 | 行上**长按不再删除**（3 处 `onLongPress` 全部摘掉） |
| D6 | 竖向滚动照常（首页 / 日历页 / 浮层），日历页月历**左右滑翻月**不受影响 |
| D7 | 报表页流水行**仍只读**、不可滑（SPEC-F7.7 §A.4 口径不变） |

## 3. 交互口径（实现前定的硬数字）

- **按钮宽度** `kSwipeActionWidth = 84`（容得下图标 + 「删除」两字）。
- **位移** `d ∈ [0, 84]`，只能左滑（内容左移），右滑不回弹过界。
- **开合判定**（纯函数 `resolveSwipeOpen`，可单测）：松手时 `d ≥ 84 × 0.45` **或** 速度 `≤ -350 px/s` → 全开；否则回 0。
- **动画**：160 ms `Curves.easeOut`（关闭同）。
- **视觉**：`Tok.red` 底 + 白色 `Icons.delete_outline_rounded` + 「删除」白字（12 / w800）。卡片已有 `clipBehavior: Clip.antiAlias` → 红底不会溢出圆角。
- **确认框**：沿用 `Features/ledger/.../tx_delete_dialog.dart`（文案「删除这本…」不动），不加新文案。
- **action 完成后一律收起**（删除成功时该行随数据刷新消失；取消时视觉上就是回弹）。

## 4. 不做

- ❌ **不做「滑走即删」**（`Dismissible` 式）—— 软删除不可恢复，误滑代价高（用户裁定）。
- ❌ 不做右滑手势（不留「编辑 / 收藏」槽位）。
- ❌ 不做多按钮（删除是唯一动作）。
- ❌ 不做「撤销」SnackBar（确认框已足够）。
- ❌ 报表页不加左滑（只读口径不变）。
- ❌ 不引 `flutter_slidable` 等新依赖，手写滑动件。
- ❌ 不改 schema、不新增路由。

## 5. 文件清单

| 文件 | 动作 |
|---|---|
| `lib/features/ledger/presentation/widgets/swipe_action_row.dart` | **新增**：`SwipeActionRow`（通用左滑露出单个动作的行）+ 顶层纯函数 `resolveSwipeOpen` |
| `lib/features/ledger/presentation/widgets/tx_group_list.dart` | **改**：`TxGroupList` → `StatefulWidget`（管「单开」）；每行包 `SwipeActionRow`；`TxTile` 摘掉 `onLongPress` 参数与文档 |
| `lib/features/calendar/presentation/calendar_page.dart` | **改**：`_SelectedDaySection` 日账单行接入（自带单开状态）；`TxTile` 不再传 `onLongPress` |
| `test/widget_test.dart` | **改**：「长按删除」例 → 「左滑 → 点删除 → 确认 → 列表消失」 |
| `test/features/search/search_overlay_test.dart` | **改**：「长按结果可删」例 → 同上 |
| `test/features/ledger/swipe_action_test.dart` | **新增**：`resolveSwipeOpen` 单测 + 左滑露出 / 取消不删 / 单开 等 widget 用例 |

**不改**（走 `TxGroupList` 自动获得）：`home_page.dart`、`search_overlay.dart`、`reports/*`（只读）、`tx_delete_dialog.dart`。

## 6. 风险

| 风险 | 处置 |
|---|---|
| 横向拖动吃掉竖向滚动 | 外层只注册 `onHorizontalDrag*`，Flutter 手势竞技场按轴判定；真机验「竖向能滚」「月历能翻月」 |
| 打开状态下点行误跳编辑页 | 打开时在行上方盖一层透明 `GestureDetector` 只收 `onTap` → 收起；行本体 `IgnorePointer` |
| `TxTile` 背景透明（白由外层卡片提供） | 滑动时行左移，左侧露出的仍是父级白卡 → 视觉一致；`Stack` 默认裁剪移出部分 |
| widget 测试 drag 后动画未完 | `await tester.pumpAndSettle()`；断言按钮文案用 `find.text('删除')` 需注意确认框里也有「删除」→ 用行内 key / 先断言按钮区 |
| 既有测试依赖长按 | 2 处（`widget_test.dart`、`search_overlay_test.dart`）本轮一并改 |

## 7. 签字

**2026-09-25 用户裁定（三项）**：

1. **长按取消，只留左滑** —— 行上长按不再有反应（长按仍保留给日历格子「记这一天的账」）。
2. **滑出红色「删除」按钮 → 点按钮才删** —— 不采用「滑走即删」，也不采用「滑到底弹确认框」。
3. **作用范围 = 首页 + 日历日账单 + 搜索结果 3 处** —— 口径一致；报表页保持只读。

## 8. 实施记录（2026-09-25）

**实现**（提交 `8d8dc8e`）

- 新增 `lib/features/ledger/presentation/widgets/swipe_action_row.dart`：
  `SwipeActionRow`（`Stack` + 右侧钉住的 84 px 动作区 + `Transform.translate` 左移内容 +
  `AnimationController` 160 ms 吸附）+ 顶层纯函数 `resolveSwipeOpen`；
  单开靠外层传进来的 `ValueNotifier<String?>`；展开时行本体 `IgnorePointer`，
  整行点击落到外层的「收起」上。
- `TxGroupList` → `StatefulWidget`（持单开协调器）；每行包 `SwipeActionRow`；
  `onDelete` 类型由 `ValueChanged<TxRow>` 改为 `Future<void> Function(TxRow)`（动作完成即收起）。
- `calendar_page.dart` 的 `_SelectedDaySection` → `StatefulWidget`，同款接入。
- `TxTile` 摘掉 `onLongPress`（长按仍保留给 `MonthGrid` 的「记这一天的账」）。
- 报表页 `report_group_list.dart` **未改**（不传回调 → 不包 `SwipeActionRow`）。

**门禁**

- `flutter analyze` 等效（`python tool/dart_analyze_fallback.py`）：**No issues found** ✅。
- 测试：**改 2 例**（`widget_test.dart`、`search_overlay_test.dart` 的长按用例 → 左滑口径）
  + **新增 10 例**（`test/features/ledger/swipe_action_test.dart`：`resolveSwipeOpen` 5 + 行行为 5）
  → 本机纯 `test()` 5 例实测全绿；含 `testWidgets` 的全量 **371 passed / 0 skipped**
  （✅ **2026-09-25 用户终端全量通过**）。

**真机走查** —— `docs/acceptance-F7.8-swipe-delete.md`（MuMu 12 / 900×1600 @320dpi，AI 经 adb 全包）

- **SPEC §2 的 D1–D7 全部通过**；0 崩溃。
- 🔴 **抓到 1 个只有真机能发现的视觉 bug**：`TxTile` 自身没有背景色（白来自外层白卡），
  而动作区钉在 `Stack` 底层 → **未滑开时红色直接透出行**。修法：行包 `ColoredBox(color: Tok.paper)`。
- ⚠️ 环境坑：装包后立即注入 adb 输入可能不生效（tap/swipe 无反应但 UI 正常）→
  `am force-stop` 重启 App 即恢复，**非代码问题**。
- 走查造的 2 笔软删已还原（改库前备份 `yanxin.sqlite.bak-20260925`），重启复核数据一致。

**版本**：已打 tag **`v0.7.11`**（2026-09-25 推远端，tag 对象 `6357de1` → 提交 `e984023`；
沿用递增，F7.7 五批已占 `v0.7.7`–`v0.7.10`）。**回滚**：`git checkout v0.7.10`。
