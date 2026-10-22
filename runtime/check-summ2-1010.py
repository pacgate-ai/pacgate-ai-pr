import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
# The summarization middleware branch exists. Check what it wrote - did it ever trigger?
cur.execute("SELECT checkpoint_id, value FROM writes WHERE thread_id=? AND channel LIKE '%ummariz%' ORDER BY rowid DESC LIMIT 5", (tid,))
for cp, val in cur.fetchall():
    print(cp, 'value size:', len(val) if val else 0)
    if val:
        # look for should=True / summary markers
        print('  has b"should":', b'should' in val, '| has b"summary":', b'summary' in val[:2000])
        print('  head:', val[:200])