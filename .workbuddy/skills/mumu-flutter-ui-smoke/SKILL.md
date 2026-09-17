---
name: mumu-flutter-ui-smoke
description: 在 MuMu 模拟器上用 adb + uiautomator 语义树对 Flutter Android 应用做 UI 冒烟/验收走查（点击、输入、翻页、校验可见文案）。当需要「在模拟器/真机上真实走一遍界面」而不是只跑 widget 测试时使用；也适用于首次使用验收、回归冒烟、交付前自检。关键词：冒烟、验收、真机走查、MuMu、adb、uiautomator、Flutter UI 验
agent_created: true
---

# MuMu + Flutter UI 冒烟走查

用语义树（uiautomator dump）代替截图来做判读：Flutter 的文本/按钮都会出现在语义树里，
读得到文案就等价于「用户看得到」，而且比看图更适合脚本化断言。

## 前置：环境常量（**双机器项目，先判机器再取常量**）

本项目两台机器在用，路径不同（判据与 `env.sh` 一致：哪台机器的 Flutter SDK 目录存在）：

| | A 机（panda / D:） | B 机（Administrator / C:） |
|---|---|---|
| adb | `D:\Download\Java\Android\platform-tools\adb.exe` | `C:\Users\Administrator\Desktop\platform-tools\adb.exe` |
| MuMu | **12** @ `D:\Downloads\MuMu\MuMuPlayer` | **15** @ `C:\Program Files\Netease\MuMu` |
| MuMuManager | `…\MuMuPlayer\nx_main\MuMuManager.exe` | `…\Netease\MuMu\nx_main\MuMuManager.exe` |
| 项目目录 | `D:\Tencent\yanxin-flutter` | `C:\Users\Administrator\Desktop\yanxin-bookkeeping-flutter-master` |

公共：包名 `com.teacodeman.yanxin`；adb 端口 `16384`（另有 `7555`，等价），设备名 `127.0.0.1:16384`；
抓取脚本 `.workbuddy/ui_dump.py`；装包前先有 APK：`flutter build apk --debug`。

```bash
export PATH="/usr/bin:/bin:$PATH"          # 本环境 bash 偶尔丢 PATH，先补
if [ -d /d/Download/Flutter/flutter ]; then            # A 机
  PROJ=/d/Tencent/yanxin-flutter
  ADB=/d/Download/Java/Android/platform-tools/adb.exe
  MUMU=/d/Downloads/MuMu/MuMuPlayer/nx_main/MuMuManager.exe
  PY=/c/Users/panda/.workbuddy/binaries/python/versions/3.13.12/python.exe
else                                                    # B 机
  PROJ=/c/Users/Administrator/Desktop/yanxin-bookkeeping-flutter-master
  ADB=/c/Users/Administrator/Desktop/platform-tools/adb.exe
  MUMU="/c/Program Files/Netease/MuMu/nx_main/MuMuManager.exe"
  PY=/c/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe
fi
DEV=127.0.0.1:16384
cd "$PROJ"
```

- A 机（MuMu 12）默认是**横屏 1600×900**（逻辑视口约 1067×600）；B 机（MuMu 15）默认**平板横屏 2560×1440**。
- NDK/cmake：A 机已含（`D:\Download\Java\Android` 内有 ndk 28.2.13676358 + cmake 3.22.1）；B 机需另装于 `C:\src\Android`。

## 标准动作序列

```bash
# 常量见上一节（先判机器，得到 $PROJ / $ADB / $PY / $DEV）

# 1) 连接（adbd 会被沙箱按调用回收，每次调用都要重连 + 操作放在同一次调用里）
"$ADB" connect "$DEV" >/dev/null 2>&1

# 2) 装 debug 包（必须 -t，debug 包带 testOnly）
"$ADB" -s "$DEV" install -r -t build/app/outputs/flutter-apk/app-debug.apk

# 3) 归零 + 冷启动（做「首次使用」类验收必须 pm clear）
"$ADB" -s "$DEV" shell pm clear com.teacodeman.yanxin
"$ADB" -s "$DEV" shell monkey -p com.teacodeman.yanxin -c android.intent.category.LAUNCHER 1
sleep 7

# 4) 抓语义树拿坐标 → 点击
"$PY" .workbuddy/ui_dump.py
"$ADB" -s "$DEV" shell input tap <x> <y>

# 5) 截图留证
"$ADB" -s "$DEV" exec-out screencap -p > .workbuddy/shots/xx.png
```

## 关键坑（都踩过）

