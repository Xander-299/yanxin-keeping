# acceptance — F7.18 分类树（两级 · 归档 · 迁移）

> 环境：MuMu 12（Android 12 / x86_64 / 900×1600），adb `emulator-5554`，
> QA 包 `com.teacodeman.yanxin.qa`（debug，`qaAppId` 注入）。
> 被测库：**升级前的真实数据** —— 154 笔账单 / ¥2,383.27 / 预算 ¥1,000（v3 时代写入）。
> 日期：2026-10-28 · 全程 AI 经 adb 驱动（`tool/ui_mumu.ps1` + `input tap/swipe`），
> 数据核对用 `sqlite3` 直查应用库。

## 1. 迁移安全（v3 → v4）

| 检查项 | 结果 |
|---|---|
| `PRAGMA user_version` | **4** ✓ |
| `categories` 新列 | `parent_id`、`is_archived` 都在 ✓ |
| 升级前 154 笔账单 | 升级后 `count=154`、`sum(amount_cents)=238327` **分毫未动** ✓ |
| 预算 ¥1,000 | 仍在（`budgets.amount_cents=100000`）✓ |
| 预置分类 | 11 支出 + 7 收入，**全部带 icon + #RRGGBB 颜色**（回填生效）✓ |
| 老名字映射 | 「红包」等别名保留原行，未重复插入 ✓ |

## 2. 管理页操作链路

| # | 操作 | 预期 | 实测 |
|---|---|---|---|
| 2.1 | 我的 → 分类管理 | 支出/收入 Tab + 树形列表（预置带「预置」角标） | ✓ |
| 2.2 | 新建「Chongwu」（选图标 pet + 颜色） | 入库 `icon=pet`、`color` 非空、排末尾 | ✓（sqlite 确认） |
| 2.3 | Chongwu 菜单 → 添加子分类「DogFood」 | `DogFood.parent_id = Chongwu.id`，列表缩进显示「1 个二级分类」 | ✓ |
| 2.4 | 编辑 DogFood 改颜色 | `color` 更新、icon 保持 | ✓ |
| 2.5 | 归档 Chongwu | 确认弹窗带说明；**父子一起 `is_archived=1`**；进「已归档（2）」折叠区 | ✓ |
| 2.6 | 归档区恢复 Chongwu | **父子一起恢复为 0** | ✓ |
| 2.7 | 删「通讯」（无账单） | 确认文案「它下面没有账单」→ 直接软删 | ✓ |
| 2.8 | 删「购物」（7 笔账单） | 弹「还在使用：有 7 笔账单挂在它下面」→ 两选 | ✓ |

## 3. 迁移删除（数据完整性重点）

「购物」7 笔 → 选目标「其他」→ 确认：

| 检查项 | 迁移前 | 迁移后 |
|---|---|---|
| 总笔数 / 总金额 | 154 / 238327 | **154 / 238327（不变）** ✓ |
| 「其他」笔数 | 22 | 29（+7）✓ |
| 「购物」行 | 1 未删 | 未删 0；软删行 1 ✓ |
| SnackBar | — | 「已把 7 笔账单迁到「其他」并删除原分类」✓ |

## 4. 记账页选择器

| # | 检查项 | 结果 |
|---|---|---|
| 4.1 | 只列支出分类（无「工资」等收入项） | ✓ |
| 4.2 | 已归档分类不出现 | ✓（归档态下验证） |
| 4.3 | 有子分类的一级带「›」角标，点进子级列表 | ✓ |
| 4.4 | 子级列表含「Chongwu（不细分）」兜底项 | ✓ |
| 4.5 | 选「DogFood」→ 记账页回填、保存 | ✓（sqlite：`100 | DogFood | Chongwu`） |

## 5. 过程中发现并修复的 bug

**ensurePresets 复活已删预置分类**：删掉预置「购物」约 3 秒后，provider 重新读取触发
`ensurePresets()`，它只查了未删除行 → 把「购物」又插了一条（实测出现两行，一行软删一行新插入）。

- 修复：`ensurePresets` 改为**连软删行一起查**，命中（含别名）即不再插入；
- 回归测试：「用户删掉的预置分类不会被补装复活」；
- 复测：删「旅行」→ 退出重进分类管理 → 不复活，sqlite 确认仅 1 行软删 ✓。

## 6. 复现命令

```powershell
# 构建（gradle.properties 临时降内存 + qaAppId，构建后按字节还原）
flutter build apk --debug --no-pub
adb -s emulator-5554 install -r -t build\app\outputs\flutter-apk\app-debug.apk

# 数据核对（MuMu 已 root）
adb -s emulator-5554 shell sqlite3 `
  /data/data/com.teacodeman.yanxin.qa/app_flutter/yanxin.sqlite `
  "PRAGMA user_version;"
```

## 7. 结论

F7.18 全部验收项通过；迁移零数据损失；发现 1 个补装 bug 并已修复 + 回归。
已知限制：二级分类在搜索/问答里仍按原名匹配（展示层才有「父 · 子」前缀，SPEC §9 D5）。
