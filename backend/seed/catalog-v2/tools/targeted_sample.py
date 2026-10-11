import json,collections,random,re,os,hashlib,urllib.request,concurrent.futures as cf
from urllib.parse import urlparse
from PIL import Image, ImageDraw, ImageFont
random.seed(77)
CAT='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/catalog.v2.json'
cat=json.load(open(CAT)); rev=json.load(open('out/photo_review.json')); st=json.load(open('out/photo_status.json'))
prov={p['slug']:p for p in json.load(open('/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/provenance.json'))['products']}
rows=[(c['slug'],p) for c in cat['categories'] for p in c['products'] if p['photo']]
rev_in={u for u in rev}
def src_of(p): return prov[p['slug']]['photo']['source'] if prov[p['slug']].get('photo') else '?'
def uninsp(lst): return [(c,p) for c,p in lst if p['photo'] not in rev_in]
sel=collections.OrderedDict()  # slug -> (cat,p,reason)
def add(c,p,reason):
    if p['slug'] not in sel and p['photo'] not in rev_in: sel[p['slug']]=(c,p,reason)
# a) fresh
for c,p in uninsp(rows):
    if c in ('fruits','legumes'): add(c,p,'fresh produce')
for cc,n in (('viandes',10),('volaille',10),('poissons-fruits-de-mer',12)):
    for c,p in random.sample(uninsp([r for r in rows if r[0]==cc]),n): add(c,p,'fresh meat/fish')
# b) low-coverage categories
for cc in ('surgeles','charcuterie-traiteur','snacks-aperitif','chocolat-confiserie','boulangerie','fromages'):
    for c,p in random.sample(uninsp([r for r in rows if r[0]==cc]),10): add(c,p,'low-coverage category')
# c) variant families (same brand + same first two words of name) with >=3 siblings
fam=collections.defaultdict(list)
for c,p in rows:
    if p.get('brandSlug'):
        w=re.sub(r'[^a-zà-ÿ ]','',p['name'].lower()).split()[:2]
        fam[(p['brandSlug'],' '.join(w))].append((c,p))
fams=[v for v in fam.values() if len(v)>=4 and len({x[1]['photo'] for x in v})>=4]
random.shuffle(fams)
for v in fams[:14]:
    for c,p in random.sample(v,3): add(c,p,'variant family')
# d) packaged sizes: same brand + same name without size, different size
sz=collections.defaultdict(list)
for c,p in rows:
    if p.get('brandSlug'):
        base=re.sub(r'\b\d+(?:[.,]\d+)?\s*(?:kg|g|l|cl|ml)\b','',p['name'].lower()).strip()
        sz[(p['brandSlug'],base)].append((c,p))
szf=[v for v in sz.values() if len(v)>=2]
random.shuffle(szf)
for v in szf[:14]:
    for c,p in v[:2]: add(c,p,'package-size family')
# e) identical-size groups -> hash both
cl=collections.defaultdict(list)
for c,p in rows:
    s=st.get(p['photo'],{})
    if s.get('size'): cl[(urlparse(p['photo']).netloc,s['size'])].append((c,p))
groups=[v for v in cl.values() if len(v)>1]
def dl(item):
    c,p=item
    fn='img/'+re.sub(r'[^a-z0-9]+','_',p['slug'])[:60]+'__t.img'
    if not os.path.exists(fn):
        try: open(fn,'wb').write(urllib.request.urlopen(urllib.request.Request(p['photo'],headers={'User-Agent':'Mozilla/5.0 (GrocerGo catalog research; visual check)'}),timeout=40).read())
        except Exception: return None
    return fn
flat=[x for g in groups for x in g]
with cf.ThreadPoolExecutor(8) as ex: fns=dict(zip([x[1]['slug'] for x in flat],ex.map(dl,flat)))
dups=[]
for g in groups:
    hs=collections.defaultdict(list)
    for c,p in g:
        fn=fns.get(p['slug'])
        if fn: hs[hashlib.md5(open(fn,'rb').read()).hexdigest()].append((c,p))
    for h,v in hs.items():
        if len(v)>1: dups.append(v)
print('identical-size groups',len(groups),'byte-identical image groups',len(dups),'products',sum(len(v) for v in dups))
for v in dups:
    for c,p in v: 
        if p['slug'] not in sel: sel[p['slug']]=(c,p,'byte-identical image shared by several products')
        else: sel[p['slug']]=(c,p,sel[p['slug']][2]+'; byte-identical image')
json.dump([[ [p['slug'] for c,p in v], v[0][1]['photo'] ] for v in dups],open('out/identical_image_groups.json','w'),ensure_ascii=False,indent=1)
# sheets
items=list(sel.values())
with cf.ThreadPoolExecutor(8) as ex: files=list(ex.map(lambda t: dl((t[0],t[1])),items))
man=json.load(open('out/sample_manifest_all.json')); n=max(r['n'] for r in man); sheet_no=max(r['sheet'] for r in man)
CW,CH=230,250; font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',18)
extra=[]
for i in range(0,len(items),20):
    sheet_no+=1; sh=Image.new('RGB',(5*CW,4*CH),'white'); dr=ImageDraw.Draw(sh)
    for k,((c,p,why),fn) in enumerate(zip(items[i:i+20],files[i:i+20])):
        n+=1; x,y=(k%5)*CW,(k//5)*CH
        try:
            im=Image.open(fn).convert('RGB'); im.thumbnail((CW-10,CH-40)); sh.paste(im,(x+5+(CW-10-im.width)//2,y+30+(CH-40-im.height)//2))
        except Exception: dr.text((x+10,y+100),'UNREADABLE',fill='red',font=font)
        dr.rectangle([x,y,x+CW-1,y+CH-1],outline='#999'); dr.text((x+6,y+4),f'#{n}',fill='black',font=font)
        extra.append(dict(n=n,sheet=sheet_no,slug=p['slug'],name=p['name'],brand=p.get('brandSlug'),category=c,source=src_of(p),image=p['photo'],file=fn,why=why))
    sh.save(f'out/sheets/sheet_{sheet_no:02d}.jpg',quality=82)
json.dump(extra,open('out/targeted_manifest.json','w'),ensure_ascii=False,indent=1)
print(len(extra),'images in',sheet_no-max(r['sheet'] for r in man),'sheets; first sheet',max(r['sheet'] for r in man)+1)
cur=0
for r in extra:
    if r['sheet']!=cur: cur=r['sheet']; print(f"\n=== sheet {cur}")
    print(f"#{r['n']} [{r['source']}/{r['category']}] {r['name'][:50]} | {r['brand'] or '-'} | {r['why'][:28]}")
