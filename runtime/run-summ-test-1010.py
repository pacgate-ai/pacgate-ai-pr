import json, urllib.request, urllib.parse, time

BASE = 'http://127.0.0.1:8001'
data = urllib.parse.urlencode({'username': 'todos-test-1010@pacgate-law.com', 'password': 'TestPass123!'}).encode()
req = urllib.request.Request(BASE + '/api/v1/auth/login/local', data=data,
                             headers={'Content-Type': 'application/x-www-form-urlencoded'})
r = urllib.request.urlopen(req, timeout=15)
set_cookies = r.headers.get_all('Set-Cookie') or []
cookie_str = '; '.join(c.split(';')[0] for c in set_cookies)
csrf = None
for c in set_cookies:
    if 'csrf' in c.lower():
        csrf = c.split(';')[0].split('=', 1)[1]
headers = {'Cookie': cookie_str, 'Content-Type': 'application/json'}
if csrf:
    headers['X-CSRF-Token'] = csrf

req = urllib.request.Request(BASE + '/api/threads', data=json.dumps({'assistant_id': 'lead_agent'}).encode(), headers=headers)
r = urllib.request.urlopen(req, timeout=15)
tid = json.load(r)['thread_id']
print('thread:', tid)

# Send a multi-turn conversation to push message tokens past 5000 with cutoff>0
payload = {
    'assistant_id': 'lead_agent',
    'input': {'messages': [{'type': 'human', 'content': [{'type': 'text', 'text': '请详细介绍 pacgate-ai 的 OCR 功能架构，包括 PaddleOCR 的检测、识别、分类三个阶段，以及 ocr-service 容器的部署方式。请尽量详细，至少 2000 字。'}]}]},
    'context': {'model_name': 'deepseek-v4.1-flash-cloud', 'thinking_enabled': False},
    'stream_mode': ['values'],
}
req = urllib.request.Request(BASE + f'/api/threads/{tid}/runs/stream', data=json.dumps(payload).encode(), headers=headers)
t0 = time.time()
r = urllib.request.urlopen(req, timeout=300)
buf = b''
while True:
    chunk = r.read(8192)
    if not chunk:
        break
    buf += chunk
    if b'event: end' in buf:
        break
print('run done in', round(time.time()-t0, 1), 's, stream size:', len(buf))