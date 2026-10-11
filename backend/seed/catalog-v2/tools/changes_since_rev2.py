import json,collections
O='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
H=O+'history/rev2/'
old=json.load(open(H+'provenance.rev2.json'))['products']
new=json.load(open(O+'provenance.json'))['products']
ocat={p['slug']:c['slug'] for c in json.load(open(H+'catalog.v2.rev2.json'))['categories'] for p in c['products']}
ncat={p['slug']:c['slug'] for c in json.load(open(O+'catalog.v2.json'))['categories'] for p in c['products']}
ex=json.load(open(O+'exclusions.json'))
excl={(e['source'],e['sourceId']):e['reason'] for e in ex['excludedRecords']}
coll={(e['src'],e['sid']):'same-source look-alike not distinguishable' for e in ex['sameSourceCollisions']['records']}
def keys(p): return {f"{s['source']}:{s['sourceId']}" for s in p.get('sources',[])}
okey={}; nkey={}
for p in old:
    for k in keys(p): okey[k]=p
for p in new:
    for k in keys(p): nkey[k]=p
oslug={p['slug']:p for p in old}; nslug={p['slug']:p for p in new}
res=dict(unchanged=[],renamed=[],recategorised=[],merged=[],removed=[],added=[])
for p in old:
    ks=keys(p)
    if p['slug'] in nslug and not p.get('sources'):  # existing product restated
        n=nslug[p['slug']]
        (res['unchanged'] if ocat[p['slug']]==ncat[n['slug']] else res['recategorised']).append(dict(slug=p['slug'],name=p['name'],old=ocat[p['slug']],new=ncat[n['slug']]))
        continue
    targets={nkey[k]['slug'] for k in ks if k in nkey}
    if not targets:
        reasons=set()
        for k in ks:
            s,sid=k.split(':',1)
            reasons.add(excl.get((s,sid)) or coll.get((s,sid)) or 'dropped by round-3 rule')
        res['removed'].append(dict(slug=p['slug'],name=p['name'],brand=p.get('brand'),category=ocat.get(p['slug']),reason='; '.join(sorted(reasons))))
        continue
    if len(targets)>1:
        res['renamed'].append(dict(slug=p['slug'],name=p['name'],note='split into '+', '.join(sorted(targets)))); continue
    t=nslug[next(iter(targets))]
    if t['slug']==p['slug'] and ocat[p['slug']]==ncat[t['slug']] and t['name']==p['name']:
        res['unchanged'].append(dict(slug=p['slug'],name=p['name']))
    else:
        old_keys_for_t={k for k in keys(t)}
        merged_from=[q for q in old if q is not p and keys(q)&keys(t)]
        rec=dict(oldSlug=p['slug'],oldName=p['name'],oldBrand=p.get('brand'),oldCategory=ocat.get(p['slug']),newSlug=t['slug'],newName=t['name'],newBrand=t.get('brand'),newCategory=ncat[t['slug']])
        if merged_from or len(keys(t))>len(ks): res['merged'].append(rec)
        elif t['name']!=p['name'] or t['slug']!=p['slug'] or p.get('brand')!=t.get('brand'): res['renamed'].append(rec)
        else: res['recategorised'].append(rec)
for p in new:
    if not p.get('sources'): continue
    if not any(k in okey for k in keys(p)):
        res['added'].append(dict(slug=p['slug'],name=p['name'],brand=p.get('brand'),category=ncat[p['slug']],sources=sorted({s['source'] for s in p['sources']})))
# merged: keep unique by newSlug listing all old slugs
grp=collections.defaultdict(list)
for r in res['merged']: grp[r['newSlug']].append(r)
res['merged']=[dict(newSlug=k,newName=v[0]['newName'],newBrand=v[0]['newBrand'],newCategory=v[0]['newCategory'],mergedFrom=[dict(slug=x['oldSlug'],name=x['oldName']) for x in v]) for k,v in grp.items()]
summary={k:len(v) for k,v in res.items()}
oldN=sum(1 for _ in old)+0
json.dump(dict(from_='rev2 (5,801 products, 671 brands)',summary=summary,**res),open(O+'changes-since-rev2.json','w'),ensure_ascii=False,indent=1)
rr=collections.Counter(r['reason'][:70] for r in res['removed'])
print(summary); print(rr.most_common(8))
print('rename sample',res['renamed'][:2]); 
