"""Stage 4: choose photos, assemble catalog.v2.json + provenance + reports. No network, no database."""
import json, os, sys, re, collections, datetime
sys.path.insert(0, os.path.dirname(__file__))
from textlib import *
from taxonomy import CATEGORIES

S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
OUTD = '/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
os.makedirs(OUTD, exist_ok=True)
now = datetime.date(2026, 10, 10).isoformat()

st2 = json.load(open(S + 'out/stage2.json'))
photo_status = json.load(open(S + 'out/photo_status.json'))
review = json.load(open(S + 'out/photo_review.json'))
snap = json.load(open(S + 'src/existing_snapshot.json'))
dbp = {p['slug']: p for p in json.load(open(S + 'src/existing_db_products.json'))}
products = st2['products']
SRC_LABEL = {'geant': 'Géant Drive (geantdrive.tn, Tunis City)', 'aziza': 'Aziza (aziza.tn, weekly promo catalogue)', 'mg': 'MG (mg.tn)',
             'carrefour': 'Carrefour Tunisie (carrefour.tn, via the existing CSV)', 'off': 'Open Food Facts (world.openfoodfacts.org, Tunisia)'}

# ------------------------------------------------------------------ photos
def choose_photo(p):
    tried = []
    for m in p['members']:
        u = m.get('image')
        if not u:
            tried.append((m['src'], 'no image in source record')); continue
        s = photo_status.get(u, {})
        if not s.get('ok'):
            tried.append((m['src'], 'URL invalid: ' + (s.get('error') or f"HTTP {s.get('status')}"))); continue
        r = review.get(u)
        if r and r['verdict'] != 'accepted':
            tried.append((m['src'], f"visually rejected: {r['reason']}")); continue
        return dict(url=u, source=m['src'], inspected=bool(r), tried=tried)
    return dict(url=None, source=None, inspected=False, tried=tried)

for p in products:
    p['photo'] = choose_photo(p)

# ------------------------------------------------------------------ existing products (restated exactly) and category moves
MOVES = {'escalope-de-poulet': 'volaille', 'poulet-entier': 'volaille', 'viande-hachee-boeuf': 'viandes',
         'daurade': 'poissons-fruits-de-mer', 'fromage-emmental': 'fromages'}
cat_names = {'fruits': 'Fruits', 'legumes': 'Légumes', 'produits-laitiers': 'Produits laitiers', 'boulangerie': 'Boulangerie',
             'viandes-poissons': 'Viandes et poissons', 'epicerie': 'Épicerie', 'boissons': 'Boissons'}
for slug, name, _ in CATEGORIES:
    cat_names.setdefault(slug, name)
existing_cat_slugs = [c['slug'] for c in snap['categories']]
order = existing_cat_slugs + [s for s, _, _ in CATEGORIES if s not in existing_cat_slugs]

by_cat = collections.OrderedDict((c, []) for c in order)
brand_used = {}
by_slug = {}
for p in products:
    if p['existingSlug']:
        e = dbp[p['existingSlug']]
        entry = dict(slug=e['slug'], name=e['name'], brandSlug=None, description=e['description'], photo=p['photo']['url'],
                     defaultSaleUnit=e['defaultSaleUnit'], defaultMinQuantity=e['defaultMinQuantity'],
                     defaultQuantityStep=e['defaultQuantityStep'], defaultMaxQuantity=e['defaultMaxQuantity'], archived=False)
        cat = MOVES.get(e['slug'], e['category'])
    else:
        entry = dict(slug=p['slug'], name=p['name'], brandSlug=p['brandSlug'], description=None, photo=p['photo']['url'],
                     defaultSaleUnit=p['unit'], defaultMinQuantity=p['min'], defaultQuantityStep=p['step'],
                     defaultMaxQuantity=p['max'], archived=False)
        cat = p['category']
        if p['brandKey']:
            brand_used[p['brandSlug']] = p['brand']
    p['finalCategory'] = cat
    by_cat[cat].append(entry)
    by_slug[entry['slug']] = (p, entry, cat)
# existing products that no source matched: restate unchanged (photo stays as in the database = null)
matched = {p['existingSlug'] for p in products if p['existingSlug']}
for slug, e in dbp.items():
    if slug in matched:
        continue
    cat = MOVES.get(slug, e['category'])
    entry = dict(slug=slug, name=e['name'], brandSlug=None, description=e['description'], photo=e['photo'],
                 defaultSaleUnit=e['defaultSaleUnit'], defaultMinQuantity=e['defaultMinQuantity'],
                 defaultQuantityStep=e['defaultQuantityStep'], defaultMaxQuantity=e['defaultMaxQuantity'], archived=False)
    by_cat[cat].append(entry)
    by_slug[slug] = (None, entry, cat)

for c in by_cat:   # stable, readable order: existing products first (db id order), then new ones by name
    exs = [x for x in by_cat[c] if x['slug'] in dbp]
    news = sorted([x for x in by_cat[c] if x['slug'] not in dbp], key=lambda x: (fold(x['name']), x['slug']))
    by_cat[c] = sorted(exs, key=lambda x: dbp[x['slug']]['id']) + news

catalog = dict(
    brands=[dict(slug=s, name=n) for s, n in sorted(brand_used.items())],
    categories=[dict(slug=c, name=cat_names[c], description=None, photo=None,
                     archived=(c == 'viandes-poissons'), products=by_cat[c]) for c in order],
)
json.dump(catalog, open(OUTD + 'catalog.v2.json', 'w'), ensure_ascii=False, indent=1)

