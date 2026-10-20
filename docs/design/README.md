# 设计参考图（历史）

⚠️ **这里的三张图是 F4.5 时期的深色版原型，已被 F7.6 的「卡通浅色」取代** ——
不要拿它们当当前 UI 的样子看，也不要直接放进 README / 网页介绍当截图。

| 文件 | 内容 | 状态 |
|---|---|---|
| `home_ui.jpg` | 首页（深色底 + 琥珀 hero + 预算卡） | 历史，F4.5 |
| `calendar.jpg` | 日历页（深色） | 历史，F7.1 |
| `calendar_select.jpg` | 日历选中态（深色） | 历史，F7.1 |

当前视觉的唯一依据是**卡通浅色**那一套设计令牌，落库在
[`lib/core/theme/tokens.dart`](../../lib/core/theme/tokens.dart)（`Tok.*`）与
[`lib/core/theme/toon/`](../../lib/core/theme/toon/)（通用件）。
产品代码里不出现裸 `Color(0x…)`。

**真实截图**已经放在 [`docs/shots/`](../shots/)（首页 / 日历 / 统计，540 宽 JPEG）。
补新截图时同样命名 `<页面>.jpg` 放进去，README 与 `docs/index.html` 都已接好。
