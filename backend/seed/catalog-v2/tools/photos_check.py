"""Stage 3a: basic URL validity for every candidate photo URL (HEAD, GET fallback). Polite concurrency."""
import json, sys, time, threading, urllib.request, urllib.error, collections, concurrent.futures as cf
S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
d = json.load(open(S + 'out/stage2.json'))
urls = collections.OrderedDict()
for p in d['products']:
    for m in p['members']:
        if m.get('image'):
            urls.setdefault(m['image'], []).append((p['slug'], m['src']))
prev = {}
try:
    prev = json.load(open(S + 'out/photo_status.json'))
except Exception:
    pass
todo = [u for u in urls if u not in prev]
print('unique urls', len(urls), 'todo', len(todo), flush=True)
UA = {'User-Agent': 'Mozilla/5.0 (GrocerGo catalog research; URL validity check)'}
host_sem = collections.defaultdict(lambda: threading.Semaphore(4))

def check(u):
    from urllib.parse import urlparse
    h = urlparse(u).netloc
    with host_sem[h]:
        for method in ('HEAD', 'GET'):
            try:
                req = urllib.request.Request(u, headers=dict(UA, **({'Range': 'bytes=0-2047'} if method == 'GET' else {})), method=method)
                with urllib.request.urlopen(req, timeout=25) as r:
                    ct = r.headers.get('Content-Type', '')
                    cl = r.headers.get('Content-Length')
                    cr = r.headers.get('Content-Range')
                    size = int(cr.split('/')[-1]) if cr and '/' in cr and cr.split('/')[-1].isdigit() else (int(cl) if cl and cl.isdigit() else None)
                    ok = r.status in (200, 206) and ct.lower().startswith('image/') and (size is None or size >= 1500)
                    return dict(status=r.status, contentType=ct, size=size, ok=ok, method=method, finalUrl=r.geturl() if r.geturl() != u else None)
            except urllib.error.HTTPError as e:
                if method == 'HEAD' and e.code in (403, 405, 400, 501):
                    continue
                return dict(status=e.code, ok=False, method=method, error=f'HTTP {e.code}')
            except Exception as e:
                if method == 'HEAD':
                    continue
                return dict(status=None, ok=False, method=method, error=type(e).__name__ + ': ' + str(e)[:80])
    return dict(status=None, ok=False, error='unreachable')

res = dict(prev)
t0 = time.time()
with cf.ThreadPoolExecutor(12) as ex:
    futs = {ex.submit(check, u): u for u in todo}
    for i, f in enumerate(cf.as_completed(futs)):
        res[futs[f]] = f.result()
        if i % 300 == 0:
            print(i, len(todo), round(time.time() - t0), flush=True)
            json.dump(res, open(S + 'out/photo_status.json', 'w'))
json.dump(res, open(S + 'out/photo_status.json', 'w'))
c = collections.Counter((v.get('ok'), v.get('status')) for v in res.values())
print(c)
