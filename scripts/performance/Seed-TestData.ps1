#Requires -Version 5.1
<#
.SYNOPSIS
  给 **QA 包** 灌测试流水（只用于性能测试，绝不碰正式包）。

.DESCRIPTION
  为什么需要：空账本下「列表滚动 / 搜索 / 统计」没有代表性。

  怎么做（本机实测：Android 14 上 `run-as ... sqlite3` 会 `Permission denied`，所以不走设备端 sqlite）：
    1) force-stop（避免 drift 的 WAL 写丢）
    2) `adb exec-out cat` 把库拉到本机（用 cmd 的 `>` 才不会被 PowerShell 改成 UTF-16）
    3) 本机 Python 直接 INSERT（schema 见 lib/core/db/tables.dart）
    4) 用 stdin 把库推回应用私有目录（`run-as pkg sh -c 'cat > …'`），并清掉 -wal/-shm

  安全闸：
    - 包名等于正式包（com.teacodeman.yanxin）时**直接拒绝**，除非显式 -Force；
    - 只 INSERT，不 DELETE / UPDATE 既有数据；
    - 全程在 QA 包上操作，删包即全清。

.EXAMPLE
  .\scripts\performance\Seed-TestData.ps1 -Count 600
#>
param(
  [string]$Serial = '',
  [string]$Package = 'com.teacodeman.yanxin.qa',
  [int]$Count = 600,
  [int]$Months = 6,
  [switch]$Force,
  [string]$Adb = 'D:\Download\Java\Android\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'PerfCommon.ps1')

$adb = Get-Tool $Adb 'adb'
$Serial = Select-PerfSerial $adb $Serial

if ($Package -eq 'com.teacodeman.yanxin' -and -not $Force) {
  Fail-Perf '这是用户的正式包（带真实账本），默认拒绝写数据；确实要写请加 -Force（不建议）'
}

Write-Step "灌数据：$Package × $Count 条"
$probe = Invoke-AdbShell $adb $Serial "run-as $Package id"
if ($probe -notmatch 'uid=') {
  Fail-Perf "$Package 不是 debuggable 包（run-as 不可用）→ 先装 debug 包再灌"
}
Write-Ok 'run-as 可用（debug 包）'

$dbRel = 'app_flutter/yanxin.sqlite'
$localDb = Join-Path $env:TEMP 'yanxin-perf.db'
Remove-Item $localDb -ErrorAction SilentlyContinue

Write-Step '1/4 停止应用并拉取数据库'
Invoke-AdbShell $adb $Serial "am force-stop $Package" | Out-Null
Start-Sleep -Milliseconds 800
$cmdLine = '"' + $adb + '" -s ' + $Serial + ' exec-out run-as ' + $Package + ' cat ' + $dbRel + ' > "' + $localDb + '"'
cmd /c $cmdLine
if (-not (Test-Path $localDb) -or (Get-Item $localDb).Length -lt 4096) {
  Fail-Perf "拉库失败（$localDb）：确认包名正确、且 App 至少启动过一次"
}
Write-Ok ("拉到本机 {0:N0} 字节" -f (Get-Item $localDb).Length)

Write-Step '2/4 本机 INSERT（Python + sqlite3）'
$py = @'
import datetime, random, sqlite3, sys, uuid
db, count, months = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
con = sqlite3.connect(db)
cur = con.cursor()
book = cur.execute("select id from books where deleted_at is null limit 1").fetchone()
acc = cur.execute("select id from accounts where deleted_at is null limit 1").fetchone()
if not book or not acc:
    print("EMPTY: 库里没有账本/账户，先启动一次 App"); sys.exit(2)
cats = cur.execute("select id, kind from categories where deleted_at is null and is_archived = 0").fetchall()
exp = [c for c, k in cats if k == "expense"]
inc = [c for c, k in cats if k == "income"]
if not exp or not inc:
    print("EMPTY: 分类表为空"); sys.exit(2)
before = cur.execute("select count(*) from transactions").fetchone()[0]
rnd = random.Random(42)
now = datetime.datetime.now()
rows = []
for i in range(count):
    d = now - datetime.timedelta(days=rnd.randint(0, months * 30), hours=rnd.randint(0, 14), minutes=rnd.randint(0, 59))
    ms = int(d.timestamp() * 1000)
    income = rnd.random() < 0.12
    cat = rnd.choice(inc if income else exp)
    amount = rnd.randint(2000, 30000) if income else rnd.randint(300, 40000)
    rows.append((
        "perf-" + uuid.uuid4().hex, book[0], acc[0], cat,
        "income" if income else "expense", amount, "perf-seed-%d" % i,
        ms, "manual", ms, ms, 1,
    ))
cur.executemany(
    "insert or ignore into transactions "
    "(id, book_id, account_id, category_id, type, amount_cents, note, occurred_at, source, created_at, updated_at, dirty) "
    "values (?,?,?,?,?,?,?,?,?,?,?,?)", rows)
con.commit()
after = cur.execute("select count(*) from transactions").fetchone()[0]
print("COUNT %d -> %d" % (before, after))
con.close()
'@
$pyPath = Join-Path $env:TEMP 'yanxin_perf_seed.py'
[IO.File]::WriteAllText($pyPath, $py, (New-Object System.Text.UTF8Encoding($false)))
$out = & python $pyPath $localDb $Count $Months 2>&1 | Out-String
Write-Host "    $($out.Trim())"
if ($out -match 'EMPTY') { Fail-Perf '库是空的：先启动一次 App（让它建账本/账户/预置分类）再灌' }
if ($out -notmatch 'COUNT (\d+) -> (\d+)') { Fail-Perf "灌数失败：$out" }

Write-Step '3/4 推回设备（stdin 直写，避开 /sdcard 权限）'
Invoke-AdbShell $adb $Serial "run-as $Package rm -f $dbRel-wal $dbRel-shm" | Out-Null
$pushCmd = '"' + $adb + '" -s ' + $Serial + ' shell run-as ' + $Package + ' sh -c "cat > ' + $dbRel + '"'
cmd /c ("type ""$localDb"" | " + $pushCmd)
if ($LASTEXITCODE -ne 0) { Fail-Perf '推回失败' }

Write-Step '4/4 校验并拉起'
$check = & python -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);print(c.execute('select count(*) from transactions').fetchone()[0])" $localDb 2>&1
Write-Ok "本机库内共 $($check.ToString().Trim()) 条流水"
Invoke-AdbShell $adb $Serial "monkey -p $Package -c android.intent.category.LAUNCHER 1" | Out-Null
Start-Sleep -Seconds 5
Write-Ok '已重新拉起 App（进首页看得到数据即可）'
