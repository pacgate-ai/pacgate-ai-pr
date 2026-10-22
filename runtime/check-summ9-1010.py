import sys
sys.path.insert(0, '/app/backend')

# should=True at EVERY checkpoint but summarization never fired!
# The middleware must be failing silently. Check _determine_cutoff_index and
# _create_summary - maybe cutoff <= 0 or the summary model call fails.
import inspect
from deerflow.agents.middlewares.summarization_middleware import SummarizationMiddleware
print(inspect.getsource(SummarizationMiddleware._determine_cutoff_index))