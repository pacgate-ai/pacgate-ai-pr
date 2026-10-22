import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute(
    "SELECT run_id, status, model_name, error, created_at, updated_at FROM runs "
    "WHERE created_at > '2026-10-10 08:00' ORDER BY created_at"
)
for r in cur.fetchall():
    rid, status, model, err, created, updated = r
    print(rid[:8], status, model, "| err:", (err or "")[:60], "|", created[:19], "->", (updated or "")[11:19])
