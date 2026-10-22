import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute("SELECT kwargs_json FROM runs WHERE run_id=?", ("ccbefc4d-2b54-4d7f-ac3c-c72cec409ab4",))
r = cur.fetchone()
k = r[0] or ""
print("has files kwarg:", "files" in k)
print("has uploaded_files:", "uploaded_files" in k)
print("kwargs head:", k[:200])
