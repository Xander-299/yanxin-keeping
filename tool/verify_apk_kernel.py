"""装机前核验：APK 里的 kernel_blob.bin 与盘上一致 + grep 本批新增文案。

## 为什么必须做

本机构建走 `tool/build_kernel_fallback.py` + `gradlew assembleDebug -x compileFlutterBuildDebug`
（Dart 管道故障的绕行路径）。一旦 kernel 那步没跑或跑的是旧产物，`gradlew` 仍会「成功」，
装上去的就是**上一版**的包 —— 走查时会看到「改了没用」而误判代码没生效。
所以在 `adb install` 之前，先证明 APK 里的 `kernel_blob.bin` 就是盘上刚编译的那份。

## 用法

    python tool/verify_apk_kernel.py                    # 默认核验 debug 包 + 三个常用关键词
    python tool/verify_apk_kernel.py SwipeActionRow 删除  # 自定义要 grep 的文案（本批新增的字符串）

判据（三条全绿才算新鲜）：
1. `apk 时间` 是**本次**构建时间；
2. `新鲜度: OK 一致`（APK 内 kernel 的 sha256[:16] == 盘上 `build/app/intermediates/.../kernel_blob.bin`）；
3. `grep` 的目标文案在 kernel 里命中（keyword 用**新代码里独有的字符串**，如新类名 / 新 key 前缀）。
"""
import datetime
import hashlib
import os
import sys
import zipfile

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APK = os.path.join(PROJ, "build", "app", "outputs", "flutter-apk", "app-debug.apk")
DISK = os.path.join(
    PROJ, "build", "app", "intermediates", "flutter", "debug",
    "flutter_assets", "kernel_blob.bin",
)

apk_bytes = zipfile.ZipFile(APK).read("assets/flutter_assets/kernel_blob.bin")
disk_bytes = open(DISK, "rb").read()

print("apk  时间:", datetime.datetime.fromtimestamp(os.path.getmtime(APK)).strftime("%m-%d %H:%M:%S"))
print("apk  大小: %.1f MB" % (os.path.getsize(APK) / 1048576))
apk_sha = hashlib.sha256(apk_bytes).hexdigest()[:16]
disk_sha = hashlib.sha256(disk_bytes).hexdigest()[:16]
print("apk  kernel sha256[:16]:", apk_sha, len(apk_bytes))
print("disk kernel sha256[:16]:", disk_sha, len(disk_bytes))
print("新鲜度:", "OK 一致" if apk_sha == disk_sha else "!! 不一致（装到旧包）")

text = apk_bytes.decode("utf-8", "ignore")
for kw in sys.argv[1:] or ["SwipeActionRow", "resolveSwipeOpen", "swipe-"]:
    print("grep", repr(kw), "->", kw in text)
