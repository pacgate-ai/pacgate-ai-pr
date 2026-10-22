import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute("SELECT first_human_message FROM runs WHERE run_id=?", ("f117baa0-bb80-4b43-a26b-f40e01e13667",))
r = cur.fetchone()
msg = r[0] or ""
i = msg.find("<uploaded_files>")
print(msg[i:i + 700])
