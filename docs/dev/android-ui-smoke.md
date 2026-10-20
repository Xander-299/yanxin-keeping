# Android 真机 / 模拟器 UI 走查方法

> 本文是「在设备上真实走一遍界面」的操作手册：用无障碍语义树（`uiautomator dump`）
> 代替截图做判读，配合截图做视觉校对。适用于交付前自检、回归冒烟、首次使用验收。
>
> 抓取脚本：[`tool/ui_dump.py`](../../tool/ui_dump.py)。

## 为什么用语义树而不是截图

Flutter 的文本 / 按钮都会出现在语义树里 —— **读得到文案 ≈ 用户看得到**，而且语义树
是可断言的结构化数据，比看图更适合脚本化。反过来，语义树证明不了「颜色对不对、
有没有被遮挡」，那些只能看截图。**两者交叉验证，别单靠一种。**

## 前置

```bash
# adb：优先用 PATH 里的，其次 ANDROID_HOME/ANDROID_SDK_ROOT 下的 platform-tools
export ADB=<adb 可执行文件>
export MUMU_SERIAL=127.0.0.1:16384     # 默认值，按你的设备改
```

要求：

- **debug 包**（`run-as` 只对 debug 包有效，后续改设备数据要用到）。
- 包名：`com.teacodeman.yanxin`；入口 Activity：`.MainActivity`。
- 设备已连上：`adb devices` 里能看到目标；看不到就别 `wait-for-device`（会长时间挂住）。

## 标准动作序列

```bash
# 1) 连接（部分环境每次调用结束会回收 adbd，所以 connect 与操作放在同一次调用里）
"$ADB" connect "$MUMU_SERIAL" >/dev/null 2>&1

# 2) 装 debug 包（debug 包带 testOnly，-t 必须）
"$ADB" -s "$MUMU_SERIAL" install -r -t build/app/outputs/flutter-apk/app-debug.apk

# 3) 归零 + 冷启动（做「首次使用」类验收必须先 pm clear）
"$ADB" -s "$MUMU_SERIAL" shell pm clear com.teacodeman.yanxin
"$ADB" -s "$MUMU_SERIAL" shell monkey -p com.teacodeman.yanxin -c android.intent.category.LAUNCHER 1
sleep 7

# 4) 抓语义树拿坐标 → 点击
python tool/ui_dump.py
"$ADB" -s "$MUMU_SERIAL" shell input tap <x> <y>

# 5) 截图留证（落在不入库的本地目录）
"$ADB" -s "$MUMU_SERIAL" exec-out screencap -p > shots/xx.png
```

**装机前先核验包是刚构建的那版**（否则会「改了没用」地怀疑代码）：

```bash
python tool/verify_apk_kernel.py <本次新增的独有字符串>
```

它比对 APK 内 `assets/flutter_assets/kernel_blob.bin` 与盘上的 sha256，并 grep 指定文案。

## 关键坑（都实际踩过）

1. **每次 shell 调用可能回收 adb daemon** → 新 shell 的首条 adb 命令会撞 `device offline`，
   而 `input tap` 会**静默不执行**（语义树一切照旧，白跑一轮）。对策：命令序列加前缀
   `adb start-server >/dev/null 2>&1; sleep 2`。别用 `wait-for-device` 代替。
2. **坐标随屏幕方向整批失效。** 先确认当前渲染尺寸：`dumpsys window displays | grep -m1 "cur="`。
   转屏用模拟器自己的 CLI（`adb shell settings put system user_rotation` 通常无效）。
3. **横屏逻辑视口可能只有约 1067×600**（dpr≈1.5）→ 日历 / 长表单必然要滚动。
   走查前先 `input swipe` 滚到目标，再 dump 取坐标。
4. **矮窗口里的 Material 日期选择器下半屏点不动**：日期网格被压成可滚动，语义树仍报出
   第 3 行以后的 bounds（`uiautomator` 不裁视口）但点过去无反应。这不是代码 bug。
5. **数字键盘坐标有陷阱**：`8` 与 `0` 常在同一列，别取错行。
6. **语义树的 bounds 是中心点**，直接 `input tap` 该中心即可。
7. **需要「某天有账」的数据时，走 UI 记一笔比导入样本快得多。**
8. **清空输入框**：`input keyevent 67`（DEL）按 n 次删干净再输入。弹窗里有旧值时直接
   `input text` 会变成拼接（`2000` + `100` = `2000100`）。
