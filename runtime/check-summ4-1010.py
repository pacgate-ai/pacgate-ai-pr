import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]
# Dump the region around DeerFlowSummarization to see the middleware state
idx = blob.find(b'DeerFlowSummarization')
print(blob[idx-200:idx+400])