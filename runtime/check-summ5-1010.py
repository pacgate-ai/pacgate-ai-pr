import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
# Get the FIRST and LAST checkpoint message counts to see growth
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id ASC LIMIT 1", (tid,))
first = cur.fetchone()[0]
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
last = cur.fetchone()[0]
print('first size:', len(first), 'last size:', len(last))
# The input tokens grew 66k->73k over the run. Summarization trigger=5000 message tokens.
# If messages were already >5000 at run start, summarization should have fired on call 1.
# It didn't (0 summary markers). WHY?
# Hypothesis: the trigger counts tokens AFTER the system+tools are excluded, and the
# message-token estimate uses a cheap heuristic that UNDERCOUNTS CJK.
# Check the actual message content language
cur.execute("SELECT value FROM writes WHERE thread_id=? AND channel='messages' ORDER BY rowid DESC LIMIT 1", (tid,))
val = cur.fetchone()[0]
# count CJK vs ASCII in the last message write
cjk = sum(1 for b in val if b > 127)
print('last message write size:', len(val), 'non-ascii bytes:', cjk, f'({100*cjk/len(val):.0f}%)')