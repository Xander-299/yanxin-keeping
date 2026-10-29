#Requires -Version 5.1
<#
.SYNOPSIS
  包体积：出 profile / release APK，记录文件大小（含 ABI 拆分），可选对比安装占用。

.DESCRIPTION
  区分三件事（报告里也要分开写）：
    - APK 文件大小   = 下载/分发大小
    - 安装后占用     = `pm path` 后的目录大小（解压 + odex，通常比 APK 大）
    - 运行时内存     = 另一个指标（见 Measure-MemoryCpu.ps1）
  构建沿用 `tool/install_device.ps1` 的做法：临时改 gradle.properties（内存 + qaAppId），
  **无论成败按字节还原**。

.EXAMPLE
  .\scripts\performance\Measure-ApkSize.ps1 -Modes profile,release
#>
param(
  [string]$Serial = '',
  [ValidateSet('profile', 'release', 'debug')]
  [string[]]$Modes = @('profile', 'release'),
  [string]$QaAppId = 'com.teacodeman.yanxin.qa',
  [switch]$Arm64Only,
  [string]$RunId = '',
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe',
  [string]$Flutter = 'D:\Download\Flutter\flutter\bin\flutter.bat',
  [string]$JdkHome = ''            # 空 = 自动找 D:\Download\Java\jdk-17.0.20.1+1
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$flutter = Get-Tool $Flutter 'flutter'
$runId = if ($RunId) { $RunId } else { Get-Timestamp }
$dir = New-RunDir $runId 'apk-size'

# ⚠️ 本机系统 JAVA_HOME 是 JDK 25，但这个 Android 工程按 HANDOFF 用 JDK 17 构建。
#    只改本次进程的 JAVA_HOME，退出时还原。
$jdk = Resolve-JdkHome $JdkHome
$oldJavaHome = $env:JAVA_HOME
$env:JAVA_HOME = $jdk
Write-Ok "构建 JDK：$jdk"

$gradleProps = Join-Path $script:RepoRoot 'android\gradle.properties'
$origBytes = [IO.File]::ReadAllBytes($gradleProps)
$patched = $false
$rows = @()

try {
  $text = [IO.File]::ReadAllText($gradleProps)
  $new = $text.Replace('-Xmx8G -XX:MaxMetaspaceSize=4G', '-Xmx3G -XX:MaxMetaspaceSize=1G')
  if ($QaAppId -and $new -notmatch '(?m)^qaAppId=') { $new = $new.TrimEnd() + "`nqaAppId=$QaAppId`n" }
  if ($new -ne $text) {
    [IO.File]::WriteAllText($gradleProps, $new, (New-Object System.Text.UTF8Encoding($false)))
    $patched = $true
    Write-Note '临改 gradle.properties（内存 3G + qaAppId），完成后按字节还原'
  }

  foreach ($mode in $Modes) {
    Write-Step "构建 $mode"
    $buildArgs = @('build', 'apk', "--$mode", '--no-pub')
    if ($Arm64Only) { $buildArgs += @('--target-platform', 'android-arm64') }
    $start = Get-Date
    & $flutter @buildArgs 2>&1 | ForEach-Object {
      $line = "$_"
      if ($line -and $line -ne 'System.Management.Automation.RemoteException') { Write-Host "    $line" }
    }

    $apkDir = Join-Path $script:RepoRoot 'build\app\outputs\flutter-apk'
    $apks = Get-ChildItem $apkDir -Filter '*.apk' | Where-Object { $_.LastWriteTime -ge $start.AddSeconds(-5) }
    if (-not $apks) { Write-Note "$mode 没产出新 APK（构建失败？看上面日志）"; continue }
    foreach ($apk in $apks) {
      $rows += [pscustomobject]@{
        mode = $mode
        file = $apk.Name
        bytes = $apk.Length
        mb = [math]::Round($apk.Length / 1MB, 2)
        builtAt = $apk.LastWriteTime.ToString('o')
      }
      Write-Ok ("{0} {1:N2} MB（{2}）" -f $apk.Name, ($apk.Length / 1MB), $apk.LastWriteTime.ToString('HH:mm:ss'))
    }
  }
}
finally {
  if ($patched) {
    [IO.File]::WriteAllBytes($gradleProps, $origBytes)
    $same = [Convert]::ToBase64String([IO.File]::ReadAllBytes($gradleProps)) -eq [Convert]::ToBase64String($origBytes)
    if ($same) { Write-Ok 'android/gradle.properties 已按字节还原' } else { Write-Note 'gradle.properties 还原不一致，请 git checkout' }
  }
  $env:JAVA_HOME = $oldJavaHome
}

# 已安装包的占用（可选）：只在设备在线且包存在时测
$installed = $null
try {
  $Serial = if ($Serial) { $Serial } else { Select-PerfSerial $adb '' }
  $pathOut = Invoke-AdbShell $adb $Serial "pm path $QaAppId"
  if ($pathOut -match 'package:(.+)') {
    $apkPath = $Matches[1].Trim()
    $duOut = Invoke-AdbShell $adb $Serial "du -sk $apkPath"
    if ($duOut -match '(\d+)') {
      $installed = [ordered]@{
        package = $QaAppId
        apkOnDeviceKb = [int]$Matches[1]
        apkOnDeviceMb = [math]::Round([int]$Matches[1] / 1024, 2)
        note = 'du -sk 的是已装 APK 本体；完整安装占用还含解压后的 native libs 与 odex'
      }
      Write-Ok ("设备上 $QaAppId 的 APK 本体 {0} MB" -f $installed.apkOnDeviceMb)
    }
  }
} catch {
  Write-Note "跳过安装占用：$($_.Exception.Message)"
}

Write-CsvFile $rows (Join-Path $dir 'apk-size.csv')
Write-JsonFile ([ordered]@{
  scenario = 'apk-size'; runId = $runId; generatedAt = (Get-Date).ToString('o'); jdk = $jdk
  modes = $Modes; arm64Only = [bool]$Arm64Only; qaAppId = $QaAppId
  apks = $rows; installed = $installed
  caveat = 'release 若缺 android/key.properties 会退化成 debug 签名（不影响体积，但不能覆盖正式包）'
}) (Join-Path $dir 'apk-size.json')

Write-Host ''
Write-Host "结果目录：$dir"
