import sqlite3, json

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()

# Find the tools list in a checkpoint blob - check what tools were bound
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]

# Find tool names in the blob
import re
# Look for common tool name patterns
for tool in [b'write_todos', b'task', b'web_search', b'firecrawl', b'view_image', b'execute_code']:
    idx = blob.find(tool)
    print(f'{tool.decode()}: {"FOUND at " + str(idx) if idx >= 0 else "not in blob"}')

# The tools are bound at agent creation, not stored per-checkpoint. Check the first checkpoint
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id ASC LIMIT 1", (tid,))
first_blob = cur.fetchone()[0]
print('\nfirst checkpoint size:', len(first_blob))
for tool in [b'write_todos', b'pacgate_pacgate_read_document']:
    idx = first_blob.find(tool)
    print(f'{tool.decode()}: {"FOUND at " + str(idx) if idx >= 0 else "not in first blob"}')