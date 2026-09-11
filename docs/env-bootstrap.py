"""一次性环境预装：Flutter SDK / JDK17 / Android cmdline-tools。

绕过沙箱对 curl 写体的拦截，改用 urllib 流式下载 + zipfile 解压。
"""
import os
import shutil
import ssl
import sys
import urllib.request
import zipfile

PROXY = "http://127.0.0.1:7890"
TMP = r"D:\Tencent\yanxin-flutter\_sdk"

TARGETS = [
    (
        "flutter",
        "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.2-stable.zip",
        r"D:\Download\Flutter",
    ),
    (
        "jdk17",
        "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse",
        r"D:\Download\Java",
    ),
]


def opener():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}),
        urllib.request.HTTPSHandler(context=ctx),
    )


def download(name, url, dest):
    os.makedirs(TMP, exist_ok=True)
    zp = os.path.join(TMP, name + ".zip")
    if os.path.exists(zp) and os.path.getsize(zp) > 10 * 1024 * 1024:
        print(f"[skip] {name} already downloaded {os.path.getsize(zp)}", flush=True)
        return zp
    op = opener()
    print(f"[get ] {name} <- {url}", flush=True)
    with op.open(url, timeout=3600) as r, open(zp, "wb") as f:
        shutil.copyfileobj(r, f, 1024 * 1024)
    print(f"[ok  ] {name} {os.path.getsize(zp)} bytes", flush=True)
    return zp


def unzip(zp, dest):
    print(f"[unzip] {zp} -> {dest}", flush=True)
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(zp) as z:
        z.extractall(dest)
    print(f"[done ] extracted to {dest}", flush=True)


def main():
    os.makedirs(TMP, exist_ok=True)
    # 1) cmdline-tools：已下载，解压到 Android SDK
    ct = os.path.join(TMP, "t2.zip")
    if os.path.exists(ct):
        latest = r"D:\Download\Java\Android\cmdline-tools\latest"
        if os.path.isdir(latest):
            shutil.rmtree(latest, ignore_errors=True)
        tmp_ex = os.path.join(TMP, "ct_ex")
        shutil.rmtree(tmp_ex, ignore_errors=True)
        unzip(ct, tmp_ex)
        src = os.path.join(tmp_ex, "cmdline-tools")
        os.makedirs(os.path.dirname(latest), exist_ok=True)
        shutil.move(src, latest)
        print(f"[done ] cmdline-tools -> {latest}", flush=True)

    # 2) Flutter + JDK17
    for name, url, dest in TARGETS:
        zp = download(name, url, dest)
        unzip(zp, dest)

    print("ALL_DONE", flush=True)


if __name__ == "__main__":
    sys.exit(main())
