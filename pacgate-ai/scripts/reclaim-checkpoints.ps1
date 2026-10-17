<#
.SYNOPSIS
  Delete stale LangGraph threads (checkpoints + writes) and VACUUM.

.DESCRIPTION
  VACUUM alone reclaims NOTHING here: freelist_count was 0 because the 2.2 GiB is
  live rows, not free pages. 73% of the file belongs to 4 threads idle for weeks
  (thread d9d0fe54 alone = 1.42 GiB). Deletion must therefore come FIRST.

  Deletion is THREAD-ATOMIC across `checkpoints` and `writes`. There is no DB-level
  FK, but app/gateway/checkpoint_lineage.py walks checkpoint_id /
  parent_checkpoint_id, so a row-age deletion would leave dangling lineage.

  A thread with checkpoints but NO threads_meta row cannot be deleted through the
  REST route (require_existing=True) - this script handles it directly.

  Default is REPORT ONLY. Pass -Apply to delete.

.PARAMETER SkipVacuum
  Delete rows but do not VACUUM. Use this while the app is running: VACUUM needs an
  exclusive lock and the app's own AsyncSqliteStore holds reads on the same file.
  Space is then reclaimed by a later -VacuumOnly run with the app stopped.
#>
[CmdletBinding()]
param(
    [int]    $RetainDays = 21,
    [string] $DataDir    = '',
    [switch] $Apply,
    [switch] $SkipVacuum,
    [switch] $VacuumOnly
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is EMPTY during parameter binding under PowerShell 5.1, so a param()
# default of "$PSScriptRoot\..." silently collapses to a relative path. Resolve it here.
if (-not $DataDir) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $DataDir = Join-Path $here '..\deploy\client-bundle\data\deer-flow'
}
$DataDir = (Resolve-Path -LiteralPath $DataDir -ErrorAction Stop).Path

$ckpt = Join-Path $DataDir 'checkpoints.db'
$meta = Join-Path $DataDir 'data\deerflow.db'
if (-not (Test-Path $ckpt)) { throw "checkpoints.db not found at $ckpt" }
if (-not (Test-Path $meta)) { throw "deerflow.db not found at $meta"  }

$python = 'C:\Program Files\Python313\python.exe'
if (-not (Test-Path $python)) { $python = 'python' }

$prog = @'
import os, sqlite3, sys, datetime

ckpt, meta, retain_days = sys.argv[1], sys.argv[2], int(sys.argv[3])
apply_  = sys.argv[4] == "apply"
vacuum  = sys.argv[5] == "vacuum"
del_    = sys.argv[6] == "delete"

def gib(n): return n / 1024**3
def mib(n): return n / 1024**2

size0 = os.path.getsize(ckpt)
c = sqlite3.connect("file:{}".format(ckpt), uri=True)
c.execute("PRAGMA busy_timeout=60000")

if vacuum and not del_:
    print("=== vacuum only ===")
    before = os.path.getsize(ckpt)
    c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    c.execute("VACUUM")
    c.close()
    print("before : {:.3f} GiB".format(gib(before)))
    print("after  : {:.3f} GiB".format(gib(os.path.getsize(ckpt))))
    sys.exit(0)

print("file            : {:.3f} GiB".format(gib(size0)))
print("free pages      : {}".format(c.execute("PRAGMA freelist_count").fetchone()[0]))
print("auto_vacuum     : {}".format(c.execute("PRAGMA auto_vacuum").fetchone()[0]))
print("page_size       : {}".format(c.execute("PRAGMA page_size").fetchone()[0]))
print("journal_mode    : {}".format(c.execute("PRAGMA journal_mode").fetchone()[0]))

m = sqlite3.connect("file:{}?mode=ro".format(meta), uri=True)
cut = m.execute("SELECT date('now', ?)", ("-{} days".format(retain_days),)).fetchone()[0]
meta_rows = {r[0]: (r[1] or "") for r in
             m.execute("SELECT thread_id, substr(COALESCE(updated_at,''),1,10) FROM threads_meta")}

rows   = c.execute("SELECT thread_id, COUNT(*), SUM(LENGTH(checkpoint)) FROM checkpoints GROUP BY thread_id").fetchall()
writes = dict(c.execute("SELECT thread_id, SUM(LENGTH(value)) FROM writes GROUP BY thread_id"))
total  = sum((r[2] or 0) + (writes.get(r[0]) or 0) for r in rows)

stale = []
for tid, n, cb in rows:
    upd = meta_rows.get(tid)
    if upd is None or upd == "" or upd < cut:
        stale.append((tid, n, (cb or 0) + (writes.get(tid) or 0), upd or "(no threads_meta row)"))

stale_bytes = sum(s[2] for s in stale)
print("threads         : {}   total bytes: {:.1f} MiB".format(len(rows), mib(total)))
print("retain cutoff   : {}   (RetainDays={})".format(cut, retain_days))
print("stale threads   : {}   stale bytes: {:.1f} MiB ({:.0f}% of db)".format(
      len(stale), mib(stale_bytes), 100.0 * stale_bytes / total if total else 0))
for tid, n, b, upd in sorted(stale, key=lambda s: -s[2])[:12]:
    print("  {:20}  n={:5d}  {:8.1f} MiB  updated={}".format(tid[:20], n, mib(b), upd))

if not apply_:
    print("")
    print("(report only - pass -Apply to delete)")
    sys.exit(0)

ids = [s[0] for s in stale]
if not ids:
    print("")
    print("nothing to delete")
    sys.exit(0)

with c:
    for i in range(0, len(ids), 200):
        chunk = ids[i:i + 200]
        q = ",".join("?" * len(chunk))
        c.execute("DELETE FROM writes WHERE thread_id IN ({})".format(q), chunk)
        c.execute("DELETE FROM checkpoints WHERE thread_id IN ({})".format(q), chunk)

free = c.execute("PRAGMA freelist_count").fetchone()[0]
print("")
print("deleted {} threads; freelist now {}".format(len(ids), free))
print("file (pre-vacuum): {:.3f} GiB".format(gib(os.path.getsize(ckpt))))
c.close()

if vacuum:
    c = sqlite3.connect("file:{}".format(ckpt), uri=True, isolation_level=None)
    c.execute("PRAGMA busy_timeout=120000")
    c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    c.execute("VACUUM")
    c.close()
    print("after VACUUM    : {:.3f} GiB".format(gib(os.path.getsize(ckpt))))
else:
    print("(VACUUM skipped - run with -VacuumOnly while deer-flow is stopped to reclaim)")
'@

$tmp = Join-Path $env:TEMP 'reclaim-checkpoints.py'
[System.IO.File]::WriteAllText($tmp, $prog, (New-Object System.Text.UTF8Encoding($false)))
try {
    $args = @($tmp, $ckpt, $meta, $RetainDays)
    if ($VacuumOnly) {
        $args += @('apply', 'vacuum', 'no-delete')
    } elseif ($Apply) {
        $args += @('apply', ($(if ($SkipVacuum) { 'no-vacuum' } else { 'vacuum' })), 'delete')
    } else {
        $args += @('report', 'no-vacuum', 'no-delete')
    }
    & $python @args
    if ($LASTEXITCODE -ne 0) { throw "reclaim python exited $LASTEXITCODE" }
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
