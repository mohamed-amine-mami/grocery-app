import json,os,re,urllib.request,concurrent.futures as cf
from PIL import Image,ImageDraw,ImageFont
S='/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
D='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
PV={p['slug']:p for p in json.load(open(D+'provenance.json'))['products']}
P=json.load(open(D+'uncertain-matches.json'))['pairs']
LD=[2,9,10,26,41,44,45,46,49,50,73,74,75,84,86,89,108,109,112,114,115,117,121,132,134,142,150,158]
os.makedirs(S+'img3',exist_ok=True); os.makedirs(S+'out/sheets3',exist_ok=True)
def fn(slug,k): return S+'img3/'+re.sub(r'[^a-z0-9]+','_',slug)[:70]+f'_{k}.img'
jobs=[];man=[]
for i in LD:
    p=P[i]; row={'i':i,'brand':p['brand']}
    for side in 'ab':
        s=p[side+'Slug']; pv=PV[s]; urls=[]
        for m in pv['sources']:
            if m.get('imageUrl') and m['imageUrl'] not in urls: urls.append(m['imageUrl'])
        row[side]=dict(slug=s,name=p[side],sources=[(m['source'],m['sourceId'],m['sourceName'],m['sourceDescription']) for m in pv['sources']],urls=urls)
        for k,u in enumerate(urls[:2]): jobs.append((u,fn(s,k)))
    man.append(row)
def dl(j):
    u,f=j
    if os.path.exists(f): return f
    try:
        open(f,'wb').write(urllib.request.urlopen(urllib.request.Request(u,headers={'User-Agent':'Mozilla/5.0 (GrocerGo catalog research; visual check)'}),timeout=40).read()); return f
    except Exception as e: return None
with cf.ThreadPoolExecutor(8) as ex: res=list(ex.map(dl,jobs))
print(len(jobs),sum(1 for r in res if r))
json.dump(man,open(S+'out/dup28_manifest.json','w'),ensure_ascii=False,indent=1)
font=ImageFont.load_default()
def tile(f):
    try:
        im=Image.open(f).convert('RGB'); im.thumbnail((300,300)); return im
    except Exception: return None
for sh in range(0,len(man),3):
    chunk=man[sh:sh+3]
    canvas=Image.new('RGB',(1300,340*len(chunk)),'white'); d=ImageDraw.Draw(canvas)
    for ri,r in enumerate(chunk):
        y=ri*340; x=5
        d.text((5,y+2),f"#{r['i']} {r['brand']} | A: {r['a']['name']}  ||  B: {r['b']['name']}",fill='black',font=font)
        for side in 'ab':
            for k,u in enumerate(r[side]['urls'][:2]):
                t=tile(fn(r[side]['slug'],k))
                if t: canvas.paste(t,(x,y+20))
                d.text((x,y+322),f"{side.upper()}{k+1}",fill='red',font=font); x+=305
            x+=40
    canvas.save(S+f'out/sheets3/dup28_{sh//3+1}.png')
print('sheets',(len(man)+2)//3)
