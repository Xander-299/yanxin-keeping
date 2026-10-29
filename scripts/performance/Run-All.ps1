#Requires -Version 5.1
<#
.SYNOPSIS
  一条命令跑完当前能自动化的全部性能场景，结果落到 performance-results\<runId>\。

.DESCRIPTION
  顺序：环境 → 启动 → 帧（首页滚动 / 日历翻月）→ 内存 CPU → 包体积。
  每个子脚本各自出 JSON + CSV，这里再写一份 index.json 汇总本次 run 的清单。

  前置：设备已连、**profile 包已装**（`adb install -r -t build\app\outputs\flutter-apk\app-profile.apk`）。
  不做的：清数据、改业务库、卸载用户正式包。

.EXAMPLE
  .\scripts\performance\Run-All.ps1 -Serial MRN7ONWCUSHYG65D
  .\scripts\performance\Run-All.ps1 -SkipApkBuild
#>
param(
  [string]$Serial = '',
  [string]$Package = 'com.teacodeman.yanxin.qa',
  [int]$ColdRuns = 5,
  [int]$WarmRuns = 5,
  [int]$FrameIterations = 3,
  [int]$Swipes = 8,
  [int]$MemorySeconds = 45,
  [switch]$SkipApkBuild,
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe',
  [string]$Flutter = 'D:\Download\Flutter\flutter\bin\flutter.bat'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$Serial = Select-PerfSerial $adb $Serial
$runId = Get-Timestamp
Write-Step "本次 run: $runId（设备 $Serial，包 $Package）"

$results = [ordered]@{ runId = $runId; startedAt = (Get-Date).ToString('o'); steps = @() }

function Invoke-Step([string]$Name, [scriptblock]$Body) {
  Write-Step $Name
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    & $Body
    $results.steps += [ordered]@{ name = $Name; ok = $true; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
  } catch {
    Write-Note "$Name 失败：$($_.Exception.Message)"
    $results.steps += [ordered]@{ name = $Name; ok = $false; error = $_.Exception.Message; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
  }
}

Invoke-Step 'environment' { & (Join-Path $PSScriptRoot 'Measure-Environment.ps1') -Serial $Serial -Package $Package -Adb $adb -Flutter $Flutter -OutDir $runId }
Invoke-Step 'startup'     { & (Join-Path $PSScriptRoot 'Measure-Startup.ps1') -Serial $Serial -Package $Package -ColdRuns $ColdRuns -WarmRuns $WarmRuns -RunId $runId -Adb $adb }
Invoke-Step 'frames-home' { & (Join-Path $PSScriptRoot 'Measure-Frames.ps1') -Serial $Serial -Package $Package -Scenario home-scroll -Swipes $Swipes -Iterations $FrameIterations -RunId $runId -Adb $adb }
Invoke-Step 'frames-calendar' { & (Join-Path $PSScriptRoot 'Measure-Frames.ps1') -Serial $Serial -Package $Package -Scenario calendar-swipe -Swipes $Swipes -Iterations $FrameIterations -RunId $runId -Adb $adb }
Invoke-Step 'memory-cpu' { & (Join-Path $PSScriptRoot 'Measure-MemoryCpu.ps1') -Serial $Serial -Package $Package -DurationSec $MemorySeconds -IntervalSec 8 -Scroll -RunId $runId -Adb $adb }
if (-not $SkipApkBuild) {
  Invoke-Step 'apk-size' { & (Join-Path $PSScriptRoot 'Measure-ApkSize.ps1') -Serial $Serial -Modes profile,release -RunId $runId -Adb $adb -Flutter $Flutter }
}

$results.finishedAt = (Get-Date).ToString('o')
$root = Join-Path $script:ResultRoot $runId
Write-JsonFile $results (Join-Path $root 'index.json')
Write-Step '完成'
foreach ($s in $results.steps) {
  $flag = if ($s.ok) { '[OK]' } else { '[!!]' }
  Write-Host ("    {0} {1,-16} {2}s{3}" -f $flag, $s.name, $s.seconds, $(if ($s.error) { "  " + $s.error } else { '' }))
}
Write-Host "结果目录：$root"
