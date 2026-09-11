# -*- coding: utf-8 -*-
"""多线程分片下载器：NDK r28b + CMake 3.22.1（腾讯镜像，走 7890 代理）。

用法：python dl_ndk.py [--verify-only]
断点续传：每个分片单独落盘 .part，全部到位后按序合并。
"""
import os
import sys
import time
import json
import threading
import urllib.request

PROXY = "http://127.0.0.1:7890"
JOBS = [
    # (url, 目标文件, 总大小)
    ("https://mirrors.cloud.tencent.com/AndroidSDK/android-ndk-r28b-windows.zip",
     r"C:\src\_dl\android-ndk-r28b-windows.zip", 748117965),
    ("https://mirrors.cloud.tencent.com/AndroidSDK/cmake-3.22.1-windows.zip",
     r"C:\src\_dl\cmake-3.22.1-windows.zip", None),
]

opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY})
)
opener.addheaders = [("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")]

CHUNK = 8 * 1024 * 1024  # 每片 8MB
THREADS = 8


def head_size(url):
    req = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
    with opener.open(req, timeout=60) as r:
        cr = r.headers.get("Content-Range", "")
        if "/" in cr:
            return int(cr.split("/")[-1])
        return int(r.headers.get("Content-Length") or 0)


def fetch_chunk(url, start, end, path, state, idx):
    for attempt in range(8):
        try:
            if os.path.exists(path) and os.path.getsize(path) == end - start + 1:
                return
            req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
            with opener.open(req, timeout=120) as r, open(path, "wb") as f:
                while True:
                    b = r.read(256 * 1024)
                    if not b:
                        break
                    f.write(b)
            if os.path.getsize(path) == end - start + 1:
                return
        except Exception as e:
            time.sleep(min(2 ** attempt, 20))
            print(f"[chunk {idx}] retry {attempt}: {e}", flush=True)
    raise RuntimeError(f"chunk {idx} failed permanently")


def download(url, dest, total=None):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    meta_path = dest + ".meta.json"
    part_dir = dest + ".parts"
    os.makedirs(part_dir, exist_ok=True)

    if total is None:
        total = head_size(url)
        print(f"size: {total} bytes", flush=True)
    if os.path.exists(dest) and os.path.getsize(dest) == total:
        print(f"already complete: {dest}", flush=True)
        return

    chunks = []
    off = 0
    i = 0
    while off < total:
        end = min(off + CHUNK, total) - 1
        chunks.append((i, off, end))
        off = end + 1
        i += 1

    lock = threading.Lock()
    done = [0]
    t0 = time.time()

    def worker(jobs):
        while True:
            with lock:
                if not jobs:
                    return
                idx, s, e = jobs.pop(0)
            fetch_chunk(url, s, e, os.path.join(part_dir, f"{idx:05d}.part"), None, idx)
            with lock:
                done[0] += 1
                el = time.time() - t0
                got = done[0] * CHUNK
                pct = 100.0 * got / total
                print(f"  {pct:5.1f}%  {got/1e6:7.1f}MB  {got/max(el,0.1)/1e6:.2f}MB/s",
                      flush=True)

    threads = [threading.Thread(target=worker, args=(list(chunks),)) for _ in range(THREADS)]
    # 共享任务队列
    jobq = list(chunks)
    threads = [threading.Thread(target=worker, args=(jobq,)) for _ in range(THREADS)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    # 合并
    with open(dest, "wb") as out:
        for idx, s, e in chunks:
            p = os.path.join(part_dir, f"{idx:05d}.part")
            with open(p, "rb") as f:
                while True:
                    b = f.read(1 << 22)
                    if not b:
                        break
                    out.write(b)
    assert os.path.getsize(dest) == total, "merged size mismatch"
    print(f"DONE {dest} {total} bytes, {time.time()-t0:.0f}s", flush=True)


if __name__ == "__main__":
    for url, dest, size in JOBS:
        print(f"=== {dest}", flush=True)
        download(url, dest, size)
    print("ALL DONE", flush=True)
