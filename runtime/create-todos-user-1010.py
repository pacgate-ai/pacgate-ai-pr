# Create a fresh test user in-process (bypasses login rate limit)
import sys
sys.path.insert(0, '/app/backend')

import asyncio
from deerflow.config import get_app_config
from deerflow.persistence.engine import init_engine_from_config
from app.gateway.deps import get_local_provider

cfg = get_app_config()
email = 'todos-test-1010@pacgate-law.com'

async def main():
    await init_engine_from_config(cfg.database)
    provider = get_local_provider()
    try:
        user = await provider.create_user(email=email, password='TestPass123!')
        print('created user:', email, user.id)
    except Exception as e:
        print('create failed (may exist):', e)

asyncio.run(main())