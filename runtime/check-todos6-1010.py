import json, urllib.request, urllib.parse, time

BASE = 'http://127.0.0.1:8001'

# Login as debug user
users = [
    ('pwtest@pacgate-law.com', 'TestPass123!'),
    ('debug-1008@pacgate-law.com', 'TestPass123!'),
    ('e2e-pdf-1009@pacgate-law.com', 'TestPass123!'),
]
r = None
for email, pw in users:
    data = urllib.parse.urlencode({'username': email, 'password': pw}).encode()
    req = urllib.request.Request(BASE + '/api/v1/auth/login/local', data=data,
                                 headers={'Content-Type': 'application/x-www-form-urlencoded'})
    try:
        r = urllib.request.urlopen(req, timeout=15)
        print('login OK', email, r.status)
        break
    except Exception as e:
        print('login FAIL:', email, e)
if r is None:
    raise SystemExit(1)

# Extract cookies
from http.cookiejar import CookieJar
import re
set_cookies = r.headers.get_all('Set-Cookie') or []
cookie_str = '; '.join(c.split(';')[0] for c in set_cookies)
print('cookies:', cookie_str[:120])

# Get csrf token
csrf = None
for c in set_cookies:
    if c.startswith('csrf'):
        csrf = c.split(';')[0].split('=', 1)[1]
print('csrf:', csrf)

# Fetch the recent thread's values
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
req = urllib.request.Request(BASE + f'/api/threads/{tid}', headers={'Cookie': cookie_str})
r = urllib.request.urlopen(req, timeout=15)
thread = json.load(r)
values = thread.get('values', {})
print('\nthread values keys:', list(values.keys()) if isinstance(values, dict) else type(values))
if isinstance(values, dict):
    print('todos:', values.get('todos'))
    print('title:', values.get('title'))

# Check the run request context - what mode was used
req = urllib.request.Request(BASE + f'/api/threads/{tid}/runs?limit=5&offset=0', headers={'Cookie': cookie_str})
r = urllib.request.urlopen(req, timeout=15)
runs = json.load(r)
for run in runs if isinstance(runs, list) else runs.get('runs', []):
    print('\nrun:', run.get('run_id'))
    print('  context:', json.dumps(run.get('context', {}), ensure_ascii=False)[:400])
    print('  metadata:', json.dumps(run.get('metadata', {}), ensure_ascii=False)[:400])