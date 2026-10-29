#Requires -Version 5.1
<#
.SYNOPSIS
  启动性能：冷启动 / 热启动（进程仍在，Activity 已退到后台）× N 次。

.DESCRIPTION
  测量口径（三条都记，别混用）：
    - TotalTime  : `am start -W` 报的"本次启动总耗时"（含 Activity 创建到首次绘制），单位 ms
    - WaitTime   : 调用方等到"启动完成"的时间，通常 ≥ TotalTime
    - Displayed  : logcat `ActivityTaskManager ... Displayed pkg/act: +1s234ms` —— **首个可交互帧真正上屏**
  注意：TotalTime/Displayed 都不是"用户能点下去"的时间（Flutter 首帧之后还有 Image/font 解码、
  首屏数据查询），真正可交互要配合 `PerfFrame` 或人工走查判断（见报告"局限"一节）。

.EXAMPLE
  .\scripts\performance\Measure-Startup.ps1 -Serial MRN7ONWCUSHYG65D
#>
param(
  [string]$Serial = '',
  [string]$Package = 'com.teacodeman.yanxin.qa',
  [string]$Activity = '',                 # 空 = 用 `cmd package resolve-activity` 自动解析
  [int]$ColdRuns = 5,
  [int]$WarmRuns = 5,
  [string]$RunId = '',
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe',
  [string]$Flutter = 'D:\Download\Flutter\flutter\bin\flutter.bat'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$Serial = Select-PerfSerial $adb $Serial
$runId = if ($RunId) { $RunId } else { Get-Timestamp }
$dir = New-RunDir $runId 'startup'

function Resolve-Activity {
  param([string]$Pkg)
  $txt = Invoke-AdbShell $adb $Serial "cmd package resolve-activity --brief $Pkg"
  foreach ($line in ($txt -split "`r?`n")) {
    if ($line -match "^$([regex]::Escape($Pkg))/\S+") { return $line.Trim() }
  }
  return $null
}

$component = if ($Activity) { $Activity } else { Resolve-Activity $Package }
if (-not $component) { Fail-Perf "解析不到 $Package 的启动 Activity（用 -Activity pkg/.MainActivity 手动指定）" }
Write-Step "启动测试：$component"
$app = Get-AppInfo $adb $Serial $Package
Write-Ok "versionCode=$($app.versionCode) versionName=$($app.versionName)"

function Start-And-Measure {
  param([string]$Mode)
  Invoke-AdbShell $adb $Serial 'logcat -c' | Out-Null
  if ($Mode -eq 'cold') {
    Invoke-AdbShell $adb $Serial "am force-stop $Package" | Out-Null
    Start-Sleep -Milliseconds 1500
  } else {
    # 热启动：进程保留，Activity 退到后台
    Invoke-AdbShell $adb $Serial 'input keyevent KEYCODE_HOME' | Out-Null
    Start-Sleep -Milliseconds 1200
  }
  $deadline = (Get-Date).AddSeconds(30)
  $amOut = Invoke-AdbShell $adb $Serial "am start -W -n $component"
  while ((Get-Date) -lt $deadline) {
    if ($amOut -match 'TotalTime:\s*(\d+)') { break }
    Start-Sleep -Milliseconds 300
    $amOut += Invoke-AdbShell $adb $Serial "am start -W -n $component"
  }
  Start-Sleep -Milliseconds 700

  $total = $null; $wait = $null; $launchState = ''
  if ($amOut -match 'TotalTime:\s*(\d+)') { $total = [int]$Matches[1] }
  if ($amOut -match 'WaitTime:\s*(\d+)') { $wait = [int]$Matches[1] }
  if ($amOut -match 'LaunchState:\s*(\w+)') { $launchState = $Matches[1] }

  # Displayed（首帧上屏）：Android 12+ 形如 `Displayed pkg/act for user 0: +1s234ms`
  # （中间还有 "for user 0"，所以不能写死 "pkg/act:" 的正则）
  $displayedMs = $null
  for ($i = 0; $i -lt 10 -and $null -eq $displayedMs; $i++) {
    $log = Invoke-AdbShell $adb $Serial 'logcat -d -s ActivityTaskManager:I'
    $hit = $log -split "`r?`n" | Where-Object { $_ -match 'Displayed' -and $_ -match [regex]::Escape($Package) } | Select-Object -First 1
    if ($hit) {
      if ($hit -match '\+(\d+)s(\d+)ms') { $displayedMs = [int]$Matches[1] * 1000 + [int]$Matches[2] }
      elseif ($hit -match '\+(\d+)ms') { $displayedMs = [int]$Matches[1] }
    } else {
      Start-Sleep -Milliseconds 300
    }
  }
  Invoke-AdbShell $adb $Serial 'input keyevent KEYCODE_HOME' | Out-Null
  return [pscustomobject]@{ Mode = $Mode; LaunchState = $launchState; TotalTime = $total; WaitTime = $wait; Displayed = $displayedMs }
}

$rows = @()
foreach ($mode in @('cold', 'warm')) {
  $n = if ($mode -eq 'cold') { $ColdRuns } else { $WarmRuns }
  if ($n -le 0) { continue }
  Write-Step ("{0} 启动 × {1}" -f $mode, $n)
  for ($i = 1; $i -le $n; $i++) {
    $r = Start-And-Measure -Mode $mode
    $rows += [pscustomobject]@{
      iteration   = $i
      mode        = $mode
      launchState = $r.LaunchState
      totalTimeMs = $r.TotalTime
      waitTimeMs  = $r.WaitTime
      displayedMs = $r.Displayed
    }
    Write-Host ("    #{0}  state={1,-5} total={2}ms wait={3}ms displayed={4}ms" -f $i, $r.LaunchState, $r.TotalTime, $r.WaitTime, $r.Displayed)
  }
}

$summary = [ordered]@{}
foreach ($mode in @('cold', 'warm')) {
  $subset = $rows | Where-Object { $_.mode -eq $mode }
  if (-not $subset) { continue }
  $summary[$mode] = [ordered]@{
    totalTime = Get-Stats ([double[]]($subset | Where-Object { $_.totalTimeMs -ne $null } | ForEach-Object { $_.totalTimeMs }))
    displayed = Get-Stats ([double[]]($subset | Where-Object { $_.displayedMs -ne $null } | ForEach-Object { $_.displayedMs }))
  }
}

Write-CsvFile $rows (Join-Path $dir 'startup-runs.csv')
Write-JsonFile ([ordered]@{
  scenario = 'startup'
  runId = $runId
  generatedAt = (Get-Date).ToString('o')
  package = $Package
  component = $component
  device = Get-DeviceInfo $adb $Serial
  app = $app
  runs = $rows
  summary = $summary
}) (Join-Path $dir 'startup.json')

Write-Step '汇总'
foreach ($mode in $summary.Keys) {
  $t = $summary[$mode].totalTime
  $dd = $summary[$mode].displayed
  if ($t) { Write-Ok ("{0,-4} TotalTime  均值 {1} / 中位 {2} / P95 {3} ms" -f $mode, $t.mean, $t.median, $t.p95) }
  if ($dd) { Write-Ok ("{0,-4} Displayed  均值 {1} / 中位 {2} / P95 {3} ms" -f $mode, $dd.mean, $dd.median, $dd.p95) }
}
Write-Host ''
Write-Host "结果目录：$dir"
