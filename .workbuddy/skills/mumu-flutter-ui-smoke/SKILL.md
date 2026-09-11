---
name: mumu-flutter-ui-smoke
description: 在 MuMu 模拟器上用 adb + uiautomator 语义树对 Flutter Android 应用做 UI 冒烟/验收走查（点击、输入、翻页、校验可见文案）。当需要「在模拟器/真机上真实走一遍界面」而不是只跑 widget 测试时使用；也适用于首次使用验收、回归冒烟、交付前自检。关键词：冒烟、验收、真机走查、MuMu、adb、uiautomator、Flutter UI 验
agent_created: true
---

# MuMu + Flutter UI 冒烟走查

用语义树（uiautomator dump）代替截图来做判读：Flutter 的文本/按钮都会出现在语义树里，
读得到文案就等价于「用户看得到」，而且比看图更适合脚本化断言。

## 前置：环境常量（本项目实测）

- adb：`/d/Download/Java/Android/platform-tools/adb.exe`
- MuMu adb 端口：`16384`（另有 `7555`）；设备名 `emulator-5554`
- 包名：`com.teacodeman.yanxin`
- python：`/c/Users/panda/.workbuddy/binaries/python/versions/3.13.12/python.exe`
- 项目里已有抓取脚本：`.workbuddy/ui_dump.py`（打印「[可点] 文案 @(x,y)」列表）

## 标准动作序列

```bash
export PATH="/usr/bin:/bin:$PATH"          # 本环境 bash 偶尔丢 PATH，先补
cd /d/Tencent/yanxin-flutter
ADB="/d/Download/Java/Android/platform-tools/adb.exe"

# 1) 连接（adbd 会被沙箱按调用回收，每次调用都要重连 + 操作放在同一次调用里）
"$ADB" connect 127.0.0.1:16384 >/dev/null 2>&1

# 2) 装 debug 包（必须 -t，debug 包带 testOnly）
"$ADB" -s emulator-5554 install -r -t build/app/outputs/flutter-apk/app-debug.apk

# 3) 归零 + 冷启动（做「首次使用」类验收必须 pm clear）
"$ADB" -s emulator-5554 shell pm clear com.teacodeman.yanxin
"$ADB" -s emulator-5554 shell monkey -p com.teacodeman.yanxin -c android.intent.category.LAUNCHER 1
sleep 7

# 4) 抓语义树拿坐标 → 点击
$PY .workbuddy/ui_dump.py
"$ADB" -s emulator-5554 shell input tap <x> <y>

# 5) 截图留证
"$ADB" -s emulator-5554 exec-out screencap -p > .workbuddy/shots/xx.png
```

## 关键坑（都踩过）

1. **每次 bash 调用结束 adbd 会被回收** → 命令必须「connect + 操作」同一次调用完成，否则 `device offline`。
2. **坐标会随屏幕方向整批失效**。先确认当前渲染尺寸：
   `dumpsys window displays | grep -m1 "cur="`（`cur=1600x900` 就是横屏）。
   **MuMu 的旋转只认它自己的 UI**：`settings put system user_rotation 0` 改不动实际显示，
   别浪费时间在 adb 里转屏。
3. **横屏逻辑视口只有约 1067×600**（dpr≈1.5）→ 日历/长表单类页面必然滚动。
   走查前先 `input swipe` 滚到目标，再 dump 取坐标；不要假设 dump 出的 y 一定在首屏可点。
4. **Material 日期选择器在矮窗口里下半屏点不动**：`showDatePicker` 的日期网格被压成可滚动，
   语义树仍报出第 3 行以后的 bounds（`uiautomator` 不裁），但点过去无反应。
   判据：只有前两行能选中、`OK` 按钮正常。**这不是代码 bug，是窗口高度问题**；
   要验证「改日期」链路就点前两行能命中的日期（同样能验证 picker→OK→回填）。
5. **数字键盘坐标有陷阱**：`8` 只有一处，别把同一行的 `0` 当 `8`。
   录入「88.88」= 5 次 `8` 键 + 1 次 `.`；录入「50.00」= `5`、`0`、`.`、`0`、`0`。
6. **语义树的 bounds 是中心点**，直接 `input tap` 该中心即可（本项目 ui_dump.py 已算好）。
7. 需要「某天有账」的日历数据时，最快是走 UI 记一笔（`记一笔 → 金额 → 分类 → 保存`），
   比导入 300+ 条样本快得多。

## 判定原则

- 断言文案存在 = 用户看得到（配合 `dump | grep` 即可）。
- 断言「点得动」必须真的 `input tap` 后重新 dump 看状态变化，不能只看节点是 `[可点]`。
- 「结果可取用」类检查：操作后回到列表页，确认新数据出现在预期位置（月/日/分组）。
- 走查记录用「操作 → 看到的反馈」两列表，避免事后凭记忆写结论。
