#Requires -Version 5.1
<#
.SYNOPSIS
  资源占用：PSS 内存 + CPU 采样（可选边滚边采，观察长时间运行的增长）。

.DESCRIPTION
  内存取 `dumpsys meminfo` 的 TOTAL PSS（KB）；CPU 取 `dumpsys cpuinfo` 里本进程的百分比
  （系统给的是一段时间内的平均值，采样间隔要 ≥5s 才有意义）。
  不做任何「清缓存 / 杀后台」操作 —— 那样测出来的不是用户真实场景。

.EXAMPLE
  .\scripts\performance\Measure-MemoryCpu.ps1 -DurationSec 90 -IntervalSec 10 -Scroll
#>
param(
  [string]$Serial = '',
  [string]$Package = 'com.teacodeman.yanxin.qa',
  [int]$DurationSec = 60,
  [int]$IntervalSec = 10,
  [switch]$Scroll,
  [string]$RunId = '',
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$Serial = Select-PerfSerial $adb $Serial
$runId = if ($RunId) { $RunId } else { Get-Timestamp }
$dir = New-RunDir $runId 'memory-cpu'
$size = Get-ScreenSize $adb $Serial

function Get-Pid {
  $out = Invoke-AdbShell $adb $Serial "pidof $Package"
  if ($out -match '(\d+)') { return [int]$Matches[1] }
  return $null
}

function Get-PssKb {
  $txt = Invoke-AdbShell $adb $Serial "dumpsys meminfo $Package"
  if ($txt -match 'TOTAL PSS:\s*(\d+)') { return [int]$Matches[1] }
  # 老格式：TOTAL 行第一个数字
  foreach ($line in ($txt -split "`r?`n")) {
    if ($line -match '^\s*TOTAL\s+(\d+)') { return [int]$Matches[1] }
  }
  return $null
}

function Get-CpuPercent {
  # dumpsys cpuinfo 在空闲时恒为 0（它的窗口太短），改用 top 采 1 秒窗口的第二帧
  $p = Get-Pid
  if (-not $p) { return $null }
  $txt = Invoke-AdbShell $adb $Serial "top -b -n 2 -d 1 -p $p -o PID,%CPU"
  $line = ($txt -split "`r?`n" | Where-Object { $_ -match "^\s*$p\s" } | Select-Object -Last 1)
  if ($line -match "^\s*$p\s+([\d.]+)") { return [double]$Matches[1] }
  return $null
}

Write-Step "资源采样：$DurationSec s / 每 $IntervalSec s$(if ($Scroll) { '（采样间滚动页面）' })"
$pid1 = Get-Pid
if (-not $pid1) {
  Write-Note "$Package 没在运行，先拉起"
  Invoke-AdbShell $adb $Serial "monkey -p $Package -c android.intent.category.LAUNCHER 1" | Out-Null
  Start-Sleep -Seconds 5
  $pid1 = Get-Pid
}
if (-not $pid1) { Fail-Perf "$Package 起不来，无法采样" }
Write-Ok "pid=$pid1"

$samples = @()
$start = Get-Date
$i = 0
$cx = [int]($size.Width / 2)
while (((Get-Date) - $start).TotalSeconds -lt $DurationSec) {
  $i++
  if ($Scroll) {
    Invoke-AdbShell $adb $Serial "input swipe $cx $([int]($size.Height*0.72)) $cx $([int]($size.Height*0.32)) 200" | Out-Null
    Start-Sleep -Milliseconds 600
  }
  $pss = Get-PssKb
  $cpu = Get-CpuPercent
  $elapsed = [int]((Get-Date) - $start).TotalSeconds
  $samples += [pscustomobject]@{ sample = $i; elapsedSec = $elapsed; pssKb = $pss; cpuPercent = $cpu }
  Write-Host ("    #{0} t={1}s  PSS={2} MB  CPU={3}%" -f $i, $elapsed, [math]::Round(($pss / 1024), 1), $cpu)
  if (((Get-Date) - $start).TotalSeconds + $IntervalSec -gt $DurationSec) { break }
  Start-Sleep -Seconds $IntervalSec
}

$validPss = @($samples | Where-Object { $_.pssKb -ne $null } | ForEach-Object { $_.pssKb })
$validCpu = @($samples | Where-Object { $_.cpuPercent -ne $null } | ForEach-Object { $_.cpuPercent })
$summary = [ordered]@{
  pssMb = [ordered]@{
    first = if ($validPss.Count) { [math]::Round($validPss[0] / 1024, 1) } else { $null }
    last = if ($validPss.Count) { [math]::Round($validPss[-1] / 1024, 1) } else { $null }
    peak = if ($validPss.Count) { [math]::Round((($validPss | Measure-Object -Maximum).Maximum) / 1024, 1) } else { $null }
    growth = if ($validPss.Count) { [math]::Round(($validPss[-1] - $validPss[0]) / 1024, 1) } else { $null }
  }
  cpuPercent = Get-Stats ([double[]]$validCpu)
}

Write-CsvFile $samples (Join-Path $dir 'memory-cpu-samples.csv')
Write-JsonFile ([ordered]@{
  scenario = 'memory-cpu'; runId = $runId; generatedAt = (Get-Date).ToString('o')
  package = $Package; device = Get-DeviceInfo $adb $Serial
  durationSec = $DurationSec; intervalSec = $IntervalSec; scroll = [bool]$Scroll
  samples = $samples; summary = $summary
}) (Join-Path $dir 'memory-cpu.json')

Write-Step '汇总'
Write-Ok ("PSS 首 {0} MB → 末 {1} MB（峰值 {2} MB，增长 {3} MB）" -f $summary.pssMb.first, $summary.pssMb.last, $summary.pssMb.peak, $summary.pssMb.growth)
if ($summary.cpuPercent) { Write-Ok ("CPU 均值 {0}% / P95 {1}%（dumpsys cpuinfo 的滑动窗口值）" -f $summary.cpuPercent.mean, $summary.cpuPercent.p95) }
Write-Host "结果目录：$dir"
