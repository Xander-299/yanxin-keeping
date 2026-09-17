# SPEC — F7.5-b 资产页（待签字）

> 状态：**（已签字 2026-09-17）** — 范围「按 SPEC 全量」；初始余额**不允许负数**。
> 起草：2026-09-17 · A 机（`D:\Tencent\yanxin-flutter`，HEAD `7bc6e55`）

---

## 1. 要解决的问题

底栏第 4 个 tab「资产」目前是 `PlaceholderPage('资产')`，纯占位。
但**账户数据早已入库**：`accounts` 表（schema v1）、`AccountRepository` 完整 CRUD、新建账本自动带一个「现金」账户、
账单导入会自动建「导入账户」、记一笔默认写 `accounts.first`。
也就是说：**账户一直存在，只是没有界面**。用户看不到自己有多少钱、分布在哪些账户，也改不了初始余额。

## 2. 目标（DoD）

1. 「资产」tab 换成真实页面：净资产 + 账户余额列表，**数据源全部真实**（无假数字、无「示例」chip）。
2. 账户可增 / 改 / 删（软删），余额随流水实时正确。
3. 金额口径有纯函数支撑并单测覆盖（transfer 不计、已删不计、跨账户不串）。
4. **不改 schema**（`schemaVersion` 仍为 2，不动 `tables.dart`、不跑 `build_runner`）。
5. 门禁：`flutter analyze` 0 issue；`flutter test` 全绿（含新增单测）。

## 3. 数据与口径

### 3.1 取数

一次载入当前账本全量，**内存聚合**（与统计页 `listByBook` 同做法，量级万级）：

- `accountRepository.listByBook(bookId)` — 未删账户，按 `sort_order, created_at` 升序
- `transactionRepository.listByBook(bookId)` — 未删流水，全时间

### 3.2 余额口径（纯函数，可单测）

```
balanceCents(account) = account.initialBalanceCents
                      + Σ income.amountCents      （收入进账）
                      - Σ expense.amountCents     （支出出账）
                      + 0                          （transfer 不计，见 §7）
netCents = Σ balanceCents(每个未删账户)
```

- 流水只计入 `accountId == account.id` 的；已软删流水（`deleted_at` 非空）不计 —— 取数层已过滤。
- `transfer` 类型**不计入任何账户**（方向语义未定，`transfer_group_id` 仍是预留字段）。
- 余额可为负（透支 / 信用卡），展示按 §4 着色，不做特殊业务处理。

### 3.3 排序与统计

- 账户列表：沿用仓储返回顺序（`sort_order` → `created_at`），**不按余额排序**（避免跳动）。
- 净资产卡副标题：`N 个账户`。
- 另给每张账户卡一行「累计收入 / 累计支出」小字（同一批流水即可算出，零额外查询）。

## 4. 交互

| 位置 | 行为 |
|---|---|
| 底栏「资产」 | 进入真实资产页（AppBar 标题「资产」，右上 `+` 图标 = 新增账户） |
| 顶部净资产卡 | 大号金额 `centsToYuan(net, group: true)`；**≥0 琥珀橙 `#FFAF38`，<0 红 `#FF6B6B`**；副行「N 个账户」 |
| 账户行 | 圆底图标（按 type）+ 账户名 + 类型中文名；右侧余额（<0 红，≥0 常规） |
| 点账户行 | 打开编辑 sheet（名称 / 类型 / 初始余额 + 红色「删除账户」） |
| AppBar `+` | 打开新增 sheet（同上，无删除按钮） |
| sheet 保存 | 校验 → 写库 → bump epoch → 列表自动刷新 + SnackBar「已保存 / 已新增 / 已删除」 |
| 删除 | **账户下有未删流水时禁止删除**，提示「该账户下还有 N 笔流水，请先改到别的账户」；否则二次确认后软删 |
| 空态 | 无账户时居中提示 + 「新建账户」按钮 |
| 账本切换 | controller watch 当前账本，切账本后重算 |

**账户表单字段**

- 名称：`trim` 后非空（重名允许，不拦）
- 类型：下拉，6 个 `accountTypes` → 现金 / 储蓄卡 / 信用卡 / 支付宝 / 微信 / 其他
- 初始余额：元输入，正则 `^\d+(\.\d{1,2})?$`（**不支持负数，见 §7**），留空 = 0

## 5. 文件清单

新增：

| 文件 | 职责 |
|---|---|
| `lib/features/assets/application/asset_aggregate.dart` | 纯函数：`AssetItem` / `AssetSummary` / `buildAssetSummary(accounts, txs)` |
| `lib/features/assets/application/assets_controller.dart` | `AsyncNotifier<AssetSummary>`：watch 当前账本 + epoch，取数聚合 |
| `lib/features/assets/presentation/assets_page.dart` | 页面：净资产卡 + 账户列表 + 空态 |
| `lib/features/assets/presentation/widgets/account_form_sheet.dart` | 新增 / 编辑 / 删除的底部表单 |
| `lib/core/providers/data_epoch.dart` | `dataEpochProvider`（`StateProvider<int>`）+ `bumpDataEpoch(ref)` |

修改：

| 文件 | 改动 |
|---|---|
| `lib/app.dart` | 壳路由分支 3 的 `PlaceholderPage('资产')` → `AssetsPage` |
| 记一笔保存 / 导入完成 / 流水删除 / 账户 CRUD | 写操作成功后 `bumpDataEpoch(ref)` |

> **为什么引入 epoch**：HANDOFF 已记载「漏刷 `statsProvider` 出过 bug」——手工逐个 `refresh()` 是已知脆弱点。
> 资产页改为 watch 一个数据版本号，写操作只需 bump 一行，未来新页面零成本接入。
> **本次不动 stats / ledger 的既有 refresh 调用**（避免回归）。

## 6. 测试

`test/features/assets/asset_aggregate_test.dart`（纯函数，≥9 条）：

1. 收入进账：初始 100 元 + 收入 50 元 → 150 元
2. 支出出账：初始 100 元 - 支出 30 元 → 70 元
3. transfer 不计（余额不变）
4. 多账户互不串账（A 的流水不进 B）
5. 净资产 = 各账户余额之和（含负余额账户）
6. 账户无流水 → 余额 = 初始余额
7. 净资和为负 → `netCents < 0`
8. 空账户列表 → `netCents == 0`、`items` 为空
9. 累计收支小字与余额自洽（`initial + income - expense == balance`）

可选（若时间允许）：controller 级测试「新增账户后列表多一行」用内存库跑。

## 7. 风险 / 取舍

| 取舍 | 说明 |
|---|---|
| **transfer 不计余额** | `transactions.transfer_group_id` 仍是预留字段，转账的「从哪到哪」没有落库语义；强行计入会算错。转账记账不在本 SPEC |
| **初始余额不允许负数** | `yuanToCents` 正则不接受 `-`，改它会松动「金额恒正」铁律。信用卡期初欠款只能先记支出，留待后续 |
| **余额是全时间累计** | 不做月份筛选；资产是存量概念，不是流量 |
| **epoch 只接资产页** | stats / calendar / ledger 保持现状，本次不重构，避免回归 |
| **不改 schema** | 无新表、无新字段，`database.g.dart` 不动，老库升级零风险 |

## 8. 工期切片

- **S1** `asset_aggregate.dart` + 9 条单测（可独立跑绿）
- **S2** `assets_controller` + `assets_page`（只读展示，替换占位）
- **S3** `account_form_sheet`（增 / 改 / 删）+ epoch 接线
- **S4** 门禁（analyze + test）→ CHANGELOG / HANDOFF / todo 回写 → 真机走查（可选）→ `git push`
