import json,re,sys,time,urllib.request,html
sys.path.insert(0,'work')
from taxonomy import GD_MAP
d=json.load(open('src/gd_raw.json'))
todo=[]
for r in d:
    m=re.search(r'/tunis-city/([^/]+)/',r['url'] or '')
    if m and m.group(1) in GD_MAP and ((r['name'] or '').endswith('...') or (r['desc'] or '').endswith('...')): todo.append(r)
out={}
for i,r in enumerate(todo):
    h=''
    for t in range(3):
        try: h=urllib.request.urlopen(urllib.request.Request(r['url'],headers={'User-Agent':'Mozilla/5.0 (GrocerGo catalog research; read-only)'}),timeout=30).read().decode('utf8','replace'); break
        except Exception as e: time.sleep(3)
    n=re.search(r'<h1[^>]*>(.*?)</h1>',h,re.S); ds=re.search(r'<meta name="description" content="([^"]*)"',h)
    b=re.search(r'/tunis-city/brand/\d+-[a-z0-9-]+">\s*([^<]+)<',h)
    out[r['sourceId']]=dict(name=html.unescape(re.sub(r'\s+',' ',n.group(1))).strip() if n else None,desc=html.unescape(ds.group(1)).strip() if ds else None)
    if i%50==0:
        print(i,len(todo),file=sys.stderr,flush=True); json.dump(out,open('src/gd_full.json','w'),ensure_ascii=False)
    time.sleep(0.7)
json.dump(out,open('src/gd_full.json','w'),ensure_ascii=False); print('DONE',len(out),file=sys.stderr,flush=True)
