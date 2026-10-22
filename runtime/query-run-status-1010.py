import sqlite3
import sys

rid = sys.argv[1]
conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute("SELECT status, error, total_tokens, last_ai_message FROM runs WHERE run_id=?", (rid,))
r = cur.fetchone()
if r:
    print(f"status: {r[0]} | err: {(r[1] or '')[:60]} | tokens: {r[2]}")
    print(f"ai: {(r[3] or '')[:120]}")
else:
    print("run not found")