9. **弹窗 / 对话框也是语义树的一部分**：`showModalBottomSheet` 的标题、`AlertDialog` 的按钮
   都能 dump 到，走查「二次确认」不用猜坐标。
10. **TextField 无文本时在语义树里「不存在」**：空输入框只有 label / hint，没有可点节点。
    此时别推算坐标去点（极易落到遮罩区，表现是「弹窗莫名关闭」，会被误判成阻断 bug）。
    正确顺序：先点弹窗内必然存在的节点（如「保存 / 取消」）拿到真实边界，再在其间选 y；
    或先 `input text` 一个字符，文本节点出现后再点它。
11. **截图与语义树要交叉验证**：`exec-out screencap` 是实时的，但**读文件可能读到缓存帧**。
    两次读同一张图时不要下「设备画面滞后」的结论，用 md5 比对或换一条路径复核。
12. **`input text` 只吃 ASCII**（中文 / emoji 会乱码或直接失败）。验中文输入时优先用页面
    自带的示例词 / 快捷 chip；或用 ASCII 备注（如 `coffee`）走系统键盘。
13. **别连按两次 `keyevent 4`**：带输入框的页面第一次返回只是收键盘，第二次就退出 App
    落到桌面了。返回优先点页面左上角的返回按钮。
14. **模拟器没启动时 `adb wait-for-device` 会永久挂住**（实测 15 分钟零输出，容易被当成
    「构建卡死」）。走查前**先探测再等**：`adb devices` 只有一行表头 = 设备不在线。
15. **凡涉及 `/sdcard/...` 的命令，Git Bash 下要 `MSYS_NO_PATHCONV=1`**：否则 Git Bash 会把
    `/sdcard/ui.xml` 当 Unix 路径转换，表现是 `remote secure_mkdirs failed` 或
    `uiautomator dump` + `pull` 静默拿不到文件（还会继续用上一次的旧 xml）。
16. **`uiautomator dump` 写固定文件名 → 会读到「上一次的界面」**（最具误导性的一个）：
    dump 在 App 刚启动 / 页面切换的瞬间会失败且不覆盖旧文件。`tool/ui_dump.py` 已改为
    **dump 前先 `rm -f`**，失败时退化成「文件不存在」→ 触发它自带的 `DUMP FAILED`。
    自己写 dump 流程时一律用**独立文件名** + `pull`。
    **通用判据：语义树与数据库 / 目录状态矛盾时（库里 0 条流水、屏幕上却有旧数据），
    先怀疑落盘缓存，别先怀疑代码。**
17. **`ui_dump.py` 给的坐标偶尔不是按钮本身**：脚本按语义节点算中心，某些结构下报的是
    **外层容器**的中心（实测整卡容器中心 y=483 而真实按钮在 y=639）。判据：同一坐标连点
    2~3 次都无状态变化 → 拉原始 XML 按 `class + text` 自己选真节点。
18. **模拟长按 = `input swipe x y x y 800`**（同坐标 + 800ms）。想「收键盘但别提交」时
    **不要用 `keyevent 111`（ESC）** —— 实测会把整个 `showModalBottomSheet` 关掉。
19. **后台任务常有 ~15 分钟上限**：全量纯测试实测跑到 15m03s 被掐断，输出停在 `[29/40]`
    且**没有汇总行**（状态仍报 completed，极易误以为跑完了）。判据：最后一行不是汇总行 =
    没跑完。对策：分批跑或把输出落盘。
20. **装包后立即注入输入可能「全都不生效」**：`install -r` + 启动后 `input tap` 与 `input swipe`
    都没反应，但 UI 正常渲染、进程健在、logcat 不报错 —— 极易误判成「代码没生效」。
    处置：`am force-stop` + 重新 `monkey` 启动一次，手势立即恢复。
    **判据：先点一个「绝对该有反应」的目标（如底栏 tab）验证输入通道活着，再判定功能坏了。**
21. **视觉类改动必须截图看，语义树证明不了「颜色 / 遮挡」**：曾出现「行没有自身底色 →
    底层红色动作区透出来」，语义树与 widget 测试全绿，只有截图看得出那条红色。
22. **模拟器不弹软键盘时的等价验证**：开启硬件键盘映射后 Flutter 判定「有物理键盘」→
    点输入框不弹软键盘，但**输入框确实聚焦了**（光标可见、`input text` 能输入）——别把
    「没弹键盘」误判成「点击没生效」。等价做法：键盘弹起对布局的唯一作用是压缩 body，
    用 `adb shell wm size 900x1000` 同样压缩 body 可用高度来验证贴底元素，**验完必须
    `wm size reset`**。

