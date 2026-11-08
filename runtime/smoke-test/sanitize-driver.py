import json, os, sys, time, httpx
sys.path.insert(0, '/app')
import server

IDS = ['c2d70539-68f0-4a0e-b20d-d11e59f17eae','7af51ed6-661b-4720-b0a7-6d20f2434e43','2b8be40f-96e7-472f-bad8-11e54263c26d','da8f79cb-5e8b-4e94-aa09-768ea137be56','a912677d-2ccf-41c1-be66-cba0952d11e8','43b1759a-1bb6-48e6-a14d-e53785808fbf','03636e75-437b-4b60-b4f0-64153652eb54','ddfe49e6-65d3-4208-b55d-a6a975e6bea1','af5a9cd0-4c4e-4aa3-bd2b-fa40753b26ed','80046e2d-3f3a-4f9e-801a-fc991c5e4c32','96765589-eb32-48a2-a8c0-d0f1a7e0fc36','1cfdc5be-2548-4d88-b2fd-4e7f2fa0ba14','8d1df7af-d485-46fd-99a1-c663da2baa95','d0d624de-e22d-4108-b00f-f28311db72a1','0b412c7b-1188-4f4f-9d87-dbd70266fbc3','9b30c07f-b6dd-4939-ad19-93f697f7a744','f3cf9eee-cc77-4947-9e6d-1cda4ce4c850','622b42fa-42fd-41d5-9b85-84bed1055f50','69fcd4c7-579f-47be-9631-d518e89d447a','ce6c089a-0cbd-412a-9f64-78302dd283d6','360df331-5962-4ef0-8137-87c6020d5480','66aa6d74-3bbb-4e3e-9f78-f38eca0bbb48','63e263e7-1a2e-40ae-8f70-448b885ae661','18741ace-68d4-46bb-a4fe-1e7afb1314f6','24310bf2-03fa-4f88-820d-6b3b73ae4daa','5b665644-32b9-4ee6-af94-80a2c62837d1','f5ca5af4-2ed5-4978-bc16-9d11ec31bc6a','365cdb6a-4a0a-4e1d-8248-067fc8ac6901','b46eebd1-6090-4cf6-b125-3d602e6d2b1d','9b26b633-d18a-4964-9d04-3206598bc00f','f1336b69-f15b-4674-995f-3732600961f9','4870fda5-fa06-4395-a91a-1166adbadd0f','f9029e0c-15cd-4ba6-ab0e-d5b3e82e053c','7fede135-c8c2-43cb-8504-7e1ab8c1e9eb','36f3421f-6f31-4ac3-a571-3e4c65b15522','a7fae50e-3901-4927-b11f-25af9a7b424e','8b03bf9d-aa32-4ca7-b056-db925cdd0aea','eab50142-cba1-4caa-88ac-2d39ccf6857f','0910a133-ed68-43c3-8a24-b62c06178468','0ba2a4a1-749c-4079-99b6-8c10d9eae203','28190ed4-ebcf-41d4-89e0-9ba390b96cd7','a81ba71f-558d-453f-ad34-3908a74eb3e8','4bfc4572-8af8-401b-ba85-0e44d3dcda5a','9b439540-a294-4896-93e6-fc01f20628a0','051a2aa4-d4ce-4f24-8d9c-50954ff75bb1','3a9c962e-773a-4ecd-9e5f-6b6df3307522','39dda93f-ecf9-475c-9afc-7cb309720f54','521509e4-96aa-46b4-95f5-7856c3056f82','ca550c34-7a4a-4102-b956-1a03a493d96c','2237f66b-e4d7-48d8-82c8-7c72783d074f','7f943083-d68d-4cd5-9928-eebcedfff969','192622d0-7e6a-42b3-9568-f2587d1190a6','7c8d73c4-71aa-4917-88f8-85d4ecadf502','54e4ee4d-2440-4e66-aeef-061de8061a0a','aaf4da00-2d7c-48a7-8f92-a299fed5c871','74af93c0-07a7-4627-a0a3-c4939e77fb8c','89dced20-c147-4b9e-b5c3-10429dac3baa','7824ddb2-8b47-4d9c-bf7c-e84c8652d3c8','cc87ae7e-51cf-4ab8-88db-6f7f50de9789','4a8526c7-4cda-41cb-a778-242e872681d8']
OUT = '/tmp/sanitize-run.jsonl'
BUDGET = float(sys.argv[1]) if len(sys.argv) > 1 else 600.0

c0 = server.get_client()
BASE = str(c0.base_url).rstrip('/')
H = dict(c0._headers())

done = set()
if os.path.exists(OUT):
    for line in open(OUT, encoding='utf-8'):
        try:
            r = json.loads(line)
            if r.get('code') == 200:
                done.add(r['doc'])
        except Exception:
            pass
todo = [d for d in IDS if d not in done]
print('RESUME done=%d todo=%d budget=%ss' % (len(done), len(todo), BUDGET), flush=True)

stats = {'ok': 0, 'conflict': 0, 'capacity': 0, 'other': 0, 'exc': 0, 'timeout': 0}
t0 = time.time()
# 900s per doc: measured 144-chunk doc needs ~655s; 700s was too tight.
with httpx.Client(base_url=BASE, headers=H, timeout=900.0) as c:
    for i, doc in enumerate(todo, 1):
        if time.time() - t0 > BUDGET:
            print('BUDGET_STOP after %d docs' % (i-1), flush=True); break
        t = time.time()
        try:
            r = c.post('/api/documents/%s/sanitize' % doc, json={'data_level': 'T2'})
            code = r.status_code
            body = r.text[:200].replace(chr(10), ' ')
            stats['ok' if code == 200 else 'conflict' if code == 409 else 'capacity' if code == 503 else 'other'] += 1
        except Exception as e:
            code, body = 0, 'timeout/err: ' + str(e)[:140]
            stats['timeout'] += 1
        rec = {'doc': doc, 'code': code, 'secs': round(time.time()-t, 1), 'body': body}
        with open(OUT, 'a', encoding='utf-8') as f:
            f.write(json.dumps(rec, ensure_ascii=False) + chr(10))
        print('PROG %s code=%s %.0fs %s' % (doc[:8], code, rec['secs'], stats), flush=True)
print('CHUNK_DONE %.0fs %s' % (time.time()-t0, stats), flush=True)
