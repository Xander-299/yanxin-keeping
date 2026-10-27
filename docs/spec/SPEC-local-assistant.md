# SPEC（**已签字**）：阶段二 · 本地财务问答 —— M1「问账本」

> **签字**：2026-10-27，用户原话「签字，先做M1看看效果」。
> **签的是什么**：
> 1. **分层架构**（见 §2）：T0 无模型（默认）/ T1 本地模型（可选组件）/ T2 云端（不做，只留接口）；
> 2. **模型不进 APK**：引擎进包（+4.1 MB/ABI），模型 0.77–1.1 GB 由用户自行导入；
> 3. **D4 分发 = a（手动导入 `.gguf`）**，保住「正式包无 `INTERNET`」这条卖点；App 内下载留到 M3 单独立项；
> 4. **先做 M1**（T0），验收标准见 §5。
>
> 依据：`Prompt.md` 阶段二、[`SPEC-local-ai.md`](SPEC-local-ai.md) §4/§10、
> [`docs/dev/llm-benchmark.md`](../dev/llm-benchmark.md)（体积与性能均为实测）。

---

## 1. 为什么先做 M1（不装模型的那一层）

用户提的核心顾虑是「本地部署 LLM，App 体积大、成本高」。实测把账拆开：

| 项 | 实测 | 结论 |
|---|---|---|
| llama.cpp 引擎（arm64，strip 后） | **+4.1 MB**（`libllama` 2.4 + `ggml` 1.8），双 ABI 约 +7–9 MB | 可接受（现包 64.6 MB） |
| 模型权重（Q4_K_M） | Qwen2.5-1.5B **1066 MB** / Qwen3-1.7B 1056 MB / Gemma-3-1B 769 MB | **绝不进 APK**，是用户可选资产 |
| 端上速度 | 生成 7.4 tok/s、**首 token 3.5–5.1 s**（177 token 上下文） | 只够「一段话解释」，不够聊天 |

而 `Prompt.md` 阶段二的 7 个示例问题里，**6 个本质是算术/统计**（本月多少、某分类多少、预算剩多少、
哪类涨最多、多久攒够钱）。这些**不该让模型算**——基准实测里模型会编数（Gemma 把「已花 4520.36」
说成「超支 4520.36」；Qwen2.5 超支额对、每日额度编）。

⇒ 所以 M1 = **用规则 + 账本计算回答**，零体积、零等待、算得准；M2 再让可选模型只做「措辞」。
这也让「不装模型」的用户拿到 100% 的功能，而不是一个「残废版」。

## 2. 架构（三层，模型是可选组件）

```
用户一句话
   │
   ├─ T0（默认，M1 已交付）
   │    parseFinanceIntent（纯函数：选区间 + 选口径）
   │      → TransactionRepository.listByRange / BudgetRepository.getForMonth
   │      → 既有口径纯函数：summarize / categoryBreakdown / buildBudgetView
   │      → 中文回答（模板）
   │
   ├─ T1（M2，可选安装 .gguf）
   │    FinanceData → 事实清单（≤80 token）→ LlmProvider（llama.cpp JNI，流式）
   │      → 模型只把事实改写成话；**回答里的数字必须能对上事实清单**，否则丢弃重来
   │
   └─ T2（暂不做）
        云端，用户显式开启；关闭后本地功能不受影响
```

**红线**（沿用 HANDOFF 不变量）：

1. **数字只有一个来源**：Dart 纯函数。模型不参与任何计算，OCR / 模型都不写库；
2. **不装模型也能用**：T0 是默认路径，不是降级路径；
3. **不认识就说不认识**：绝不生成没查过的金额。

## 3. M1 交付（文件级）

| 文件 | 作用 |
|---|---|
| `lib/features/assistant/application/finance_intent.dart` | 一句话 → 意图（7 类）+ 时间区间 `Period`；中文数字归一；分类别名 |
| `lib/features/assistant/application/finance_answer.dart` | 意图 + 数据 → 中文回答（标题 / 主数字 / 事实行 / 叙述 / 追问建议）；`kExampleQuestions` |
| `lib/features/assistant/application/assistant_controller.dart` | Riverpod 会话编排：解析 → 查库（`listByRange` / `getForMonth`）→ 出答案 |
| `lib/features/assistant/presentation/assistant_page.dart` | 问答页：空态示例 chips、问题气泡、答案卡、事实行、追问 chips、输入栏 |
| `lib/app.dart` | `+ GoRoute('/assistant')` |
| `lib/features/profile/presentation/profile_page.dart` | 「我的 → 问账本」入口 |
| `test/features/assistant/finance_intent_test.dart`（22 例） | 区间口径 / 优先级 / 别名 / 储蓄 / 不认识 |
| `test/features/assistant/finance_answer_test.dart`（14 例） | 金额、占比、笔数、预算超支、环比、大额、储蓄、空数据 |
| `test/features/assistant/assistant_controller_test.dart`（6 例） | 内存库端到端、空问题、未知问题、连续追问、清空 |
| `test/features/assistant/assistant_page_test.dart`（4 例，含深色主题） | 点示例 → 出答案卡；打字问未知 → 明说不会；清空 |

