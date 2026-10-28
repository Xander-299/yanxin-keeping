# AGENTS.md — Agent 规则入口（指针文件）

> 本文件**不承载规则**，只做指针。所有实质约定都在下面三个入口里，以它们为准。

## 接手必读（按顺序）

1. **[`HANDOFF.md`](HANDOFF.md)** —— 唯一接手入口：现状、硬约束、**10 条不变量**、坑清单、目录导航。
   干活前先通读一遍；改完代码把变化回写进去。
2. **[`docs/spec/`](docs/spec/)** —— 需求流程：功能改动先有 SPEC（命名 `SPEC-F7.<n>-<slug>.md`，
   编号看 [`docs/PRD-yanxin-flutter.md`](docs/PRD-yanxin-flutter.md) 的 FR 表）；用户下发的任务书原文
   **必须先存档进 [`docs/spec/prompts/`](docs/spec/prompts/)** 再被 SPEC 引用。
3. **[`docs/handoff/`](docs/handoff/)** —— 过程知识：踩坑（pitfalls）、决策参考（reference）、
   未决问题（open-issues）、历史（history / status-log / session-log）。

## 三条最容易踩的本地约定（详情都在 HANDOFF）

- 本机跑测试**必须** `flutter test --concurrency=1`（否则 OOM）；
- 出 QA 包要临时改 `android/gradle.properties`（降内存 + `qaAppId`），构建后**按字节还原**（`git diff android/` 为空）；
- 根目录 `Prompt.md` 是**临时提示词暂存位**，会被下一次任务覆盖 —— 不是规则，也不要引用它。

## 门禁

`flutter analyze` 0 issue + `flutter test` 全绿（CI 自动跑，见 `.github/workflows/ci.yml`）。
