import json,re,os,urllib.request,concurrent.futures as cf,collections,sys
sys.path.insert(0,'work')
from textlib import fold
from PIL import Image, ImageDraw, ImageFont
O='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
cat=json.load(open(O+'catalog.v2.json')); prov={p['slug']:p for p in json.load(open(O+'provenance.json'))['products']}
rev=json.load(open('out/photo_review.json'))
brands={b['slug']:b['name'] for b in cat['brands']}
by=collections.defaultdict(list)
for c in cat['categories']:
    for p in c['products']:
        if p.get('brandSlug') and p['photo'] and rev.get(p['photo'],{}).get('verdict','accepted')=='accepted': by[p['brandSlug']].append(p)
def slugs(name): return [s for s,n in brands.items() if fold(n)==fold(name)]
PAIRS=[("Al Jazia","El Jazia"),("Calife Souani","Souani"),("Calife Souani","Vieux Calife Souani"),("Daily","Daily'n"),("Dorra","El Dorra"),("Frideal Olina","Olina"),("Furketta","Furkitta"),("Gazelle","La Gazelle"),("Jardin d'Emma","Jardins d'Emma"),("Lebanese Factory","The Lebanese Factory"),("Le Petit Paris","Petit Paris"),("Lovege","Lovego"),("Nablia","Neblia"),("Raoua","Raoua Chani"),("Reflet","Reflets de Tunisie"),("Royaume des Abeilles","Royaumes des Abeilles"),("Seniatna","Senietna"),("Spiga","Spipa"),("Tanit","Tanit le Jardin"),("Tifanny","Tiffanny"),("Tijen","Tijen Water"),("Weepo","Weepop's"),("El Jawhara","Jawhara"),("National Souani","Souani"),("Souani","Vieux Calife Souani")]
cells=[];meta=[]
for a,b in PAIRS:
    for nm in (a,b):
        sl=slugs(nm)
        ps=by.get(sl[0],[]) if sl else []
        for p in ps[:2]:
            cells.append((a+' | '+b,nm,p)); 
        if not ps: cells.append((a+' | '+b,nm,None))
print(len(cells))
def dl(c):
    pr,nm,p=c
    if not p: return None
    fn='img/'+re.sub(r'[^a-z0-9]+','_',p['slug'])[:60]+'__b.img'
    if not os.path.exists(fn):
        try: open(fn,'wb').write(urllib.request.urlopen(urllib.request.Request(p['photo'],headers={'User-Agent':'Mozilla/5.0'}),timeout=40).read())
        except Exception: return None
    return fn
with cf.ThreadPoolExecutor(8) as ex: files=list(ex.map(dl,cells))
CW,CH=230,250;font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',18)
n=0;sheet=0;out=[]
for i in range(0,len(cells),20):
    sheet+=1; sh=Image.new('RGB',(5*CW,4*CH),'white'); dr=ImageDraw.Draw(sh)
    for k,((pr,nm,p),fn) in enumerate(zip(cells[i:i+20],files[i:i+20])):
        n+=1;x,y=(k%5)*CW,(k//5)*CH
        if fn:
            try:
                im=Image.open(fn).convert('RGB');im.thumbnail((CW-10,CH-40));sh.paste(im,(x+5+(CW-10-im.width)//2,y+30+(CH-40-im.height)//2))
            except Exception: pass
        dr.rectangle([x,y,x+CW-1,y+CH-1],outline='#999');dr.text((x+6,y+4),f'#{n}',fill='black',font=font)
        out.append(dict(n=n,sheet=sheet,pair=pr,brand=nm,slug=p['slug'] if p else None,name=p['name'] if p else None))
    sh.save(f'out/sheets/brand_{sheet:02d}.jpg',quality=82)
json.dump(out,open('out/brand_cells.json','w'),ensure_ascii=False,indent=1)
cur=0
for r in out:
    if r['sheet']!=cur: cur=r['sheet']; print('\n== brand sheet',cur)
    print(f"#{r['n']} [{r['brand']}] {r['name']}   <{r['pair']}>")
