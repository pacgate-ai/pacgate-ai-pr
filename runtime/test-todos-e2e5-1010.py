# Check the FINAL values (not just tool calls) - did todos land in thread.values?
import json, urllib.request, urllib.parse

BASE = 'http://127.0.0.1:8001'
data = urllib.parse.urlencode({'username': 'todos-test-1010@pacgate-law.com', 'password': 'TestPass123!'}).encode()
req = urllib.request.Request(BASE + '/api/v1/auth/login/local', data=data,
                             headers={'Content-Type': 'application/x-www-form-urlencoded'})
r = urllib.request.urlopen(req, timeout=15)
set_cookies = r.headers.get_all('Set-Cookie') or []
cookie_str = '; '.join(c.split(';')[0] for c in set_cookies)

tid = '5932a7b6-7c8e-47d9-b324-4e248d35a385'
req = urllib.request.Request(BASE + f'/api/threads/{tid}', headers={'Cookie': cookie_str})
r = urllib.request.urlopen(req, timeout=15)
thread = json.load(r)
values = thread.get('values', {})
print('values keys:', list(values.keys()) if isinstance(values, dict) else type(values))
print('todos in values:', values.get('todos') if isinstance(values, dict) else None)