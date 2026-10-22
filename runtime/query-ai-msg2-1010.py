import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute("SELECT first_human_message FROM runs WHERE run_id LIKE '65f9a41d%'")
row = cur.fetchone()
print((row[0] or "")[:400] if row else "none")
print("----")
# also check the 09:15 run's uploads
cur.execute("SELECT kwargs_json FROM runs WHERE run_id LIKE '65f9a41d%'")
row2 = cur.fetchone()
print((row2[0] or "")[:300] if row2 else "none")
