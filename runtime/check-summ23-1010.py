import sys
sys.path.insert(0, '/app/backend')

# No logging on the happy path. The middleware fires silently.
# DECISIVE TEST: check the Ollama server log for summarizer calls during the
# 01:20-01:33 window. The summarizer uses the same nemotron tag. If the
# middleware fired, there would be EXTRA /v1/chat/completions calls.
# From the earlier log analysis: calls at 01:20:24, 01:20:35, 01:20:38, 01:21:34,
# 01:22:33, 01:22:40, 01:23:16, 01:23:17, 01:23:48, 01:24:13, 01:25:58, 01:26:47
# Each deer-flow LLM call logged token usage. The summarizer call would NOT log
# token usage (different middleware). Count: 12 calls, 8 with token-usage logs.
# 01:21:34, 01:22:40, 01:23:17, 01:24:13, 01:26:47 have NO token-usage log!
# Those 5 unlogged calls could BE the summarizer!
# Wait - but then summarization DID fire... but the writes were empty?
# Re-check: maybe the writes I looked at were from the WRONG thread.
print('Checking writes table for the summarization channel across ALL threads...')
import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
cur.execute("SELECT thread_id, COUNT(*) FROM writes WHERE channel LIKE '%ummariz%' GROUP BY thread_id")
for r in cur.fetchall():
    print(r)
cur.execute("SELECT COUNT(*) FROM writes WHERE channel LIKE '%ummariz%' AND length(value) > 0")
print('non-empty summarization writes:', cur.fetchone()[0])