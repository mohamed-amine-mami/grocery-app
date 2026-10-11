import json, re, collections, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from textlib import *
S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
O = '/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
cat = json.load(open(O + 'catalog.v2.json'))
prov = {p['slug']: p for p in json.load(open(O + 'provenance.json'))['products']}
st2 = json.load(open(S + 'out/stage2.json'))
val = json.load(open(S + 'out/validate.json'))
db = {p['slug']: p for p in json.load(open(S + 'src/existing_db_products.json'))}
pork = json.load(open(S + 'out/pork_candidates.json'))
review = json.load(open(S + 'out/photo_review.json'))
allp = {p['slug']: (c['slug'], p) for c in cat['categories'] for p in c['products']}
def tbl(rows, header):
    out = ['| ' + ' | '.join(header) + ' |', '|' + '|'.join(['---'] * len(header)) + '|']
    for r in rows: out.append('| ' + ' | '.join(str(x).replace('|', '/') for x in r) + ' |')
    return '\n'.join(out)

# ------------------------------------------------------------- item 5: chamia / bsissa / zrir
rows = []
for slug, (c, p) in allp.items():
    pr = prov[slug]
    n = fold(p['name'])
    srcs = pr.get('sources', [])
    in_sub = any('/chamia-bsissa-et-zrir/' in (s.get('url') or '') for s in srcs)
    if re.search(r'\b(chamia|helva|halwa|bsissa|zrir)\b', n) or in_sub:
        typ = ('chamia (halva)' if re.search(r'chamia|helva|halwa', n) else 'bsissa' if 'bsissa' in n else 'zrir' if 'zrir' in n else 'other')
        rows.append(dict(slug=slug, name=p['name'], brand=pr.get('brand'), type=typ, finalCategory=c,
                         sources=[(s['source'], s['sourceName'], s['sourceCategory']) for s in srcs]))
json.dump(rows, open(O + 'chamia-bsissa-review.json', 'w'), ensure_ascii=False, indent=1)
tc = collections.Counter((r['type'], r['finalCategory']) for r in rows)
cb_md = tbl([(t, c, n) for (t, c), n in sorted(tc.items())], ['Food type', 'Final category', 'Products'])

# ------------------------------------------------------------- item 6: duplicates
dm = st2.get('descriptorMerges', [])
unc = st2['uncertain']
sizeless = [u for u in unc if 'size unknown' in u['reason']]
samesize = [u for u in unc if 'same size' in u['reason']]
hi = sorted([u for u in samesize if u['similarity'] >= 0.8], key=lambda u: -u['similarity'])
variants = [u for u in samesize if u['similarity'] < 0.8]
sizeless_hi = sorted([u for u in sizeless if u['similarity'] >= 0.75], key=lambda u: -u['similarity'])
coll = st2['sameSourceCollisions']
cc = collections.Counter((r['brand'], re.sub(r'\s+\d.*$', '', r['name'])) for r in coll)
json.dump(dict(descriptorMergesApplied=[dict(brand=b, kept=a, mergedAway=c_, sources=s) for a, c_, b, s in dm],
               sameBrandSameSizeSimilarWording=samesize, sameWordingSizeUnknown=sizeless, sameSourceCollisions=coll),
          open(O + 'duplicate-review.json', 'w'), ensure_ascii=False, indent=1)

# ------------------------------------------------------------- corrections log
corr = [dict(slug=p['slug'], name=p['name'], category=p['category'], rule=p['correction']) for p in st2['products'] if p.get('correction')]
json.dump(corr, open(O + 'classification-corrections.json', 'w'), ensure_ascii=False, indent=1)
cc2 = collections.Counter(c['rule'].split(' ')[0] for c in corr)

# ------------------------------------------------------------- brand review
brands = {b['slug']: b for b in cat['brands']}
tlj = [(s, p) for s, (c, p) in allp.items() if p.get('brandSlug') == 'tous-les-jours']
tlj_cat = collections.Counter(allp[s][0] for s, p in tlj)
excl = json.load(open(O + 'exclusions.json'))
n_geant_only = sum(1 for s, p in tlj if {x['source'] for x in prov[s]['sources']} == {'geant'})
mg_brand = {k: sum(1 for s, (c, p) in allp.items() if p.get('brandSlug') == k) for k in ('mg-j-aime', 'koll-youm')}
open(S + 'out/round2_numbers.json', 'w').write(json.dumps(dict(chamia_rows=len(rows), dm=len(dm), hi=len(hi), variants=len(variants), sizeless=len(sizeless),
    coll=len(coll), corr=len(corr), tlj=len(tlj), tlj_cat=tlj_cat, n_geant_only=n_geant_only, mg_brand=mg_brand, cc=cc2), default=str))
print(len(rows), 'chamia/bsissa rows;', len(dm), 'descriptor merges;', len(corr), 'corrections;', tlj_cat, mg_brand)
print(cb_md)
