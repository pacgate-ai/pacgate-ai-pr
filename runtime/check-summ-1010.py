import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT COUNT(*) FROM checkpoints WHERE thread_id=? AND checkpoint LIKE '%summary%'", (tid,))
print('checkpoints with summary marker:', cur.fetchone()[0])
cur.execute("SELECT COUNT(*) FROM checkpoints WHERE thread_id=?", (tid,))
print('total checkpoints:', cur.fetchone()[0])
# check for the summarization middleware channel
cur.execute("SELECT DISTINCT channel FROM writes WHERE thread_id=? AND channel LIKE '%ummariz%'", (tid,))
print('summarization channels:', [r[0] for r in cur.fetchall()])