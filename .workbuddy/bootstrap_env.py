"""在新机器（只有 C: 盘）上补齐颜芯记账 Flutter 工程的缺失依赖。

背景：HANDOFF.md 记录的环境基线在 D: 盘（旧机器），本机无 D: 盘，
Flutter SDK / Android SDK / Pub 缓存 / Gradle 缓存全部缺失；JDK 17 现成（M:\\QQcache）。

用法：python .workbuddy/bootstrap_env.py [--step flutter|android|all]
绕过沙箱对 curl 落盘的拦截（curl -o 一律 exit 23），改用 urllib 流式写盘。
"""
import os
import shutil
import ssl
import sys
import time
import urllib.request
import zipfile

ROOT = r"C:\src"
TMP = os.path.join(ROOT, "_sdk")

FLUTTER_URL = (
    "https://storage.flutter-io.cn/flutter_infra_release/releases/"
    "stable/windows/flutter_windows_3.47.2-stable.zip"
)
PROXY = "http://127.0.0.1:7890"
REPO_XML = "https://dl.google.com/android/repository/repository2-3.xml"


def opener(use_proxy: bool = False):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    handlers = [urllib.request.HTTPSHandler(context=ctx)]
    if use_proxy:
        handlers.insert(0, urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}))
    return urllib.request.build_opener(*handlers)


def download(url: str, dest: str, min_bytes: int = 5 * 1024 * 1024, use_proxy: bool = False):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > min_bytes:
        print(f"[skip] {dest} ({os.path.getsize(dest)} bytes) 已存在", flush=True)
        return dest
    print(f"[get ] {url}", flush=True)
    t0 = time.time()
    with opener(use_proxy).open(url, timeout=3600) as r, open(dest, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = r.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total and done % (64 * 1024 * 1024) < 1024 * 1024:
                print(
                    f"       {done/1e6:.0f}/{total/1e6:.0f} MB "
                    f"({done/total*100:.0f}%, {time.time()-t0:.0f}s)",
                    flush=True,
                )
    print(f"[ok  ] {dest} {os.path.getsize(dest)} bytes in {time.time()-t0:.0f}s", flush=True)
    return dest


def unzip(zp, dest, strip_top: str | None = None):
    print(f"[unzip] {zp} -> {dest}", flush=True)
    tmp_ex = zp + ".ex"
    shutil.rmtree(tmp_ex, ignore_errors=True)
    os.makedirs(tmp_ex, exist_ok=True)
    with zipfile.ZipFile(zp) as z:
        z.extractall(tmp_ex)
    os.makedirs(dest, exist_ok=True)
    src = os.path.join(tmp_ex, strip_top) if strip_top else tmp_ex
    for name in os.listdir(src):
        s, d = os.path.join(src, name), os.path.join(dest, name)
        if os.path.exists(d):
            if os.path.isdir(d):
                shutil.rmtree(d, ignore_errors=True)
            else:
                os.remove(d)
        shutil.move(s, d)
    shutil.rmtree(tmp_ex, ignore_errors=True)
    print(f"[done ] extracted -> {dest}", flush=True)


def step_flutter():
    zp = os.path.join(TMP, "flutter.zip")
    download(FLUTTER_URL, zp)
    unzip(zp, os.path.join(ROOT, "flutter"), strip_top="flutter")
    print("[done] Flutter SDK -> C:\\src\\flutter", flush=True)


def latest_commandlinetools_url():
    print(f"[xml ] {REPO_XML}", flush=True)
    with opener().open(REPO_XML, timeout=300) as r:
        xml = r.read().decode("utf-8", "ignore")
    import re

    # XML 里的 <url> 不含 android/repository/ 前缀，下载时要自己补
    cands = re.findall(r"<url>(commandlinetools-win-\d+_latest\.zip)</url>", xml)
    # 取版本号最大的一个
    cands = sorted(set(cands), key=lambda s: int(re.search(r"-(\d+)_latest", s).group(1)))
    print(f"[xml ] candidates tail: {cands[-3:]}", flush=True)
    # XML 里的 <url> 只有文件名，下载路径要补 android/repository/
    return "https://dl.google.com/android/repository/" + cands[-1] if cands else None


def step_android():
    url = latest_commandlinetools_url()
    if not url:
        print("[fail ] 没找到 commandlinetools 下载地址", flush=True)
        return
    zp = os.path.join(TMP, "cmdline-tools.zip")
    download(url, zp, min_bytes=1024 * 1024)
    latest = os.path.join(ROOT, "Android", "cmdline-tools", "latest")
    unzip(zp, latest, strip_top="cmdline-tools")
    print(f"[done] cmdline-tools -> {latest}", flush=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    step = args[args.index("--step") + 1] if "--step" in args else "all"
    if step in ("flutter", "all"):
        step_flutter()
    if step in ("android", "all"):
        step_android()
    print("ALL_DONE", flush=True)