## 视觉对拍：和设计稿并排比

改 UI 后要与页面原型并排核对。若原型是单页 HTML（无 URL 路由），可以复制一份到临时目录、
末尾追加一小段「读 query 参数定点跳屏」的脚本再截图（**不动原文件**）：

```bash
# 复制原型到临时目录 → 追加 ?s=<屏名> 跳屏脚本 → headless Chrome 截图
chrome --headless=new --disable-gpu --hide-scrollbars --window-size=1200,1000 \
       --screenshot="<绝对路径>/proto-stats.png" "file:///<绝对路径>/index.html?s=stats"
```

要点：

- Chrome 的 `--screenshot=` 路径相对的是 **Chrome 自己的 CWD**，一律给绝对路径，
  否则静默报「系统找不到指定的路径」。
- 连续 / 并发跑多次 headless 时各带一个 `--user-data-dir=`，避免 profile 锁。
- 截出来常是「左侧栏 + 中间手机」的整页图，中间那台才是设计稿本体。

## 放大截图判定像素级细节

1× 看整屏截图时，「输入框的底边框紧贴文字」极容易被读成「hint 文本带了 underline」；
3px 描边叠在遮罩背景上，1× 下看着像「没有描边」。别凭感觉下结论：用一个缩放用的
HTML（`transform: scale(z)` + 负偏移定位）配合 headless Chrome 裁切放大再看。

## 直接改设备上的 App 数据

走查常在设备上留下垃圾（临时账本 / 账户 / 流水），而 App 未必有对应删除入口。
**不用 pull / 改 / push 数据库往返** —— 模拟器自带 `/system/bin/sqlite3`，配 `run-as` 直接改：

```bash
"$ADB" -s "$MUMU_SERIAL" shell am force-stop com.teacodeman.yanxin   # 必须先停，否则 drift 连接会覆盖
"$ADB" -s "$MUMU_SERIAL" shell run-as com.teacodeman.yanxin ls -l app_flutter/   # → yanxin.sqlite
"$ADB" -s "$MUMU_SERIAL" shell run-as com.teacodeman.yanxin cp app_flutter/yanxin.sqlite \
                                                      app_flutter/yanxin.sqlite.bak
"$ADB" -s "$MUMU_SERIAL" shell "run-as com.teacodeman.yanxin sqlite3 app_flutter/yanxin.sqlite \
  \"update books set deleted_at=$TS, updated_at=$TS, dirty=1 where name='QA-Temp' and deleted_at is null; select changes();\""
```

要点：**先备份**；优先**软删**（`deleted_at`）而不是 `DELETE`（与 App 自身口径一致）；
删父行即可（子表随父行不可达）；改完记得 `dirty=1`。

## 改 schema 时必做：覆盖安装验迁移

内存库单测能证明 `onUpgrade` 的逻辑，**证明不了 `adb install -r` 这条真实路径**。
凡是动了表结构，走查必须包含：

1. 装旧包并造数据（或直接用已在跑的旧版本）；
2. **只覆盖安装、不 `pm clear`**（`pm clear` 会把老库删掉）；
3. 断言「老数据分毫不少」+「新表可用」；
4. 再 force-stop 重启一次，确认新写入的数据也持久化。

**升级路径崩了是线上事故，比新功能不好用严重得多。**

## 判定原则

- 断言文案存在 = 用户看得到（`tool/ui_dump.py` + grep 即可）。
- 断言「点得动」必须真的 `input tap` 后**重新 dump 看状态变化**，不能只看节点标了可点。
- 「结果可取用」类检查：操作后回到列表页，确认新数据出现在预期位置（月 / 日 / 分组）。
- **跨页一致性必查**：凡是「常驻 Notifier / 只在首次进入时 build」的页面（如统计页），
  记完一笔后必须**再进一次**验证数据刷新 —— 首页对了不代表别的页也对。
- **新增路由必须回读 `lib/app.dart` 复核**：改了路由但文件编辑丢了时，UI 表现是
  「点入口没反应 / 显示 Page Not Found」，语义树里能看到
  `GoException: no routes for location: /xxx`，而 `flutter analyze` 查不出来。
- 走查记录用「操作 → 看到的反馈」两列表，避免事后凭记忆写结论。
