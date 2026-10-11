import re,json,time,html,urllib.request,sys
UA={'User-Agent':'Mozilla/5.0 (GrocerGo catalog research; read-only)'}
B='https://www.geantdrive.tn'
def get(u):
    err=None
    for i in range(3):
        try: return urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=40).read().decode('utf8','replace')
        except Exception as e: err=e; time.sleep(3)
    print('FAIL',u,err,file=sys.stderr,flush=True); return ''
import os
prods={r['sourceId']:r for r in json.load(open('src/gd_raw_part1.json'))}; catnames={}
VISITED=set('10 100 107 11 114 120 130 131 135 14 142 152 158 160 161 165 170 174 177 18 181 186 189 190 193 196 199 202 205 208 210'.split())
NONFOOD=set('24 211 214 218 220 230 236 248 251 262 268 269 277 280 289 296 306 312 313 317 320 322 323 326 332 337 821 822 823 824 825 826 827 828 854 855 858 867 868 869 874 875 876 878 893 898 899 900 901 902 923 926 939 943 944 951 957 963 964 965 966 25 189 210'.split())
def parse(h,cat):
    n=0
    for m in re.finditer(r'<article class="product-miniature[^>]*data-id-product="(\d+)".*?</article>',h,re.S):
        b=m.group(0); pid=m.group(1)
        a=re.search(r'class="h3 product-title"[^>]*><a\s+href="([^"]+)">([^<]*)</a>',b)
        man=re.search(r'manufacturer_product[^>]*>\s*([^<]*)<',b)
        sd=re.search(r'product_short">\s*([^<]*)<',b)
        im=re.search(r'data-full-size-image-url="([^"]+)"',b)
        pr=re.search(r'class="price[^"]*"[^>]*>\s*([^<]+)<',b)
        r=prods.setdefault(pid,dict(sourceId=pid,url=a.group(1) if a else None,name=html.unescape(a.group(2)).strip() if a else None,brand=html.unescape(man.group(1)).strip() if man else '',desc=html.unescape(sd.group(1)).strip() if sd else '',image=im.group(1) if im else None,price=pr.group(1).strip() if pr else None,cats=[]))
        if cat not in r['cats']: r['cats'].append(cat); 
        n+=1
    return n
home=get(B+'/tunis-city/'); time.sleep(1)
ok=lambda u: (u.rsplit('/',1)[1].split('-')[0] not in VISITED|NONFOOD)
queue=[(B+'/tunis-city/'+x,'') for x in ['31-epicerie','76-bio','81-dietetiques-et-sans-gluten','333-epicerie-et-boissons','341-le-frais','816-plats-cuisines','818-fruits-secs-seches-et-confits','32-huiles-vinaigres-condiments-et-sauces','41-conserves-de-poissons-et-de-viandes','48-conserves-de-legumes-et-tomates','63-pates-couscous','68-farines-riz-et-legumes-secs','72-sels-epices-et-plats-cuisines','85-produits-sales-et-aperitifs','92-cafes-et-boissons-chaudes']]
done=set(); 
while queue:
    u,_=queue.pop(0)
    if u in done: continue
    done.add(u)
    h=get(u); time.sleep(0.8)
    cat=u.rsplit('/',1)[1]
    n=parse(h,cat)
    for l in set(re.findall(r'href="(https://www\.geantdrive\.tn/tunis-city/\d+-[a-z0-9-]+)"',h)):
        if ok(l) and l not in done and (l,'') not in queue: queue.append((l,''))
    for l in set(re.findall(r'href="(https://www\.geantdrive\.tn/tunis-city/\d+-[a-z0-9-]+\?page=\d+)"',h)):
        if l not in done: queue.insert(0,(l,''))
    print(len(done),len(queue),cat,n,len(prods),file=sys.stderr,flush=True)
    if len(done)%10==0: json.dump(list(prods.values()),open('src/gd_raw.json','w'),ensure_ascii=False)
json.dump(list(prods.values()),open('src/gd_raw.json','w'),ensure_ascii=False)
print('DONE',len(prods),file=sys.stderr,flush=True)
