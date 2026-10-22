import json, urllib.request, urllib.parse, time

BASE = 'http://127.0.0.1:8001'

# Try each user with delay between attempts
users = [
    ('todos-test-1010@pacgate-law.com', 'TestPass123!'),
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
        time.sleep(2)
if r is None:
    raise SystemExit(1)

set_cookies = r.headers.get_all('Set-Cookie') or []
cookie_str = '; '.join(c.split(';')[0] for c in set_cookies)
csrf = None
for c in set_cookies:
    if 'csrf' in c.lower():
        csrf = c.split(';')[0].split('=', 1)[1]
print('csrf:', csrf)
headers = {'Cookie': cookie_str, 'Content-Type': 'application/json'}
if csrf:
    headers['X-CSRF-Token'] = csrf

# Create a NEW thread and run with is_plan_mode=true to test todos end-to-end
req = urllib.request.Request(BASE + '/api/threads', data=json.dumps({'assistant_id': 'lead_agent'}).encode(),
                             headers=headers)
r = urllib.request.urlopen(req, timeout=15)
thread = json.load(r)
tid = thread['thread_id']
print('new thread:', tid)

# Send a run with is_plan_mode=true
payload = {
    'assistant_id': 'lead_agent',
    'input': {'messages': [{'type': 'human', 'content': [{'type': 'text', 'text': 'Use the write_todos tool to create a 3-item todo list: research X, draft Y, review Z. Then finish.'}]}]},
    'context': {'is_plan_mode': True, 'model_name': 'deepseek-v4.1-flash-cloud', 'thinking_enabled': False},
    'stream_mode': ['values'],
}
req = urllib.request.Request(BASE + f'/api/threads/{tid}/runs/stream',
                             data=json.dumps(payload).encode(),
                             headers=headers)
t0 = time.time()
try:
    r = urllib.request.urlopen(req, timeout=240)
    print('run started', r.status)
    todos_seen = False
    buf = b''
    deadline = time.time() + 220
    while time.time() < deadline:
        chunk = r.read(4096)
        if not chunk:
            break
        buf += chunk
        if b'write_todos' in buf:
            todos_seen = True
            print('WRITE_TODOS SEEN IN STREAM at', round(time.time()-t0, 1), 's')
        if b'event: end' in buf:
            print('stream ended at', round(time.time()-t0, 1), 's')
            break
    m = buf.find(b'"todos"')
    if m >= 0:
        print('todos key in values at offset', m)
        print('todos context:', buf[m:m+400])
    else:
        print('NO todos key in final values')
        print('tail:', buf[-600:])
except Exception as e:
    print('run FAIL:', e, 'elapsed', round(time.time()-t0, 1))