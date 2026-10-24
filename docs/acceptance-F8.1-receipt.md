# 验收报告 · F8.1 截图记账（阶段一）

> 日期：2026-10-24 · 设备：Redmi K50（`22041211AC` / rubens / Android 14 / HyperOS）
> 代码：工作区（未打 tag；D5 = F8 线，`v0.8.1` 走查通过后再打）
> SPEC：[`docs/spec/SPEC-local-ai.md`](spec/SPEC-local-ai.md)

## 一句话结论

**端到端已在真机跑通**：相册选图 → 端上 OCR（121–191 ms）→ 核对页字段全对 → 确认入账 → 首页可见；
同一张图再走一次会命中指纹去重（「这笔之前已经记过了」，账本仍 1 笔）。
全程 **Wi-Fi 关闭**，release 包**无 `INTERNET` 权限**。

## 一、门禁

| # | 项 | 结果 |
|---|---|---|
| 1 | `flutter analyze` | ✅ No issues found |
| 2 | `flutter test --concurrency=1` | ✅ **588 passed / 6 skipped** |
| 3 | 真实截图回归 | ✅ 18 例（8 张账单详情 + 1 张交易详情 + 合成样本），见 `test/features/receipt/receipt_real_samples_test.dart` |
| 4 | release 构建 | ✅ 64.6 MB（关 R8 后 +3 MB） |
| 5 | ABI 瘦身 | ✅ `arm64-v8a` + `armeabi-v7a`（x86_64 已裁） |
| 6 | 正式包权限 | ✅ 仅 `POST_NOTIFICATIONS` + `RECEIVE_BOOT_COMPLETED`（**无 `INTERNET`**） |
| 7 | ML Kit 离线资产 | ✅ `libmlkit_google_ocr_pipeline.so` 10.5 MB(arm64) + 模型 2.4 MB |

## 二、真机走查（用户提供的微信「交易详情」截图：`-22.98 / 美团 / 2026-10-24 16:28:57`）

| # | 用例 | 结果 |
|---|---|---|
| 1 | 我的 → 截图记账 → 从相册选一张 | ✅ 系统 Photo Picker 弹出并返回路径 |
| 2 | 核对页 | ✅ 微信支付 · 交易成功 · **¥22.98** · 分类**餐饮** · 日期 **2026-10-24 16:28** · 账户 现金 · 依据「独立行」· **121–191 ms** |
| 3 | 确认记账 | ✅ 「已记账 · 支出 ¥22.98 · 2026-10-24 16:28」 |
| 4 | 首页 | ✅ 本月支出 ¥22.98；列表出现「餐饮 美团 −22.98」 |
| 5 | 同一张图再走一遍 | ✅ 「这笔之前已经记过了 · ¥22.98，没有重复入账」，仍 1 笔 |
| 6 | 离线 | ✅ Wi-Fi 关闭状态下完成识别与入账 |
| 7 | 选到已删除的图 | ✅ 「图片读不到了，换一张试试」，不崩不写库 |

## 三、走查中修掉的三个阻塞（都不是"功能写错了"，而是环境/构建/依赖层）

| # | 阻塞 | 根因 | 修法 |
|---|---|---|---|
| 1 | 新包**一启动 SIGSEGV**（`JNI is not initialized … before main()`） | `path_provider_android 2.3.1` 传递进来的 `jni_flutter 1.0.3` 在本机 Flutter 3.47.2 上初始化时序不对；**未改动的 HEAD 同样崩** | `dependency_overrides: jni_flutter: 1.0.1`（lock 只动 3 条） |
| 2 | 点「选图」**没反应**（release 包、无报错） | `file_picker 12` 的选图链路在 release 里 `pickFile()` 直接返回 null，系统 Activity 都没起（导入页同样失效） | 选图收进自己的 `yanxin/ocr` 通道：Android 13+ 系统 Photo Picker，老系统 SAF 兜底 |
| 3 | 选图成功但 **OCR 抛 NPE**（`Object.getClass() on a null object reference`） | Flutter release **默认开 R8**，把 ML Kit 内部组件裁掉；同一张图 debug 包正常、release 包必崩 | `release { isMinifyEnabled = false; isShrinkResources = false }`（+3 MB） |

**顺带修掉的两个解析 bug**（真实截图暴露）：
- `商户` 标签命中 `商户单号` → 商户名变成「单号」；改为**标签必须行首** + 复合后缀拒收；
- `交易单号` 与号码被 OCR 拆成两行 → 抓不到单号；改为**允许取下一行**；
- 另：商户启发式补「金额**下一行**」（交易详情版式商户在金额下面，账单详情版式在上面）。

## 四、已知限制

| # | 项 | 说明 |
|---|---|---|
| 1 | 支付失败截图的**真机**用例 | 单测已覆盖（按钮禁用 + 不写库），但手上没有真实"失败"截图样本 |
| 2 | 二维码付款的商户 | 取到的是收款方**昵称**（真实样本里是「静」），店名在标题行，用户可在备注里改 |
| 3 | 分类粗糙 | 「美团」恒判餐饮，走美团订的**民宿**也会是餐饮 → 用户确认页改 |
| 4 | 账户默认「现金」 | 账本里没有 `wechat` 类型账户时的兜底（与「记一笔」页一致） |
| 5 | APK 体积 | 关 R8 后 64.6 MB；将来瘦身要加 ML Kit keep 规则再测，**别直接开回 R8** |
| 6 | 导入账单页的选文件 | 仍走 `file_picker`，本机同样点不出来 → **存量问题，建议单独处理**（改造成本与截图记账那次相当） |
| 7 | 富文本/长截图 | 不做（单张） |

## 五、复现命令

```powershell
# 门禁
flutter analyze --no-pub
flutter test --no-pub --concurrency=1

# 出 QA 包（并列安装，不碰用户正式包账本）
#   android/gradle.properties 里临时写：qaAppId=com.teacodeman.yanxin.qa
flutter build apk --release --no-pub
adb install -r -t build\app\outputs\flutter-apk\app-release.apk

# 不走 UI 的 OCR/解析探针（排查构建/识别问题用）
adb push bill.jpg /data/local/tmp/bill.jpg
flutter build apk --debug --no-pub -t tool/ocr_probe_main.dart
adb install -r -t build\app\outputs\flutter-apk\app-debug.apk
adb shell run-as com.teacodeman.yanxin.qa cp /data/local/tmp/bill.jpg cache/bill.jpg
adb shell am start -n com.teacodeman.yanxin.qa/com.teacodeman.yanxin.MainActivity
adb logcat -s flutter | Select-String PROBE

# 清理
adb uninstall com.teacodeman.yanxin.qa
```
