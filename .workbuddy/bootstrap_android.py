"""直下 Android platform / build-tools（绕过 sdkmanager 的 `;` 参数被 cmd 拆词的问题）。

cmd.exe 把 `;` 当参数分隔符 → `sdkmanager "platforms;android-35"` 会被拆成
「Package android-35 not found」。改成解析 repository2-3.xml 直下 zip 再解压。
"""
import io
import os
import urllib.request
import zipfile

BASE = "https://dl.google.com/android/repository/"
TARGETS = [
    ("platform-35_r02.zip", r"C:\src\Android\platforms\android-35"),
    ("platform-36_r02.zip", r"C:\src\Android\platforms\android-36"),
    ("build-tools_r36_windows.zip", r"C:\src\Android\build-tools\36.0.0"),
]


def main():
    for name, dest in TARGETS:
        if os.path.isfile(os.path.join(dest, "source.properties")):
            print(f"[skip] {dest} 已存在", flush=True)
            continue
        print(f"[get ] {BASE}{name}", flush=True)
        data = urllib.request.urlopen(BASE + name, timeout=1800).read()
        print(f"[ok  ] {name} {len(data)} bytes", flush=True)
        os.makedirs(dest, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            z.extractall(dest)
        print(
            f"[done] -> {dest} source.properties="
            f"{os.path.isfile(os.path.join(dest, 'source.properties'))}",
            flush=True,
        )
    print("ALL_DONE", flush=True)


if __name__ == "__main__":
    main()
