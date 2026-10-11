import re,json,time,html,urllib.request,sys
UA={'User-Agent':'Mozilla/5.0 (GrocerGo catalog research; read-only)'}
B='https://www.geantdrive.tn'
def get(u):
    err=None
    for i in range(3):
        try: return urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=40).read().decode('utf8','replace')
        except Exception as e: err=e; time.sleep(3)
    print('FAIL',u,err,file=sys.stderr,flush=True); return ''
prods={}; catnames={}
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
queue=[(u,'') for u in sorted(set(re.findall(r'href="(https://www\.geantdrive\.tn/tunis-city/\d+-[a-z0-9-]+)"',home)))]
done=set(); 
while queue:
    u,_=queue.pop(0)
    if u in done: continue
    done.add(u)
    h=get(u); time.sleep(0.8)
    cat=u.rsplit('/',1)[1]
    n=parse(h,cat)
    for l in set(re.findall(r'href="(https://www\.geantdrive\.tn/tunis-city/\d+-[a-z0-9-]+)"',h)):
        if l not in done and (l,'') not in queue: queue.append((l,''))
    for l in set(re.findall(r'href="(https://www\.geantdrive\.tn/tunis-city/\d+-[a-z0-9-]+\?page=\d+)"',h)):
        if l not in done: queue.insert(0,(l,''))
    print(len(done),len(queue),cat,n,len(prods),file=sys.stderr,flush=True)
    if len(done)%10==0: json.dump(list(prods.values()),open('src/gd_raw.json','w'),ensure_ascii=False)
json.dump(list(prods.values()),open('src/gd_raw.json','w'),ensure_ascii=False)
print('DONE',len(prods),file=sys.stderr,flush=True)
