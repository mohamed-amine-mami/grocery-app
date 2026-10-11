import re,json,time,html,urllib.request,sys
UA={'User-Agent':'Mozilla/5.0 (GrocerGo catalog research; read-only)'}
def get(u):
    for i in range(3):
        try:
            return urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=30).read().decode('utf8','replace')
        except Exception as e:
            err=e; time.sleep(2)
    print('FAIL',u,err,file=sys.stderr); return ''
seen={}; cats={}
def parse(h,catname):
    n=0
    for m in re.finditer(r'<article[^>]*data-id-product="(\d+)".*?</article>',h,re.S):
        b=m.group(0); pid=m.group(1)
        t=re.search(r'class="h3 product-title">\s*<a href="([^"]+)">([^<]+)</a>',b)
        img=re.search(r'data-full-size-image-url="([^"]+)"',b) or re.search(r'data-src="([^"]+)"',b)
        pr=re.search(r'class="product-price"[^>]*content="([\d.]+)"',b)
        cat=re.search(r'product-category-name text-muted">([^<]*)<',b)
        if pid not in seen:
            seen[pid]=dict(sourceId=pid,url=t.group(1) if t else None,name=html.unescape(t.group(2)).strip() if t else None,image=img.group(1) if img else None,price=pr.group(1) if pr else None,sourceCategory=html.unescape(cat.group(1)).strip() if cat else catname,listing=catname)
            n+=1
    return n
queue=[('https://mg.tn/15-alimentaire','alimentaire'),('https://mg.tn/16-marche-frais','marche-frais'),('https://mg.tn/10-bien-manger','bien-manger'),('https://mg.tn/77-le-bio','bio'),('https://mg.tn/74-cuisine','cuisine'),('https://mg.tn/76-mg-marque-historique','mg-marque')]
done=set()
while queue:
    u,c=queue.pop(0)
    if u in done: continue
    done.add(u); h=get(u); time.sleep(1)
    n=parse(h,c)
    # pagination
    for p in set(re.findall(r'href="(https://mg\.tn/\d+-[a-z0-9-]+\?page=\d+)"',h)):
        if p not in done: queue.append((p,c))
    # subcategories
    for s in set(re.findall(r'href="(https://mg\.tn/\d+-[a-z0-9-]+)"',h)):
        pass
    print(u,n,file=sys.stderr)
json.dump(list(seen.values()),open('src/mg_raw.json','w'),ensure_ascii=False,indent=0)
print(len(seen))
