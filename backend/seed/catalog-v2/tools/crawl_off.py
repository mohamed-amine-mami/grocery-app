import json,time,urllib.request,sys
UA={'User-Agent':'GrocerGo-catalog-research/1.0 (portfolio project; read-only)'}
F='code,product_name,product_name_fr,brands,quantity,categories_tags,image_front_url,lang,last_modified_t'
out=[];page=1
while True:
    u=f'https://world.openfoodfacts.org/api/v2/search?countries_tags_en=tunisia&page_size=100&page={page}&fields={F}'
    d=None
    for i in range(4):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=90)); break
        except Exception as e:
            print('retry',page,e,file=sys.stderr,flush=True); time.sleep(8)
    if d is None: print('GAVE UP page',page,file=sys.stderr); break
    ps=d.get('products',[])
    out+=ps
    print(page,len(ps),len(out),file=sys.stderr,flush=True)
    if len(ps)<100: break
    page+=1; time.sleep(3)
json.dump(out,open('src/off_raw.json','w'),ensure_ascii=False)