BRAND_OWNERSHIP = {
    'tous-les-jours': dict(status='unverified', note='Brand string supplied by Géant Drive only; no source states who owns it. Not claimed to be a Géant label.'),
    'mg-j-aime': dict(status='verified-private-label', owner='Magasin Général', note='mg.tn and press reports describe MG J\'aime as MG\'s distributor brand.'),
    'koll-youm': dict(status='unverified', note='Sold only on mg.tn alongside MG J\'aime; no reachable page states ownership.'),
}
# ------------------------------------------------------------------ provenance sidecar
prov = []
for slug, (p, entry, cat) in by_slug.items():
    if p is None:
        prov.append(dict(slug=slug, existingProduct=True, matchedInSources=False, name=entry['name'], category=cat, sources=[],
                         note='existing catalog product; no source record matched with confidence, restated unchanged'))
        continue
    prov.append(dict(
        slug=slug, existingProduct=bool(p['existingSlug']), matchedInSources=True, name=entry['name'], brand=p['brand'], brandSlug=p['brandSlug'], category=cat,
        privateLabelOf=p['privateLabel'], mergedRecords=len(p['members']),
        brandOwnership=BRAND_OWNERSHIP.get(p['brandSlug']),
        unit=dict(saleUnit=entry['defaultSaleUnit'], min=entry['defaultMinQuantity'], step=entry['defaultQuantityStep'], max=entry['defaultMaxQuantity'],
                  basis='existing database values restated' if p['existingSlug'] else ('loose, sold by weight (source marks "Le KG" / "Conditionné par …" / loose market item)' if p['unit'] == 'KG' else 'packaged unit sold per piece')),
        photo=dict(url=p['photo']['url'], source=p['photo']['source'], visuallyInspected=p['photo']['inspected'],
                   fallbacksRejected=[dict(source=a, reason=b) for a, b in p['photo']['tried']]),
        sources=[dict(source=m['src'], sourceId=m['sid'], sourceName=m['srcFullName'] or m['srcName'], sourceBrand=m['srcBrand'] or None,
                      sourceDescription=m['srcDesc'] or None, sourceCategory=m['srcCat'], url=m['url'], imageUrl=m.get('image'),
                      previousConversionSlug=m.get('oldSlug')) for m in p['members']],
    ))
json.dump(dict(generatedOn=now, note='Sidecar only: nothing in this file is imported. Keyed by catalog slug.', products=prov),
          open(OUTD + 'provenance.json', 'w'), ensure_ascii=False, indent=1)

# ------------------------------------------------------------------ photo report data
all_urls = {}
for p in products:
    for m in p['members']:
        if m.get('image'):
            all_urls.setdefault(m['image'], set()).add(m['src'])
url_rows = []
for u, srcs in sorted(all_urls.items()):
    s = photo_status.get(u, {})
    r = review.get(u)
    url_rows.append(dict(url=u, sources=sorted(srcs), httpStatus=s.get('status'), contentType=s.get('contentType'), bytes=s.get('size'),
                         urlValid=bool(s.get('ok')), error=s.get('error'),
                         visualReview=(dict(verdict=r['verdict'], reason=r['reason'] or None, sheet=r['sheet'], item=r['n']) if r else None)))
chosen = collections.Counter()
for p in products:
    if p['photo']['url']:
        chosen[(p['photo']['source'], 'inspected-accepted' if p['photo']['inspected'] else 'url-valid-not-inspected')] += 1
    else:
        chosen[('none', 'null')] += 1
host_counter = collections.Counter()
from urllib.parse import urlparse
for r in url_rows:
    host_counter[(urlparse(r['url']).netloc, r['urlValid'])] += 1
rev_counter = collections.Counter((v['source'], v['verdict']) for u, v in review.items() if u in all_urls)
json.dump(dict(generatedOn=now, summary=dict(
    uniqueUrls=len(url_rows), urlValid=sum(r['urlValid'] for r in url_rows),
    urlInvalid=sum(not r['urlValid'] for r in url_rows),
    visuallyInspected=sum(1 for r in url_rows if r['visualReview']),
    visualAccepted=sum(1 for r in url_rows if r['visualReview'] and r['visualReview']['verdict'] == 'accepted'),
    visualRejected=sum(1 for r in url_rows if r['visualReview'] and r['visualReview']['verdict'] != 'accepted'),
    chosenPhotoBySourceAndStatus={f'{a}|{b}': n for (a, b), n in sorted(chosen.items())}),
    urls=url_rows), open(OUTD + 'photo-validation.json', 'w'), ensure_ascii=False, indent=1)

# ------------------------------------------------------------------ stats for the markdown reports (written by write_reports.py)
stats = dict(
    products=sum(len(v) for v in by_cat.values()), brands=len(catalog['brands']),
    perCategory={c: len(v) for c, v in by_cat.items()},
    perSource=collections.Counter(), withPhoto=0, nullPhoto=0,
)
for p in products:
    for m in p['members']:
        stats['perSource'][m['src']] += 1
for c, v in by_cat.items():
    for x in v:
        if x['photo']:
            stats['withPhoto'] += 1
        else:
            stats['nullPhoto'] += 1
stats['perSource'] = dict(stats['perSource'])
json.dump(dict(stats=stats, chosen={f'{a}|{b}': n for (a, b), n in chosen.items()},
               hostCounter={f'{a}|{b}': n for (a, b), n in host_counter.items()},
               reviewCounter={f'{a}|{b}': n for (a, b), n in rev_counter.items()},
               categoryMoves=MOVES), open(S + 'out/final_stats.json', 'w'), indent=1, ensure_ascii=False)
print(json.dumps(stats, ensure_ascii=False)[:1500])
print('chosen', dict(chosen))
