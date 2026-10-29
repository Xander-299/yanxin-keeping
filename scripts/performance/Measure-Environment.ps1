#Requires -Version 5.1
<#
.SYNOPSIS
  采集性能测试环境：工具链、设备、应用信息（不动设备数据）。

.EXAMPLE
  .\scripts\performance\Measure-Environment.ps1
  .\scripts\performance\Measure-Environment.ps1 -Serial MRN7ONWCUSHYG65D -Package com.teacodeman.yanxin.qa
#>
param(
  [string]$Serial = '',
  [string]$Package = 'com.teacodeman.yanxin.qa',
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe',
  [string]$Flutter = 'D:\Download\Flutter\flutter\bin\flutter.bat',
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$flutter = Get-Tool $Flutter 'flutter'
$Serial = Select-PerfSerial $adb $Serial
$runId = if ($OutDir) { $OutDir } else { Get-Timestamp }
$dir = New-RunDir $runId 'environment'

Write-Step '工具链'
$flutterVersion = (& $flutter --version 2>&1 | Out-String).Trim()
$dartVersion = (& (Join-Path (Split-Path $flutter) 'dart.bat') --version 2>&1 | Out-String).Trim()
$javaHome = $env:JAVA_HOME
$javaVersion = ''
if (Test-Path (Join-Path $javaHome 'bin\java.exe')) {
  $javaVersion = (& (Join-Path $javaHome 'bin\java.exe') -version 2>&1 | Out-String).Trim()
}
Write-Ok "flutter: $flutter"
Write-Ok "adb: $adb"
Write-Ok "JAVA_HOME: $javaHome"
if ($javaVersion -match 'version "([^"]+)"') { Write-Ok "java: $($Matches[1])" }

Write-Step "设备 $Serial"
$device = Get-DeviceInfo $adb $Serial
$refresh = Get-RefreshRate $adb $Serial
$device['refreshRate'] = $refresh
foreach ($k in $device.Keys) { Write-Host ("    {0,-14} {1}" -f $k, $device[$k]) }

Write-Step "应用 $Package"
$app = Get-AppInfo $adb $Serial $Package
if ($null -eq $app.versionCode) {
  Write-Note "$Package 未安装（后续测试前先装包）"
} else {
  Write-Ok "versionCode=$($app.versionCode) versionName=$($app.versionName)"
}

$envInfo = [ordered]@{
  generatedAt   = (Get-Date).ToString('o')
  toolchain     = [ordered]@{
    flutterPath  = $flutter
    flutterVersion = ($flutterVersion -split "`n")[0]
    dartVersion  = $dartVersion
    javaHome     = $javaHome
    javaVersion  = $javaVersion
    adbPath      = $adb
    androidHome  = $env:ANDROID_HOME
  }
  device        = $device
  app           = $app
}
Write-JsonFile $envInfo (Join-Path $dir 'environment.json')
Write-Ok "写出 $(Join-Path $dir 'environment.json')"