1. **每次 bash 调用结束 adbd 会被回收** → 命令必须「connect + 操作」同一次调用完成，否则 `device offline`。
2. **坐标会随屏幕方向整批失效**。先确认当前渲染尺寸：
   `dumpsys window displays | grep -m1 "cur="`（`cur=1920x1080` 就是横屏）。
   **MuMu 转屏的正确姿势（实测）**：用官方 CLI——
   `"$MUMU" setting -v 0 -k resolution_mode -val phone.1`（竖屏手机 1080×1920@480dpi，
   视口 360×640dp）→ `"$MUMU" control -v 0 restart` → 等 `"$MUMU" info -v 0` 里 `is_android_started=true`。
   `adb shell settings put system user_rotation` / `wm user-rotation` 都无效，别浪费时间。
   平板横屏对应 `tablet.1`；MuMu 15 默认就是 `tablet.1`（2560×1440），MuMu 12 默认横屏 1600×900（未必是 tablet.1）。
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
8. **清空输入框**：`input keyevent 67`（DEL）按 n 次删干净，再 `input text "xxx"`。
   弹窗里预填了旧值时直接用 `input text` 会变成拼接（`2000` + `100` = `2000100`）。
9. **弹窗/对话框也是语义树的一部分**：`showModalBottomSheet` 的标题、`AlertDialog` 的按钮
   都能 dump 到，走查「二次确认」类交互不用靠猜坐标。
10. **`input text` 只吃 ASCII**（中文/emoji 进去是乱码或直接失败）。要验「中文关键词搜索」「中文备注」这类场景，
    两条路：① 优先用**页面自带的示例词 / 快捷 chip**（本项目搜索页就有 `餐饮 / 午餐 / 88.88` 三个 chip，
    点一下等于填词 + 触发搜索）；② 用 ASCII 备注（如 `coffee`）走系统键盘输入。
    记一笔页的备注框要先 `input swipe` 上滑才可见（1080×1920 竖屏下 y≈1596），点它才会拉起系统键盘。
11. **别连按两次 `keyevent 4`**：带输入框的页面（如搜索页）第一次返回只是收键盘，
    如果页面已经被键盘挡住而你以为没生效，再按一次就**退出 App 落到 MuMu 桌面/浏览器**了
    （重启靠 `monkey -p <pkg> -c android.intent.category.LAUNCHER 1`）。
    返回优先点页面左上角的 `Back`（1080×1920 下 @(84,156)）。

## 改 schema 时必做：覆盖安装验迁移

内存库单测能证明 `onUpgrade` 的逻辑，**但证明不了 `adb install -r` 覆盖安装这条真实路径**。
凡是动了数据库表结构（本项目如 F7.3 加 `budgets` 表、schema v1 → v2），走查必须包含：

```bash
# 1) 装旧包并造数据（或直接用已在跑的旧版本）
# 2) 只覆盖安装、不 pm clear —— 这一步是关键，pm clear 就把老库删了
"$ADB" -s "$DEV" install -r -t build/app/outputs/flutter-apk/app-debug.apk
"$ADB" -s "$DEV" shell monkey -p com.teacodeman.yanxin -c android.intent.category.LAUNCHER 1
sleep 9

# 3) 断言「老数据都在」+「新表可用（新功能能读能写）」
"$PY" .workbuddy/ui_dump.py          # 首页支出/收入/结余应与升级前一致
# 4) 再 force-stop 重启一次，确认新写入的数据也持久化
"$ADB" -s "$DEV" shell am force-stop com.teacodeman.yanxin
```

判据：① 老数据分毫不少；② 新功能能读到「未设置」这类正确空态（不是崩溃/不是空屏）；
③ 新写入的值 force-stop 后仍在。**升级路径崩了是线上事故，比新功能不好用严重得多。**

## 判定原则

- 断言文案存在 = 用户看得到（配合 `dump | grep` 即可）。
- 断言「点得动」必须真的 `input tap` 后重新 dump 看状态变化，不能只看节点是 `[可点]`。
- 「结果可取用」类检查：操作后回到列表页，确认新数据出现在预期位置（月/日/分组）。
- 走查记录用「操作 → 看到的反馈」两列表，避免事后凭记忆写结论。
- **跨页一致性必查（2026-09-12 抓到过真 bug）**：凡是「常驻 Notifier / 只在首次进入时 build」的页面
  （本项目如统计页），记完一笔后必须**再进一次**验证数据刷新——首页对了不代表别的页也对。
- 多个页面各有一份「当前月份」时，记账入口从哪个页进，保存后就回到哪个页（本项目行为），别误判成跳错页。
- **新增路由必须回读 `app.dart` 复核（2026-09-12 踩过）**：改了路由但文件编辑丢了时，UI 表现是
  「点入口没反应 / 显示 Page Not Found」，语义树里能看到 `GoException: no routes for location: /xxx`。
  `flutter analyze` 查不出来（没人调用那个 builder）→ 走查前先 `grep "GoRoute(path: '/xxx'" lib/app.dart`。
