#Requires -Version 5.1
<#
  性能测试公共库（dot-source 使用）。

  . .\scripts\performance\PerfCommon.ps1

  约定：
  - 只读设备（除了显式 force-stop / start），不清数据、不改业务库；
  - 所有脚本都要求显式或自动识别**一台**设备，绝不默认"第一台"是模拟器；
  - 结果目录：<repo>\performance-results\<runId>\<scenario>\*.json|*.csv
#>

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:ResultRoot = Join-Path $script:RepoRoot 'performance-results'

function Get-Tool([string]$ExplicitPath, [string]$Name) {
  if ($ExplicitPath -and (Test-Path $ExplicitPath)) { return $ExplicitPath }
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "找不到 $Name：请用参数指定路径（本机默认：adb=D:\Download\Java\Android\platform-tools\adb.exe，flutter=D:\Download\Flutter\flutter\bin\flutter.bat）"
}

function Write-Step([string]$Msg) { Write-Host ''; Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Note([string]$Msg) { Write-Host "    [!]  $Msg" -ForegroundColor Yellow }
function Fail-Perf([string]$Msg)  { Write-Host ''; Write-Host "[FAIL] $Msg" -ForegroundColor Red; exit 1 }

# 本机默认 JDK：系统 JAVA_HOME 是 JDK 25，这个 Android 工程用 JDK 17 构建（HANDOFF 的发布硬约束）。
# 只影响「本次构建进程」，用完还原，不改系统环境变量。
$script:DefaultJdk17 = 'D:\Download\Java\jdk-17.0.20.1+1'

function Resolve-JdkHome([string]$Explicit) {
  if ($Explicit -and (Test-Path (Join-Path $Explicit 'bin\java.exe'))) { return $Explicit }
  if (Test-Path (Join-Path $script:DefaultJdk17 'bin\java.exe')) { return $script:DefaultJdk17 }
  if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    Write-Note "没找到 JDK 17，退回系统 JAVA_HOME=$env:JAVA_HOME"
    return $env:JAVA_HOME
  }
  throw '找不到可用的 JDK（指定 -JdkHome）'
}

# 在指定 JDK 下执行一段构建；结束后还原 JAVA_HOME。
function Invoke-WithJdk([string]$JdkHome, [scriptblock]$Body) {
  $old = $env:JAVA_HOME
  $env:JAVA_HOME = $JdkHome
  try {
    $javaExe = Join-Path $JdkHome 'bin\java.exe'
    $ver = (& $javaExe -version 2>&1 | Out-String)
    $label = if ($ver -match 'version "([^"]+)"') { $Matches[1] } else { '?' }
    Write-Ok "构建 JDK：$JdkHome（java $label）"
    & $Body
  }
  finally {
    $env:JAVA_HOME = $old
  }
}

function Get-AdbDevices([string]$Adb) {
  $raw = & $Adb devices 2>&1 | Out-String
  $list = @()
  foreach ($line in ($raw -split "`r?`n")) {
    if ($line -match '^(\S+)\s+device(\s|$)') {
      $list += [pscustomobject]@{ Serial = $Matches[1] }
    }
  }
  return $list
}

# 真机优先：serial 不含 ':' 且不以 emulator- 开头
function Select-PerfSerial([string]$Adb, [string]$Explicit) {
  $devices = Get-AdbDevices $Adb
  if ($Explicit) {
    if (-not ($devices | Where-Object { $_.Serial -eq $Explicit })) {
      Fail-Perf "设备 $Explicit 不在线。当前：$(($devices | ForEach-Object { $_.Serial }) -join ', ')"
    }
    return $Explicit
  }
  $physical = $devices | Where-Object { $_.Serial -notmatch ':' -and $_.Serial -notmatch '^emulator-' }
  if ($physical.Count -ge 1) { return $physical[0].Serial }
  if ($devices.Count -ge 1) {
    Write-Note "没找到真机，退回模拟器 $($devices[0].Serial)（模拟器数据不能代表真机性能）"
    return $devices[0].Serial
  }
  Fail-Perf '没有在线设备：先 adb devices 确认'
}

function Invoke-Adb([string]$Adb, [string]$Serial, [string[]]$ArgList) {
  $out = & $Adb -s $Serial @ArgList 2>&1 | Out-String
  return $out
}