**没动的**：`lib/core/db/**`（schema 仍 v3）、`pubspec.yaml`（零新增依赖）、`android/**`（零权限变更）、
任何写库路径（M1 只读）。

## 4. 口径（写死，改之前先看测试）

| 项 | 口径 |
|---|---|
| 时间 | 区间一律**本地时区、半开 `[start, end)`**；回答里必须写出实际区间（「近 30 天（9月26日–10月25日）」） |
| 「这个月 / 本月」 | 当前自然月；「上个月」跨年安全；只说「10 月」→ 不晚于当前月算今年，否则去年 |
| 「最近一个月」 | **滚动 30 天**（不是上月）；「最近三个月」→ 含本月共 3 个自然月 |
| 汇总 | `summarize`（transfer 不计收支）；主数字按问的方向（问收入给收入） |
| 分类 | `categoryBreakdown` + `(kind, name)` 双元组；别名只在**该分类真实存在**时生效 |
| 预算 | `buildBudgetView`（超支时每日可花为 0 的逻辑沿用既有口径） |
| 对比 | `current` vs `previous`；上期无数据 → 明说「没法比较」，不拿 0 当基数 |
| 大额 | 用户没说时间 → 近 90 天；按金额降序取前 5 |
| 储蓄 | 纯算术，向上取整；明说「不含利息」 |
| 没有数据 | 一律「这段时间没有记账记录 / 没有某分类记录」，**不返回 ¥0.00 结论** |
| 不认识 | 返回示例问题，不猜 |

## 5. 验收（对齐 `Prompt.md` 阶段二 §6）

| # | 要求 | 本批状态 | 判定方式 |
|---|---|---|---|
| 1 | 可以用自然语言提问 | ✅ | 示例 chips + 自由输入；`assistant_page_test` |
| 2 | 回答来自真实财务数据 | ✅ | 控制器查 `listByRange`；`assistant_controller_test` 断言金额 |
| 3 | 金额和统计由业务代码计算 | ✅ | 只调 `summarize` / `categoryBreakdown` / `buildBudgetView`，模板层不做新算术 |
| 4 | 支持月度汇总、分类支出、预算查询、趋势比较 | ✅ | 4 类意图各有测试；另有「大额」「储蓄」两类 |
| 5 | 模型未安装 / 推理失败时有清晰提示 | ⏳ M2 | M1 页脚已写明「现在是规则+账本计算，模型是后续可选」 |
| 6 | 离线时功能正常 | ✅ | 全链路无网络调用；release 包无 `INTERNET`（未改动清单） |
| 7 | 不会偷偷切云端 | ✅ | 代码里没有任何网络依赖 |
| 8 | 关键查询有单测与集成测试 | ✅ | 46 例（22 + 14 + 6 + 4） |

**门禁实测（2026-10-27，本机）**：`flutter analyze` → **No issues found!**；
`flutter test --concurrency=1` → **634 passed / 6 skipped / 0 failed**（基线 588，本批 **+46**）。

## 6. 已知限制（M1 的边界，别对外承诺）

| # | 限制 | 说明 |
|---|---|---|
| 1 | **只认账本里的数**，不做开放式对话 | 问「我该不该买」一律回「还没学会」+ 示例 |
| 2 | 意图是**规则**，句式超出词表就答不上 | 现在覆盖 7 类；词表在 `finance_intent.dart`，加一句测试就能扩 |
| 3 | 不认识「跨账本 / 多账户余额」类问题 | 账户余额查询（`buildAssetSummary`）留到下一批 |
| 4 | 不记住上下文 | 「那上个月呢」这种指代不支持，每句都要说全（模型进来后由 M2 的会话层解决） |
| 5 | 金额解析只到「元」，不认「两千」这类中文金额 | 宁可让用户重问，也不猜错数 |
| 6 | 深色 / 浅色都已适配，但**未做真机走查**（见 §7） | 颜色全走 `context.toon` 实例字段 |

## 7. 下一步

1. **真机走查**（本批收尾）：装 QA 包 → 「我的 → 问账本」→ 5 个示例各点一次，核对首页/账本数字；
2. **M2**：`LlmProvider` 抽象 + llama.cpp JNI（arm64 / `dotprod` / 线程绑大核 / 流式 / 取消）+
   `.gguf` 手动导入（`getExternalFilesDir('models')` + sha256 校验）+ 设备内存门槛与降级；
3. **M3**：可选下载器（独立 flavor）、多模型管理、性能与隐私说明。
