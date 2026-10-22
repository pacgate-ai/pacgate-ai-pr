import sys
sys.path.insert(0, '/app/backend')

# 17 summarization-channel writes for our thread, ALL empty. Empty write =
# the middleware node ran and returned None. But we proved should=True and
# cutoff>0 from step 8. CONTRADICTION.
# Resolution: the branch channel 'branch:to:DeerFlowSummarizationMiddleware.before_model'
# is a TASK branch, not the middleware output. The middleware's actual output
# would go to the 'messages' channel via a Command. An empty branch write just
# means the branch task completed.
# The REAL question: did the middleware's returned state get applied?
# If it fired, the messages channel would show a RemoveMessage + summary.
# The last checkpoint has 22 messages and NO summary marker -> it did NOT fire.
# BUT the direct invocation DID fire. The difference: during the live run,
# the middleware runs INSIDE the graph with the REAL runtime.
# Look at the timing: the unlogged LLM calls (01:21:34 etc.) - were they the
# summarizer? If the summarizer fired and SUCCEEDED, state would change.
# If it fired and FAILED (exception), the tool_error middleware might swallow it.
# Check the deer-flow logs for exceptions around those times
print('checking deer-flow logs for summarizer exceptions...')
import subprocess
out = subprocess.run(['docker', 'logs', 'deer-flow'], capture_output=True, text=True)
lines = out.stdout.split('\n') + out.stderr.split('\n')
for i, line in enumerate(lines):
    if 'ummariz' in line.lower():
        print(line[:200])