"""Checkpoint DB: reclaimable space + what a retention policy would free."""
import os
import sqlite3

db = "/app/backend/.deer-flow/checkpoints.db"
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
cur = con.cursor()

for p in ("page_size", "page_count", "freelist_count", "journal_mode", "auto_vacuum", "wal_autocheckpoint"):
    try:
        print(f"PRAGMA {p:20} = {cur.execute(f'PRAGMA {p}').fetchone()[0]}")
    except Exception as e:  # noqa: BLE001
        print(f"PRAGMA {p:20} ! {e}")

ps = cur.execute("PRAGMA page_size").fetchone()[0]
pc = cur.execute("PRAGMA page_count").fetchone()[0]
fl = cur.execute("PRAGMA freelist_count").fetchone()[0]
print(f"\nfile = {ps*pc/1024**3:.3f} GiB   free = {ps*fl/1024**2:.1f} MiB  "
      f"({100*fl/pc:.1f}% reclaimable by VACUUM)")

print("\n--- per-thread bytes (all) ---")
rows = cur.execute(
    "SELECT thread_id, COUNT(*), SUM(LENGTH(checkpoint)), MIN(LENGTH(checkpoint)), MAX(LENGTH(checkpoint)) "
    "FROM checkpoints GROUP BY thread_id ORDER BY SUM(LENGTH(checkpoint)) DESC"
).fetchall()
tot = sum(r[2] or 0 for r in rows)
print(f"threads={len(rows)} totalCheckpointBytes={tot/1024**2:.1f} MiB")
for tid, n, b, mn, mx in rows[:8]:
    print(f"  {str(tid)[:36]:38} n={n:5d} MB={(b or 0)/1024**2:8.1f} avg={(b or 0)/n/1024:7.1f} KiB max={(mx or 0)/1024:7.1f} KiB")
big = rows[0]
print(f"\nTOP thread share = {100*(big[2] or 0)/tot:.1f}%  ({big[2]/1024**2:.1f} MiB of {tot/1024**2:.1f} MiB)")

print("\n--- writes table ---")
w = cur.execute("SELECT COUNT(*), SUM(LENGTH(value)) FROM writes").fetchone()
print(f"  rows={w[0]} totalMB={(w[1] or 0)/1024**2:.1f}")

print("\n--- top 3 threads in the app's thread table (are they still live?) ---")
try:
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    print("  tables:", [r[0] for r in cur.fetchall()])
except Exception as e:  # noqa: BLE001
    print("  ", e)

con.close()

# is the big thread referenced by the app db?
appdb = "/app/backend/.deer-flow/data/deerflow.db"
if os.path.exists(appdb) and os.path.getsize(appdb) > 0:
    c2 = sqlite3.connect(f"file:{appdb}?mode=ro", uri=True)
    for t in ("threads", "runs"):
        try:
            n = c2.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            print(f"\napp db {t}: {n} rows")
        except Exception as e:  # noqa: BLE001
            print(f"\napp db {t}: {e}")
    c2.close()
else:
    print("\napp db empty/absent at", appdb)
