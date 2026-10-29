#Requires -Version 5.1
<#
.SYNOPSIS
  页面流畅度：用 `dumpsys gfxinfo` 统计帧数 / 掉帧率 / 百分位，配合脚本化手势驱动。

.DESCRIPTION
  为什么用 gfxinfo：它由系统 RenderThread 统计，**profile / release 包都能用**，不需要改代码、
  不需要 DevTools 会话。局限：
    - 只统计「本应用窗口」提交的帧，Flutter 的 SurfaceView 内容一般能统计到，但某些机型/版本会报 0 帧
      （脚本会显式告警，不静默当成 0 卡顿）；
    - 百分比是"超过 16.67ms 预算"的帧占比（60Hz）；设备若跑 120Hz 预算变成 8.3ms，不能横比。

.EXAMPLE
  .\scripts\performance\Measure-Frames.ps1 -Scenario home-scroll -Swipes 8
  .\scripts\performance\Measure-Frames.ps1 -Scenario calendar-swipe -Swipes 6
#>
param(
  [string]$Serial = '',
  [string]$Package = 'com.teacodeman.yanxin.qa',
  [ValidateSet('home-scroll', 'calendar-swipe', 'tab-switch', 'record-open')]
  [string]$Scenario = 'home-scroll',
  [int]$Swipes = 8,
  [int]$Iterations = 3,
  [string]$RunId = '',
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$Serial = Select-PerfSerial $adb $Serial
$runId = if ($RunId) { $RunId } else { Get-Timestamp }
$dir = New-RunDir $runId ("frames-$Scenario")
$size = Get-ScreenSize $adb $Serial
$refresh = Get-RefreshRate $adb $Serial

Write-Step "帧统计：$Scenario（$($size.Width)x$($size.Height) @${refresh}Hz）"

function Reset-App {
  Invoke-AdbShell $adb $Serial "am force-stop $Package" | Out-Null
  Start-Sleep -Milliseconds 800
  Invoke-AdbShell $adb $Serial "monkey -p $Package -c android.intent.category.LAUNCHER 1" | Out-Null
  Start-Sleep -Seconds 4
}

function Invoke-Scenario {
  param([string]$Name, [int]$Times)
  $w = $size.Width; $h = $size.Height; $cx = [int]($w / 2)
  switch ($Name) {
    'home-scroll' {
      for ($i = 0; $i -lt $Times; $i++) {
        Invoke-AdbShell $adb $Serial "input swipe $cx $([int]($h*0.72)) $cx $([int]($h*0.30)) 220" | Out-Null
        Start-Sleep -Milliseconds 120
      }
      for ($i = 0; $i -lt $Times; $i++) {
        Invoke-AdbShell $adb $Serial "input swipe $cx $([int]($h*0.30)) $cx $([int]($h*0.72)) 220" | Out-Null
        Start-Sleep -Milliseconds 120
      }
    }
    'calendar-swipe' {
      # 底栏第 2 个 tab = 日历
      Invoke-AdbShell $adb $Serial "input tap $([int]($w*0.30)) $([int]($h*0.96))" | Out-Null
      Start-Sleep -Milliseconds 1500
      for ($i = 0; $i -lt $Times; $i++) {
        $dir = if ($i % 2 -eq 0) { 1 } else { -1 }
        $fromX = if ($dir -gt 0) { [int]($w*0.78) } else { [int]($w*0.22) }
        $toX = if ($dir -gt 0) { [int]($w*0.22) } else { [int]($w*0.78) }
        Invoke-AdbShell $adb $Serial "input swipe $fromX $([int]($h*0.30)) $toX $([int]($h*0.30)) 200" | Out-Null
        Start-Sleep -Milliseconds 500
      }
    }
    'tab-switch' {
      for ($i = 0; $i -lt $Times; $i++) {
        $x = [int]($w * (0.12 + 0.25 * ($i % 4)))
        Invoke-AdbShell $adb $Serial "input tap $x $([int]($h*0.96))" | Out-Null
        Start-Sleep -Milliseconds 700
      }
    }
    'record-open' {
      for ($i = 0; $i -lt $Times; $i++) {
        # 底栏中央「记一笔」
        Invoke-AdbShell $adb $Serial "input tap $cx $([int]($h*0.955))" | Out-Null
        Start-Sleep -Milliseconds 1200
        Invoke-AdbShell $adb $Serial "input keyevent KEYCODE_BACK" | Out-Null
        Start-Sleep -Milliseconds 700
      }
    }
  }
}

function Read-GfxInfo {
  $txt = Invoke-AdbShell $adb $Serial "dumpsys gfxinfo $Package"
  $o = [ordered]@{ totalFrames = $null; jankyFrames = $null; jankyPercent = $null; p50 = $null; p90 = $null; p95 = $null; p99 = $null; missedVsync = $null; slowUi = $null }
  if ($txt -match 'Total frames rendered:\s*(\d+)') { $o.totalFrames = [int]$Matches[1] }
  if ($txt -match 'Janky frames:\s*(\d+)\s*\(([\d.]+)%\)') { $o.jankyFrames = [int]$Matches[1]; $o.jankyPercent = [double]$Matches[2] }
  if ($txt -match '50th percentile:\s*(\d+)ms') { $o.p50 = [int]$Matches[1] }
  if ($txt -match '90th percentile:\s*(\d+)ms') { $o.p90 = [int]$Matches[1] }
  if ($txt -match '95th percentile:\s*(\d+)ms') { $o.p95 = [int]$Matches[1] }
  if ($txt -match '99th percentile:\s*(\d+)ms') { $o.p99 = [int]$Matches[1] }
  if ($txt -match 'Number Missed Vsync:\s*(\d+)') { $o.missedVsync = [int]$Matches[1] }
  if ($txt -match 'Number Slow UI thread:\s*(\d+)') { $o.slowUi = [int]$Matches[1] }
  return $o
}

$rows = @()
for ($i = 1; $i -le $Iterations; $i++) {
  Reset-App
  Invoke-AdbShell $adb $Serial "dumpsys gfxinfo $Package reset" | Out-Null
  Invoke-Scenario -Name $Scenario -Times $Swipes
  Start-Sleep -Milliseconds 600
  $g = Read-GfxInfo
  if ($null -eq $g.totalFrames -or $g.totalFrames -eq 0) {
    Write-Note "#$i gfxinfo 报告 0 帧 —— 该机型/该包可能统计不到 Flutter 的 SurfaceView，本场景记为「未测量」"
  } else {
    Write-Host ("    #{0} 帧数 {1} · 掉帧 {2} ({3}%) · p50 {4}ms · p95 {5}ms · p99 {6}ms" -f $i, $g.totalFrames, $g.jankyFrames, $g.jankyPercent, $g.p50, $g.p95, $g.p99)
  }
  $rows += [pscustomobject]@{
    iteration = $i; scenario = $Scenario; swipes = $Swipes
    totalFrames = $g.totalFrames; jankyFrames = $g.jankyFrames; jankyPercent = $g.jankyPercent
    p50 = $g.p50; p90 = $g.p90; p95 = $g.p95; p99 = $g.p99
    missedVsync = $g.missedVsync; slowUiThread = $g.slowUi
  }
}

$valid = $rows | Where-Object { $_.totalFrames -ne $null -and $_.totalFrames -gt 0 }
$summary = [ordered]@{
  measured = ($valid.Count -gt 0)
  refreshRate = $refresh
  frameBudgetMs = if ($refresh) { [math]::Round(1000 / $refresh, 2) } else { $null }
  totalFrames = Get-Stats ([double[]]($valid | ForEach-Object { $_.totalFrames }))
  jankyPercent = Get-Stats ([double[]]($valid | ForEach-Object { $_.jankyPercent }))
  p95 = Get-Stats ([double[]]($valid | ForEach-Object { $_.p95 }))
}

Write-CsvFile $rows (Join-Path $dir 'frames-runs.csv')
Write-JsonFile ([ordered]@{
  scenario = "frames-$Scenario"; runId = $runId; generatedAt = (Get-Date).ToString('o')
  package = $Package; device = Get-DeviceInfo $adb $Serial; screen = $size; refreshRate = $refresh
  iterations = $Iterations; swipes = $Swipes; runs = $rows; summary = $summary
}) (Join-Path $dir 'frames.json')

Write-Step '汇总'
if (-not $summary.measured) {
  Write-Note 'gfxinfo 全程 0 帧 → 记为「未测量」（不要当成 0 掉帧）'
} else {
  Write-Ok ("掉帧率 均值 {0}% / P95 {1}%" -f $summary.jankyPercent.mean, $summary.jankyPercent.p95)
  Write-Ok ("p95 帧耗时 均值 {0}ms（预算 {1}ms @ {2}Hz）" -f $summary.p95.mean, $summary.frameBudgetMs, $refresh)
}
Write-Host "结果目录：$dir"
