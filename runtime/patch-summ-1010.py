import re

PATH = '/app/backend/packages/harness/deerflow/agents/middlewares/summarization_middleware.py'
with open(PATH, 'r', encoding='utf-8') as f:
    src = f.read()

# Add debug logging to _amaybe_summarize decision points
old = """    async def _amaybe_summarize(self, state: AgentState, runtime: Runtime) -> dict | None:
        messages = state["messages"]
        self._ensure_message_ids(messages)

        total_tokens = self.token_counter(messages)
        if not self._should_summarize(messages, total_tokens):
            return None

        cutoff_index = self._determine_cutoff_index(messages)
        if cutoff_index <= 0:
            return None
"""
new = """    async def _amaybe_summarize(self, state: AgentState, runtime: Runtime) -> dict | None:
        messages = state["messages"]
        self._ensure_message_ids(messages)

        total_tokens = self.token_counter(messages)
        logger.info("SUMM-DEBUG: msgs=%d tokens=%d should=%s", len(messages), total_tokens, self._should_summarize(messages, total_tokens))
        if not self._should_summarize(messages, total_tokens):
            return None

        cutoff_index = self._determine_cutoff_index(messages)
        logger.info("SUMM-DEBUG: cutoff=%d", cutoff_index)
        if cutoff_index <= 0:
            return None
"""
assert old in src, 'pattern not found'
src = src.replace(old, new)

# Also log after summary creation
old2 = """        summary = await self._acreate_summary(messages_to_summarize)
        new_messages = self._build_new_messages(summary)
"""
new2 = """        summary = await self._acreate_summary(messages_to_summarize)
        logger.info("SUMM-DEBUG: summary_len=%s", len(summary) if summary else 0)
        new_messages = self._build_new_messages(summary)
"""
assert old2 in src, 'pattern2 not found'
src = src.replace(old2, new2)

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(src)
print('patched OK')