function Invoke-AdbShell([string]$Adb, [string]$Serial, [string]$Command) {
  return (Invoke-Adb $Adb $Serial @('shell', $Command))
}

function Get-DeviceInfo([string]$Adb, [string]$Serial) {
  return [ordered]@{
    serial         = $Serial
    model          = (Invoke-AdbShell $Adb $Serial 'getprop ro.product.model').Trim()
    brand          = (Invoke-AdbShell $Adb $Serial 'getprop ro.product.brand').Trim()
    androidVersion = (Invoke-AdbShell $Adb $Serial 'getprop ro.build.version.release').Trim()
    sdk            = (Invoke-AdbShell $Adb $Serial 'getprop ro.build.version.sdk').Trim()
    abi            = (Invoke-AdbShell $Adb $Serial 'getprop ro.product.cpu.abi').Trim()
    wmSize         = (Invoke-AdbShell $Adb $Serial 'wm size').Trim()
    wmDensity      = (Invoke-AdbShell $Adb $Serial 'wm density').Trim()
    soc            = (Invoke-AdbShell $Adb $Serial 'getprop ro.soc.model').Trim()
  }
}

# 屏幕刷新率：取当前 display mode 的刷新率（60 / 120 …）
function Get-RefreshRate([string]$Adb, [string]$Serial) {
  $txt = Invoke-AdbShell $Adb $Serial 'dumpsys display'
  if ($txt -match 'renderFrameRate ([0-9.]+)') { return [double]$Matches[1] }
  return $null
}

function Get-AppInfo([string]$Adb, [string]$Serial, [string]$Package) {
  $txt = Invoke-AdbShell $Adb $Serial "dumpsys package $Package"
  $versionCode = $null
  $versionName = $null
  if ($txt -match 'versionCode=(\d+)') { $versionCode = [int]$Matches[1] }
  if ($txt -match 'versionName=([^\s]+)') { $versionName = $Matches[1] }
  return [ordered]@{ package = $Package; versionCode = $versionCode; versionName = $versionName }
}

# 均值 / 中位数 / P95 / 极值（样本 < 2 时 P95 = 最大值）
function Get-Stats([double[]]$Values) {
  if (-not $Values -or $Values.Count -eq 0) { return $null }
  $sorted = $Values | Sort-Object
  $n = $sorted.Count
  $mean = ($sorted | Measure-Object -Average).Average
  $median = if ($n % 2 -eq 1) { $sorted[[int](($n - 1) / 2)] } else { ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2 }
  $p95Index = [int][math]::Ceiling(0.95 * $n) - 1
  if ($p95Index -lt 0) { $p95Index = 0 }
  return [ordered]@{
    count  = $n
    mean   = [math]::Round($mean, 1)
    median = [math]::Round($median, 1)
    p95    = [math]::Round($sorted[$p95Index], 1)
    min    = [math]::Round($sorted[0], 1)
    max    = [math]::Round($sorted[$n - 1], 1)
  }
}

function New-RunDir([string]$RunId, [string]$Scenario) {
  $dir = Join-Path (Join-Path $script:ResultRoot $RunId) $Scenario
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  return $dir
}

function Write-JsonFile([object]$Data, [string]$Path) {
  $json = $Data | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-CsvFile([object[]]$Rows, [string]$Path) {
  if (-not $Rows -or $Rows.Count -eq 0) { return }
  $Rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Get-Timestamp { return (Get-Date).ToString('yyyyMMdd-HHmmss') }

# 等待某个字符串出现在界面上（用 uiautomator 的 shell 版，避免依赖仓库里的 python）
function Wait-UiText([string]$Adb, [string]$Serial, [string]$Text, [int]$TimeoutSec = 15) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $xml = Invoke-AdbShell $Adb $Serial 'uiautomator dump /sdcard/_perf.xml >/dev/null 2>&1; cat /sdcard/_perf.xml'
    if ($xml -and $xml.Contains($Text)) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return $false
}

# 屏幕坐标（基于 wm size，适配不同分辨率）
function Get-ScreenSize([string]$Adb, [string]$Serial) {
  $txt = Invoke-AdbShell $Adb $Serial 'wm size'
  if ($txt -match '(\d+)x(\d+)') { return [pscustomobject]@{ Width = [int]$Matches[1]; Height = [int]$Matches[2] } }
  Fail-Perf '读不到屏幕尺寸（wm size）'
}
