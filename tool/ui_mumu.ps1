# 模拟器 UI 辅助（MuMu / adb）：dump 语义树 → 列出可点节点 → 按文案点中心点。
# 为什么先落文本文件：控制台是 GBK，中文会糊；写 UTF-8 文件后用 read 工具看才准。
param(
  [ValidateSet('dump', 'tap', 'screen')]
  [string]$Action = 'dump',
  [string]$Match = '',
  [string]$Serial = '127.0.0.1:16384',
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe',
  [string]$Out = 'D:\yanxin-llm-bench\ui.txt'
)

function Get-UiXml {
  # ⚠️ dump 会偶发失败（"null root node"），失败时**不能**读上一轮的旧文件 —— 否则会拿着
  # 上一次的界面当"当前状态"做判断（本轮实测踩到过）。所以：先删本地与设备上的旧文件，
  # dump 后校验设备上文件确实存在、且尺寸变了，最多重试 3 次。
  $local = 'D:\yanxin-llm-bench\ui.xml'
  if (Test-Path $local) { Remove-Item $local -Force }
  for ($i = 1; $i -le 3; $i++) {
    & $Adb -s $Serial shell 'rm -f /sdcard/ui.xml; uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; test -s /sdcard/ui.xml && echo OK' 2>&1 | Out-Null
    & $Adb -s $Serial pull /sdcard/ui.xml $local 2>&1 | Out-Null
    if (Test-Path $local) {
      $raw = [System.IO.File]::ReadAllText($local, [System.Text.Encoding]::UTF8)
      if ($raw.Length -gt 200) { return [xml]$raw }
    }
    Start-Sleep -Milliseconds 800
  }
  throw "uiautomator dump 连续失败（界面可能还在动 / 无障碍服务没起来）"
}

function Get-Nodes($xml) {
  $xml.SelectNodes('//node') | ForEach-Object {
    $t = $_.text
    if (-not $t) { $t = $_.'content-desc' }
    if (-not $t) { return }
    [pscustomobject]@{
      Text = $t
      Bounds = $_.bounds
      Clickable = $_.clickable
      Class = $_.class
      B = ($_.bounds -replace '[\[\]]', '')
    }
  }
}

switch ($Action) {
  'dump' {
    $xml = Get-UiXml
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 前台节点（text 或 content-desc 非空）")
    foreach ($n in (Get-Nodes $xml)) {
      $lines.Add(("{0}  |  {1}  |  clickable={2}" -f $n.Text, $n.Bounds, $n.Clickable))
    }
    [System.IO.File]::WriteAllLines($Out, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "写出 $($lines.Count - 1) 个节点 → $Out"
  }
  'tap' {
    $xml = Get-UiXml
    $hit = Get-Nodes $xml | Where-Object { $_.Text -eq $Match } | Select-Object -First 1
    if (-not $hit) { $hit = Get-Nodes $xml | Where-Object { $_.Text -like "*$Match*" } | Select-Object -First 1 }
    if (-not $hit) { Write-Host "!! 没找到：$Match"; exit 1 }
    # bounds 形如 "[791,60][876,122]" → 只抓数字，别按逗号/方括号硬切（切出来会混进 "60][876"）
    $nums = [regex]::Matches($hit.Bounds, '\d+') | ForEach-Object { [int]$_.Value }
    $cx = [int](($nums[0] + $nums[2]) / 2)
    $cy = [int](($nums[1] + $nums[3]) / 2)
    Write-Host ("tap '{0}' @ ({1},{2})  {3}" -f $hit.Text, $cx, $cy, $hit.Bounds)
    & $Adb -s $Serial shell "input tap $cx $cy" | Out-Null
  }
  'screen' {
    & $Adb -s $Serial shell 'screencap -p /sdcard/s.png' 2>&1 | Out-Null
    & $Adb -s $Serial pull /sdcard/s.png 'D:\yanxin-llm-bench\screen.png' 2>&1 | Out-Null
    Write-Host 'screenshot → D:\yanxin-llm-bench\screen.png'
  }
}
