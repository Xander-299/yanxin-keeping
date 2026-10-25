<#
.SYNOPSIS
  在真机上跑一次「设备 × 模型」基准，直接输出 SPEC-local-ai.md §4.2 要的那一行表。

.DESCRIPTION
  做三件事：
  1. 把探针（bench_android + 依赖 .so + 中文 prompt 集）和模型推到 /data/local/tmp/llmbench
     （按字节数跳过重复推送）；
  2. 跑探针（贪心解码，逐轮打印耗时与 RSS），同时从宿主机侧每 15 秒采一次电池温度与 CPU 频率
     —— HyperOS 下 /sys/class/thermal/** 对 shell 是 Permission denied，温度只能走 `dumpsys battery`；
  3. 解析成一行 markdown + 一份原始日志，便于回填基准表。

  口径（与 SPEC §4.2 一致，别改）：
  - 「冷加载」= llama_model_load_from_file 的墙钟时间（含建页表，不含首次解码）；
  - 「首 token」= 首轮 prefill 完成并采样出第一个 token 的时间；
  - 「pp tok/s」= prompt 处理速率；「tg tok/s」= 除首 token 外的生成速率；
  - 「N 轮后 RSS」取最后一轮 VmRSS；「温升」取首末电池温度差；
  - 中途不杀进程，所以 RSS 曲线能看出「越跑越涨还是稳」。

  注意：本机是 **Windows PowerShell 5.1**（没有 pwsh 7），脚本必须存成 UTF-8 **with BOM**，
  否则中文注释会被当 ANSI 读 → 语法错。

.EXAMPLE
  powershell -File tool/llm_bench/run_bench.ps1 `
    -ModelPath D:\yanxin-llm-bench\models\qwen2.5-1.5b-instruct-q4_k_m.gguf `
    -Label 'Qwen2.5-1.5B-Instruct Q4_K_M' -CpuMask f0 -Threads 4 -Rounds 10
#>
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [Parameter(Mandatory)][string]$Label,
  [int]$Ctx = 2048,
  [int]$Threads = 4,
  [int]$Rounds = 10,
  [int]$Minutes = 0,
  [string]$CpuMask = '',   # 亲和性掩码（十六进制），'f0' = 只跑 cpu4-7（mt6895 的大核 A78 @2.85GHz）
  [string]$WorkRoot = 'D:\yanxin-llm-bench',
  [string]$OutDir = 'out',   # out = 基线（armv8-a）；out-dp = dotprod 变体
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe',
  [string]$Remote = '/data/local/tmp/llmbench'
)

# 同 build_android.ps1：不设 Stop（adb 会把正常进度写到 stderr）。
$ErrorActionPreference = 'Continue'
function Fail($msg) { Write-Host "!! $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$out = Join-Path $WorkRoot $OutDir
if (-not (Test-Path (Join-Path $out 'bench_android'))) { Fail '探针还没编：先跑 tool/llm_bench/build_android.ps1' }
if (-not (Test-Path $ModelPath)) { Fail "模型不存在：$ModelPath" }

# 设备上某个文件的字节数；不存在返回 -1。
# 注意：**不要**在 adb 的 shell 命令串里写 `2>/dev/null` —— Windows PowerShell 会把它当自己的
# 重定向解析（报 "Could not find a part of the path 'D:\dev\null'"）。
function Get-RemoteSize([string]$path) {
  $raw = & $Adb shell "stat -c %s '$path'" 2>$null
  if ($LASTEXITCODE -ne 0) { return -1 }
  $v = 0L
  if ([long]::TryParse((($raw -join '') -replace '\s', ''), [ref]$v)) { return $v }
  return -1
}

$deviceLines = @((& $Adb devices) -split "`n" | Where-Object { $_ -match '\sdevice\s*$' })
if ($deviceLines.Count -eq 0) { Fail '没有设备：adb devices 为空（插上手机 / 开 USB 调试）' }
Write-Host ('    设备：' + $deviceLines[0].Trim())

$modelFile = Split-Path $ModelPath -Leaf
$modelMB = [math]::Round((Get-Item $ModelPath).Length / 1MB, 0)

# ── 1. 推探针 ──
Step "推探针 → $Remote"
& $Adb shell "mkdir -p $Remote/models" 2>&1 | Out-Null
$files = @(Get-ChildItem "$out\*.so") + @(Get-ChildItem "$out\bench_android") + @(Get-ChildItem "$out\prompts_finance.txt")
foreach ($f in $files) {
  if ((Get-RemoteSize "$Remote/$($f.Name)") -ne $f.Length) {
    & $Adb push $f.FullName "$Remote/$($f.Name)" 2>&1 | Out-Null
    Write-Host "    + $($f.Name)"
  }
}

# ── 2. 推模型（GB 级，按字节数跳过）──
$remoteModel = "$Remote/models/$modelFile"
if ((Get-RemoteSize $remoteModel) -ne (Get-Item $ModelPath).Length) {
  Step "推模型（$modelMB MB）"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $Adb push $ModelPath $remoteModel 2>&1 | Select-Object -Last 1
  Write-Host ('    耗时 ' + $sw.Elapsed.TotalSeconds.ToString('0.0') + ' s')
} else {
  Write-Host '    模型已在设备上，跳过推送'
}
& $Adb shell "chmod 755 $Remote/bench_android" 2>&1 | Out-Null

# ── 3. 基线温度 ──
function Get-BattTempC {
  $raw = (@(& $Adb shell 'dumpsys battery | grep temperature') -join '') -replace '[^0-9]', ''
  if (-not $raw) { return $null }
  return [int]$raw / 10.0
}
# 返回 "小核当前频率/大核当前频率"（MHz）
function Get-CpuFreqs {
  $raw = & $Adb shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq'
  $vals = @($raw | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [math]::Round([int]$_ / 1000) })
  return ($vals -join '/')
}
$tempStart = Get-BattTempC
Write-Host "    起始电池温度：$tempStart ℃"

# ── 4. 跑探针（后台）+ 主机侧每 15 s 采温度 / 频率 ──
$gen = if ($Minutes -gt 0) { '--minutes ' + $Minutes } else { '-r ' + $Rounds }
$prefix = if ($CpuMask) { "taskset $CpuMask " } else { '' }
$inner = "./bench_android -m models/$modelFile -c $Ctx -t $Threads $gen " +
         "--prompt-file prompts_finance.txt --freq-path /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq"
$cmd = "cd $Remote && LD_LIBRARY_PATH=. $prefix$inner"
Write-Host "    `$ $cmd"
$raw = Join-Path $out ('raw-' + ($Label -replace '[^\w\.\-]+', '_') + '.txt')

$job = Start-Job -ScriptBlock {
  param($adb, $c, $file)
  & $adb shell $c 2>&1 | Set-Content -Path $file -Encoding utf8
} -ArgumentList $Adb, $cmd, $raw

$temps = New-Object System.Collections.Generic.List[double]
$freqs = New-Object System.Collections.Generic.List[string]
while ($job.State -eq 'Running') {
  $t = Get-BattTempC
  if ($null -ne $t) { $temps.Add($t) }
  $freqs.Add((Get-CpuFreqs))
  Start-Sleep -Seconds 15
}
$job | Wait-Job | Out-Null
$job | Remove-Job
$tempEnd = Get-BattTempC

# ── 5. 解析 ──
$text = Get-Content $raw -Raw
if ($text -match 'LOAD_FAILED') { Fail "模型加载失败，看原始日志：$raw" }
$cfg  = [regex]::Match($text, 'CFG ctx=(\d+) predict=(\d+) threads=(\d+)')
$meta = [regex]::Match($text, 'META desc=(.*) n_params=(\d+) model_bytes=(\d+) n_ctx_train=(\d+)')
$load = [regex]::Match($text, 'LOAD load_ms=([\d\.]+) rss_after_load_kb=(-?\d+)')
$sum  = [regex]::Match($text, 'SUMMARY rounds=(\d+) load_ms=([\d\.]+) ttft_ms_avg=([\d\.]+) pp_tps_avg=([\d\.]+) tg_tps_avg=([\d\.]+) peak_rss_kb=(-?\d+) wall_s=([\d\.]+)')
if (-not $sum.Success) { Fail "没拿到 SUMMARY，看原始日志：$raw" }
$rows = [regex]::Matches($text, 'ROUND i=(\d+) elapsed_s=[\d\.]+ prompt_tok=(\d+) gen_tok=(\d+) ttft_ms=([\d\.]+) pp_tps=([\d\.]+) gen_ms=[\d\.]+ tg_tps=([\d\.]+) rss_kb=(-?\d+)')
if ($rows.Count -eq 0) { Fail "没拿到任何 ROUND：$raw" }

$lastRow = $rows[$rows.Count - 1]
$rssSeries = @($rows | ForEach-Object { [math]::Round([double]$_.Groups[7].Value / 1024) })
$peakRss = [double]$sum.Groups[6].Value / 1024
$bigFreqs = @($freqs | ForEach-Object { ($_ -split '/')[1] } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
$minBig = if ($bigFreqs.Count) { ($bigFreqs | Measure-Object -Minimum).Minimum } else { 0 }

$threadLabel = '' + $Threads + $(if ($CpuMask) { '（唯大核 mask=' + $CpuMask + '）' } else { '' })
$markdown = '| ' + $Label + ' | ' + $meta.Groups[1].Value + ' | ' + $modelMB + ' MB | ctx ' +
  $cfg.Groups[1].Value + ' | ' + $threadLabel + ' | ' +
  [math]::Round([double]$load.Groups[1].Value) + ' ms | ' +
  [math]::Round([double]$rows[0].Groups[4].Value) + ' ms | ' +
  [math]::Round([double]$sum.Groups[4].Value, 1) + ' | ' +
  [math]::Round([double]$sum.Groups[5].Value, 1) + ' | ' +
  [math]::Round($peakRss) + ' MB | ' +
  $rssSeries[$rssSeries.Count - 1] + ' MB | ' +
  [math]::Round(($tempEnd - $tempStart), 1) + ' ℃（' + $tempStart + '→' + $tempEnd + '） | ' +
  $minBig + ' MHz |'

Write-Host ''
Write-Host '── 基准表一行 ──' -ForegroundColor Green
Write-Host $markdown
Write-Host '── 明细 ──'
Write-Host ('    轮数=' + $sum.Groups[1].Value + '  prompt_tok=' + $rows[0].Groups[2].Value + '  gen_tok=' + $rows[0].Groups[3].Value)
Write-Host ('    加载后 RSS=' + [math]::Round([double]$load.Groups[2].Value / 1024) + ' MB；每轮 RSS=' + ($rssSeries -join ' → ') + ' MB')
Write-Host ('    大核频率采样（MHz）：' + ($bigFreqs -join ' '))
Write-Host "    原始日志：$raw"
