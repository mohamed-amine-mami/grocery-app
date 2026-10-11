import json, collections, re
from urllib.parse import urlparse
S='/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
O='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
cat=json.load(open(O+'catalog.v2.json')); prov={p['slug']:p for p in json.load(open(O+'provenance.json'))['products']}
photo=json.load(open(O+'photo-validation.json')); rev=json.load(open(S+'out/photo_review.json'))
cand={r['url']:r for r in photo['urls']}
def tbl(rows, header):
    out=['| '+' | '.join(header)+' |','|'+'|'.join(['---']*len(header))+'|']
    for r in rows: out.append('| '+' | '.join(str(x).replace('|','/') for x in r)+' |')
    return '\n'.join(out)
rin={u:r for u,r in rev.items() if u in cand}
r1=[r for r in rin.values() if r.get('round',1)==1]; r2=[r for r in rin.values() if r.get('round')==2]
used=[]; 
for c in cat['categories']:
    for p in c['products']:
        if p['photo']: used.append((c['slug'],p,prov[p['slug']]['photo']['source']))
by_cat=collections.defaultdict(lambda:[0,0])
by_src=collections.defaultdict(lambda:[0,0])
for c,p,src in used:
    by_cat[c][0]+=1; by_src[src][0]+=1
    if rev.get(p['photo'],{}).get('verdict')=='accepted': by_cat[c][1]+=1; by_src[src][1]+=1
rej=collections.Counter((r['source'],r['verdict']) for r in rin.values() if r['verdict']!='accepted')
inv=[r for r in photo['urls'] if not r['urlValid']]
nonnull=len(used); insp=sum(v[1] for v in by_cat.values())
nulls=sum(1 for c in cat['categories'] for p in c['products'] if not p['photo'])
sec=f"""

<!-- round2 -->
## 5. Review round 2 — definitions, coverage and the targeted sample

Counts are over the **current** candidate ({nonnull:,} products with a photo, {nulls} with `null`). Five different things are counted separately:

| Measure | Count | What it means |
|---|---|---|
| URLs **checked for HTTP/accessibility and image content type** | **{len(cand):,}** | every candidate URL of every source record (HEAD, ranged-GET fallback; 200/206 + `image/*` + ≥ 1.5 KB) |
| – passed | {len(cand)-len(inv):,} | |
| – **failed / removed** | **{len(inv)}** | {sum(1 for r in inv if r['httpStatus']==404)} HTTP 404, {sum(1 for r in inv if r['httpStatus']!=404)} other; never used |
| Images **visually inspected** | **{len(rin)}** distinct | round 1: {len(r1)}; round 2 (targeted): {len(r2)} |
| – inspected and **rejected** (not used → fallback source or `null`) | **{sum(rej.values())}** | {dict((f'{a}:{b.replace("rejected-","")}',n) for (a,b),n in sorted(rej.items()))} |
| Photos used in the catalogue that were **inspected and accepted** | **{insp:,}** | |
| Photos used that are URL-valid but **not visually verified** | **{nonnull-insp:,}** | relevance to the product is **unverified**; not claimed as correct |

### Did the first sample cover the sources and categories? — no, so a targeted round was added
Round 1 covered every source but was thin in fresh produce (34 of 235 inspected), meat/poultry/fish, frozen, charcuterie, snacks and confectionery, and had no check for variant families, package sizes or identical files. Round 2 inspected **{len(r2)} more images** aimed at those gaps:

| Target | Images | Result |
|---|---|---|
| Fresh produce — every remaining photo in `fruits` and `legumes` | 63 | 1 rejected (garlic/onion confusion); 1 misfiled product found (citron under légumes → fixed) |
| Fresh meat / poultry / fish sample | 32 | 0 rejected; 1 misfiled (sardine under viandes → fixed), 1 soup under volaille (fixed) |
| Low-coverage categories (surgelés, charcuterie, snacks, confiserie, boulangerie, fromages) | 60 | 1 rejected (Exquise tub showed Eskimo), 2 rejected (bakery photos carry Carrefour's logo) |
| Variant families (same brand + line, ≥ 4 distinct photos; 3 sampled each) | 36 | 0 wrong flavour found in 12 families |
| Package-size families (same brand/line, 2 sizes) | 28 | 1 rejected (honey box ≠ sibling jar); others fine |
| Byte-identical image files shared by different products (all 14 groups) | 28 | 0 rejected (size variants and generic stock photos) |
| Other-retailer logo / branding check on **every** brandless Carrefour counter item not yet seen | 79 | 0 more with logos |

### Coverage by category — photos used / inspected and accepted
{tbl([(c,v[0],v[1],f'{100*v[1]//max(1,v[0])} %') for c,v in sorted(by_cat.items(), key=lambda kv:-kv[1][0])],['Category','Photos used','Inspected & accepted','Share'])}

### Coverage by source of the photo used
{tbl([(s,v[0],v[1],f'{100*v[1]//max(1,v[0])} %') for s,v in sorted(by_src.items(), key=lambda kv:-kv[1][0])],['Source','Photos used','Inspected & accepted','Share'])}

Weak area that remains: `epicerie` (the largest category, mostly Géant packs). Its inspected share is the lowest of the big categories; the Géant sample error rate overall is {sum(1 for r in rin.values() if r['source']=='geant' and r['verdict']!='accepted')} rejects in {sum(1 for r in rin.values() if r['source']=='geant')} Géant images inspected, which is an estimate, not a verification of the other ~{by_src['geant'][0]-by_src['geant'][1]:,} Géant photos.

### Known wrong or unreliable matches → `null` (or fallback to a verified photo)
All {sum(rej.values())} rejected images are listed with reasons in section 2 of this report (round 1) and below (round 2):

{tbl([(r['n'],r['source'],r['name'][:48],r['reason']) for r in r2 if r['verdict']!='accepted'],['Item','Source','Product','Reason'])}

Rule applied for the **un-inspected** population: a photo is used only if its URL passed the accessibility check; that is *not* evidence the picture is right. The honest statement for the catalogue is: {insp:,} photos visually verified, {nonnull-insp:,} not.
"""
s=open(O+'photo-validation.md').read()
s=s.split('\n<!-- round2 -->')[0]+sec
open(O+'photo-validation.md','w').write(s)
print(len(r1),len(r2),insp,nonnull-insp,len(inv),dict(rej))
