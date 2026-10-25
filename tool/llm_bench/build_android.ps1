<#
.SYNOPSIS
  编 Android 端 llama.cpp 静态/共享库 + 本仓库的基准探针 `bench_android`（阶段二 §4.2）。

.DESCRIPTION
  产物（默认）：
    D:\yanxin-llm-bench\out\bench_android        端上可执行（arm64-v8a）
    D:\yanxin-llm-bench\out\*.so                 它依赖的 llama / ggml 动态库
    D:\yanxin-llm-bench\out\build-info.txt       llama.cpp commit + NDK 版本（基准表要写死这两项）

  为什么源码与产物放在仓库外：
  - 本仓库在**中文路径**下（`D:\new file\...`），NDK / ninja 偶发拒绝非 ASCII 路径；
  - llama.cpp 源码 + 中间产物 1–2 GB，不该进版本库。
  所以本脚本把源码 clone 到 `-WorkRoot`（默认 `D:\yanxin-llm-bench`），只把**探针源码**
  （`tool/llm_bench/bench_android.cpp`）留在仓库里，保证测量口径可复现。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/llm_bench/build_android.ps1
  powershell -File tool/llm_bench/build_android.ps1 -LlamaTag b7050 -Jobs 4
#>
param(
  [string]$WorkRoot = 'D:\yanxin-llm-bench',
  [string]$LlamaTag = 'b7050',
  [string]$Ndk = 'D:\Download\Java\Android\ndk\28.2.13676358',
  [string]$CmakeBin = 'D:\Download\Java\Android\cmake\3.22.1\bin',
  [string]$Abi = 'arm64-v8a',
  [string]$Platform = 'android-24',
  [int]$Jobs = 4,
  [string]$BuildDir = '',
  [string]$OutDir = 'out',
  [string]$ArmArch = ''   # 例如 'armv8.2-a+dotprod'（大核支持 SDOT 时 Q4_K 会快一截）
)

# 注意：**不要**设成 Stop —— cmake / clang 正常也会往 stderr 写，
# Windows PowerShell 5.1 会把 stderr 当错误记录，Stop 会让脚本在第一条日志上就退出。
# 失败一律用 $LASTEXITCODE 判。
$ErrorActionPreference = 'Continue'
function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "!! $msg" -ForegroundColor Red; exit 1 }

$repo      = Join-Path $WorkRoot 'llama.cpp'
if (-not $BuildDir) { $BuildDir = "build-$Abi" }
$build     = Join-Path $WorkRoot $BuildDir
$out       = Join-Path $WorkRoot $OutDir
$cmake     = Join-Path $CmakeBin 'cmake.exe'
$ninja     = Join-Path $CmakeBin 'ninja.exe'
$srcBench  = Join-Path $PSScriptRoot 'bench_android.cpp'

if (-not (Test-Path $cmake)) { Fail "找不到 cmake：$cmake（用 -CmakeBin 指定 SDK 的 cmake 目录）" }
if (-not (Test-Path "$Ndk\build\cmake\android.toolchain.cmake")) { Fail "NDK 不对：$Ndk" }
if (-not (Test-Path $srcBench)) { Fail "找不到探针源码：$srcBench" }
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ── 1. 源码：浅克隆到固定 tag（基准必须能复现到同一个 commit）──
if (-not (Test-Path "$repo\.git")) {
  Step "clone llama.cpp @ $LlamaTag → $repo"
  & git clone --depth 1 --branch $LlamaTag https://github.com/ggml-org/llama.cpp.git $repo
  if ($LASTEXITCODE -ne 0) { Fail '克隆失败（网络？换代理后重试）' }
} else {
  Step "复用已有源码：$repo"
}
$commit = (& git -C $repo rev-parse --short HEAD).Trim()
$tagNow = (& git -C $repo describe --tags 2>$null)
Write-Host "    commit=$commit tag=$tagNow"

# ── 2. 配置 + 编库（llama / llama-bench / llama-cli；后者用于人工看生成质量）──
$needConfigure = -not (Test-Path (Join-Path $build 'CMakeCache.txt'))
if ($needConfigure) {
  Step "configure（$Abi / $Platform / Ninja）"
  & $cmake -S $repo -B $build -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" `
    "-DCMAKE_TOOLCHAIN_FILE=$Ndk\build\cmake\android.toolchain.cmake" `
    "-DANDROID_ABI=$Abi" "-DANDROID_PLATFORM=$Platform" `
    -DCMAKE_BUILD_TYPE=Release `
    -DLLAMA_CURL=OFF -DGGML_OPENMP=OFF -DGGML_BACKEND_DL=OFF -DGGML_NATIVE=OFF -DGGML_CCACHE=OFF `
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_EXAMPLES=ON `
    "-DGGML_CPU_ARM_ARCH=$ArmArch"
  if ($LASTEXITCODE -ne 0) { Fail 'configure 失败' }
}

Step "编译 llama / llama-bench / llama-cli（-j $Jobs；内存紧张就调小）"
& $cmake --build $build --target llama llama-bench llama-cli -j $Jobs
if ($LASTEXITCODE -ne 0) { Fail '编译失败（本机内存不足会先崩 ninja，见 HANDOFF 的内存提示）' }

# ── 3. 编基准探针（链接刚编出来的 .so）──
$api = $Platform -replace '^android-', ''
$cxx = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android$api-clang++.cmd"
if (-not (Test-Path $cxx)) { Fail "找不到交叉编译器：$cxx" }

Step '编译 bench_android'
# 直接按**全路径**链接 .so：NDK 的 clang++.cmd 包装层会把 `-L<dir> -lxxx` 丢掉
# （实测 `ld.lld: error: unable to find library -llama`，文件明明就在那个目录里）。
$libs = @('libllama.so', 'libggml.so', 'libggml-base.so', 'libggml-cpu.so') |
  ForEach-Object { Join-Path "$build\bin" $_ }
foreach ($l in $libs) { if (-not (Test-Path $l)) { Fail "缺少链接产物：$l" } }
$benchOut = Join-Path $out 'bench_android'
& $cxx -O3 -std=c++17 -fPIE -pie -DNDEBUG `
  "-I$repo\include" "-I$repo\ggml\include" `
  $srcBench -o $benchOut @libs -static-libstdc++
if ($LASTEXITCODE -ne 0) { Fail 'bench_android 编译失败' }

# ── 4. 收拢产物 + 记账 ──
Step '收集 .so 到 out'
Get-ChildItem "$build\bin\*.so" | ForEach-Object { Copy-Item $_.FullName $out -Force }
Copy-Item (Join-Path $PSScriptRoot 'prompts_finance.txt') $out -Force

$ndkRev = (Get-Content (Join-Path $Ndk 'source.properties') | Select-String 'Pkg.Revision').Line
@(
  "llama_cpp_tag=$tagNow",
  "llama_cpp_commit=$commit",
  "abi=$Abi",
  "android_platform=$Platform",
  "ndk=$ndkRev",
  "built_at=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
) | Set-Content (Join-Path $out 'build-info.txt') -Encoding utf8

Step '完成'
Get-ChildItem $out | Select-Object Name, @{n='MB'; e={[math]::Round($_.Length/1MB, 1)}} | Format-Table -AutoSize
Write-Host "产物目录：$out"
