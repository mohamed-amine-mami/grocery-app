import json, re, collections, os, shutil, sys
sys.path.insert(0, os.path.dirname(__file__))
from textlib import *
from taxonomy import GD_MAP, GD_EXCLUDED_REVIEW, CATEGORIES
from urllib.parse import urlparse
S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
O = '/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
cat = json.load(open(O + 'catalog.v2.json'))
prov = {p['slug']: p for p in json.load(open(O + 'provenance.json'))['products']}
st2 = json.load(open(S + 'out/stage2.json'))
fs = json.load(open(S + 'out/final_stats.json'))
photo = json.load(open(O + 'photo-validation.json'))
val = json.load(open(S + 'out/validate.json'))
db = {p['slug']: p for p in json.load(open(S + 'src/existing_db_products.json'))}
snap = json.load(open(S + 'src/existing_snapshot.json'))
review = json.load(open(S + 'out/photo_review.json'))
gd_raw = json.load(open(S + 'src/gd_raw.json'))

allp = [(c['slug'], p) for c in cat['categories'] for p in c['products']]
N = len(allp)
cat_name = {c['slug']: c['name'] for c in cat['categories']}

# ---- sidecars -------------------------------------------------------------------------------
os.makedirs(O + 'sources', exist_ok=True)
for f in ('mg_raw.json', 'aziza_raw_food.tsv', 'off_raw.json'):
    shutil.copy(S + 'src/' + f, O + 'sources/' + f)
for f in ('textlib.py', 'taxonomy.py', 'crawl_mg.py', 'crawl_gd.py', 'crawl_gd2.py', 'fetch_trunc.py', 'crawl_off.py', 'build_candidates.py', 'build_groups.py', 'photos_check.py', 'photos_sample.py', 'finalize.py', 'validate.mjs', 'write_reports.py'):
    shutil.copy(S + 'work/' + f, O + 'tools/' + f)

# excluded / unresolved
gd_unmapped = collections.Counter()
for r in gd_raw:
    m = re.search(r'/tunis-city/([^/]+)/', r['url'] or '')
    s = m.group(1) if m else '?'
    if s not in GD_MAP:
        gd_unmapped[s] += 1
excl = dict(
    note='Records that were read from a source but are NOT in catalog.v2.json, with the reason. Géant records in out-of-scope sub-categories are counted, not listed.',
    excludedRecords=st2['excludedPre'],
    sameSourceCollisions=dict(note='Same brand + same size + same wording as another record of the same source but a different record id. Not provably the same product, and the importer needs unique names, so only the first one was kept.', records=st2['sameSourceCollisions']),
    nameCollisionsWithExistingOrOtherProducts=st2['nameCollisions'],
    geantOutOfScopeSubcategories=dict(total=sum(gd_unmapped.values()), bySubcategory=dict(gd_unmapped.most_common())),
    geantReviewedAndExcluded=GD_EXCLUDED_REVIEW,
)
json.dump(excl, open(O + 'exclusions.json', 'w'), ensure_ascii=False, indent=1)
json.dump(dict(note='Pairs that look like the same product but are NOT merged (different wording and/or size unknown on one side). For review.', pairs=st2['uncertain']),
          open(O + 'uncertain-matches.json', 'w'), ensure_ascii=False, indent=1)
for b_ in st2['brands']:
    pass
brand_report = dict(
    note='Brand registry with every source spelling that was folded into it, and look-alike brands that were NOT merged (for review).',
    brands=[dict(slug=b['slug'], name=b['name'], sourceSpellings=b['spellings'], **({'ownership': {'tous-les-jours': 'unverified', 'koll-youm': 'unverified (observed MG-exclusive)', 'mg-j-aime': 'verified MG private label'}[b['slug']]} if b['slug'] in ('tous-les-jours','koll-youm','mg-j-aime') else {})) for b in st2['brands']],
    lookAlikesNotMerged=[dict(a=a, b=b) for a, b in st2['brandVariants']])
json.dump(brand_report, open(O + 'brands.json', 'w'), ensure_ascii=False, indent=1)

# ---- integrity checks -------------------------------------------------------------------------
slugs = [p['slug'] for _, p in allp]
brand_slugs = {b['slug'] for b in cat['brands']}
used_b = {p['brandSlug'] for _, p in allp if p.get('brandSlug')}
checks = []
def chk(name, ok, detail=''):
    checks.append((name, ok, detail))
chk('Importer parseCatalog: schema, slug format, uniqueness, brand/category references, quantity rules, photo URL format', val['parseErrorCount'] == 0, f"{val['parseErrorCount']} errors")
chk('Importer planCatalog against the dev-database snapshot: no name collisions / planner errors', len(val['planErrors']) == 0, f"{len(val['planErrors'])} errors")
chk('Product slugs unique across the file', len(slugs) == len(set(slugs)), f'{len(slugs)} products')
chk('Every product brandSlug exists in brands[]', used_b <= brand_slugs, f'{len(used_b)} brands referenced')
chk('No brand in brands[] is unused', brand_slugs == used_b, f'{len(brand_slugs - used_b)} unused')
chk('No Carrefour-branded product (brand or name)', not any('carrefour' in fold(b['name']) for b in cat['brands']) and not any('carrefour' in fold(p['name']) for _, p in allp), '')
ex_slugs = set(db)
new_slugs = [p['slug'] for _, p in allp if p['slug'] not in ex_slugs]
chk('All 42 existing slugs still present exactly once', all(slugs.count(s) == 1 for s in ex_slugs), '')
mism = []
for s, e in db.items():
    p = next(x for _, x in allp if x['slug'] == s)
    for k_db, k_f in (('name', 'name'), ('defaultSaleUnit', 'defaultSaleUnit'), ('defaultMinQuantity', 'defaultMinQuantity'),
                      ('defaultQuantityStep', 'defaultQuantityStep'), ('defaultMaxQuantity', 'defaultMaxQuantity'), ('description', 'description')):
        if e[k_db] != p[k_f]:
            mism.append((s, k_db))
chk('Existing products: name, description, unit and all quantity fields restated exactly as in the dev database', not mism, f'{len(mism)} differences')
chk('No existing slug reused for a different product', all(prov[s]['existingProduct'] for s in ex_slugs), '')
pieces_ok = all(p['defaultSaleUnit'] in ('PIECE', 'KG') for _, p in allp)
chk('Units used are PIECE or KG only (no L products, no unit not allowed by product-rules)', pieces_ok, '')
photos = [p['photo'] for _, p in allp if p['photo']]
st_ok = all(next(r for r in photo['urls'] if r['url'] == u)['urlValid'] for u in photos)
chk('Every non-null photo URL answered HTTP 200 with an image/* content type and >= 1.5 KB', st_ok, f'{len(photos)} non-null photos')
chk('No photo URL rejected in visual inspection is used', not any(review.get(u, {}).get('verdict', 'accepted') != 'accepted' for u in photos), '')
dupnames = collections.Counter((p['name'].lower(), p.get('brandSlug')) for _, p in allp)
chk('Active names unique per brand (database unique index)', max(dupnames.values()) == 1, '')

# ---- numbers for prose ------------------------------------------------------------------------
per_src_final = collections.Counter()
for s, (pr) in prov.items():
    for m in pr['sources']:
        per_src_final[m['source']] += 1
prod_by_srcset = collections.Counter()
for s, pr in prov.items():
    prod_by_srcset[tuple(sorted({m['source'] for m in pr['sources']}))] += 1
kg = sum(1 for _, p in allp if p['defaultSaleUnit'] == 'KG')
brandless = sum(1 for _, p in allp if not p.get('brandSlug'))
inspected_final = sum(1 for p in photos if review.get(p, {}).get('verdict') == 'accepted')  # photos used that were inspected
nulls = [(s, p) for s, p in allp if not p['photo']]
null_reasons = collections.Counter()
for s, p in nulls:
    pr = prov[p['slug']]
    if p['slug'] in db and not pr.get('sources'):
        null_reasons['existing product with no confident source match (unchanged)'] += 1
    else:
        fb = pr['photo']['fallbacksRejected']
        if not fb:
            null_reasons['no image in the source record(s)'] += 1
        else:
            kinds = {('404' if '404' in f['reason'] else 'visual' if 'visually' in f['reason'] else 'other') for f in fb}
            null_reasons['source image URL returns 404 / invalid' if kinds <= {'404', 'other'} else 'image rejected in visual inspection'] += 1

geant_final = per_src_final['geant']
# ---- write markdown ----------------------------------------------------------------------------
def tbl(rows, header):
    out = ['| ' + ' | '.join(header) + ' |', '|' + '|'.join(['---'] * len(header)) + '|']
    for r in rows:
        out.append('| ' + ' | '.join(str(x) for x in r) + ' |')
    return '\n'.join(out)

C = {c['slug']: c for c in cat['categories']}
CAT_SCOPE = {
 'fruits': 'Fresh fruit (loose by weight or by piece), prepared fresh fruit',
 'legumes': 'Fresh vegetables, herbs, salads (loose or packed)',
 'viandes': 'Beef, veal, lamb, minced meat, merguez, other fresh meat (pork cuts if any)',
 'volaille': 'Chicken, turkey, other poultry and rabbit (fresh cuts and whole birds)',
 'poissons-fruits-de-mer': 'Fish and seafood (fresh, packed, smoked; not canned tuna/sardines)',
 'produits-laitiers': 'Milk, yoghurt, leben/raieb, cream, butter, margarine, eggs, chilled dairy desserts',
 'fromages': 'All cheeses (portions, slices, spreads, grated, cooking cheeses)',
 'charcuterie-traiteur': 'Cold cuts, salami, ham, prepared dishes, ready meals, sandwiches',
 'boulangerie': 'Bread, viennoiserie, pastries from the bakery counter',
 'surgeles': 'Frozen foods, ice cream, ice cubes',
 'epicerie': 'Pantry: pasta, rice, couscous, flour, sugar, oil, vinegar, canned goods, sauces, spices, pulses, dates, dried fruit, baking aids',
 'petit-dejeuner': 'Cereals, jams, honey, spreads, rusks, instant chocolate drinks, and the traditional breakfast items chamia (halva), bsissa and zrir (as Géant files them: Épicerie > Petit déjeuner)',
 'biscuits-gateaux': 'Biscuits, wafers, cakes, madeleines, muffins, packaged pastries',
 'chocolat-confiserie': 'Chocolate, sweets, chewing gum (candies merely filled with chamia stay here)',
 'snacks-aperitif': 'Crisps, puffs, crackers and savoury snacks',
 'boissons': 'Water, soft drinks, juices, nectars, syrups, coffee, tea, infusions, chicory, energy drinks, non-alcoholic beer',
 'produits-traditionnels': 'Traditional Tunisian specialties that are a food type of their own: chamia (halva), bsissa, zrir, assida/mesfouf/droo (sorghum) and zgougou preparations, ground pulse/grain/nut pastes (as Géant groups them: "Chamia, bsissa et zrir" and "Préparations traditionnelles")',
 'viandes-poissons': 'Previous combined category — now empty and archived (see impact report)',
}
rows = []
for slug in [c['slug'] for c in cat['categories']]:
    status = 'existing, kept' if slug in {c['slug'] for c in snap['categories']} else 'new'
    if slug == 'viandes-poissons':
        status = 'existing, **archived** (needs your approval)'
    rows.append((f'`{slug}`', C[slug]['name'], status, CAT_SCOPE[slug], len(C[slug]['products'])))

taxo = f"""# Catalogue v2 — taxonomy and rules

Generated 2026-10-10. Nothing here has been imported. Every rule below is enforced by the importer contract
(`backend/src/catalog/catalog-file.ts`, `catalog-plan.ts`, `products/product-rules.ts`) or is a convention this
phase applied and documented.

## 1. Categories

{tbl(rows, ['Slug', 'Display name', 'Status', 'Scope', 'Products'])}

Decisions applied: `epicerie` kept; `viandes`, `volaille`, `poissons-fruits-de-mer` are separate global categories;
cheese is split out of `produits-laitiers` (one existing product, `fromage-emmental`, moves — listed in the impact report).
Category slugs are permanent identities; names can change later without a new row. Categories carry no description or photo.

## 2. Product identity and slugs

- A product's identity is its **slug**; the importer matches on nothing else. Renames keep the slug.
- The 42 existing slugs are restated unchanged and never reused. A new product whose generated slug would collide gets `-2`, `-3` in deterministic order.
- New slug = `slugify(display name + brand)`; the brand is not repeated when the name already contains it. Max 100 characters.
- **Same product** (merged) = same brand + same normalised wording + same size, across sources. Different flavour, size,
  count or brand = different product. Wording-only look-alikes are listed in `uncertain-matches.json`, never merged.
- Existing product ↔ source record matching is deliberately narrow: brandless **and** the same normalised name. {sum(1 for p in prov.values() if p['existingProduct'] and p['matchedInSources'])} of 42 matched.

## 3. Display names (French)

- Source wording is kept (sentence case, whitespace collapsed, truncation markers removed after reading the full product page).
- Packaged products carry their package size at the end (`Yaourt aromatisé fraise 100 g`, `Eau minérale 1,5 L`) because the
  database requires unique names per brand and sizes are the only honest discriminator. Flavour/variant text from the source is
  kept before the size. Multi-packs are written `3 × 25 g`.
- Nothing is translated or invented. Loose produce keeps its plain name (`Courgette`).
- Original source names, ids and URLs live only in `provenance.json`.

## 4. Brands

- Brand = the manufacturer/brand string of the source, folded by case, accents, apostrophes and spacing
  (`MOULIN D'OR` = `MOULIN DOR` = `MOULIN D OR` → `Moulin d'Or`). Explicit alias: `DELICE` = `DÉLICE DANONE` → `Délice`.
- Display spelling: the most common mixed-case source spelling, else title case with elision rules (`d'`, `l'`).
- Slug = slugify(display name). Brandless (`brandSlug: null`) is valid: loose produce, bakery counter, butcher, fishmonger.
- **Excluded:** any brand or product name containing "Carrefour" (2 Carrefour records dropped). Other brands sold at Carrefour are kept.
- Retailer own-brands are *not* excluded (only Carrefour was): MG own labels `MG J'aime` and `Koll Youm` ({sum(1 for p in prov.values() if p.get('privateLabelOf'))} products, flagged `privateLabelOf: MG` in the provenance). `Tous les jours` ({sum(1 for _, p in allp if p.get('brandSlug') == 'tous-les-jours')} products) appears as a featured house brand on Géant Drive; **unverified** whether it is Géant's own label.
- Brands are never archived or deleted by the importer; a wrong brand can only be renamed or re-pointed. Look-alike brands that were **not** merged are in `brands.json`.

## 5. Units and quantity rules (explicit in the file — nothing left to importer defaults)

Importer constraints: unit ∈ PIECE/KG/L; quantities are integers in pieces / **grams** / mL; KG and L values must be multiples of 10;
caps 1,000 pieces / 100,000 g; `min` and `max` multiples of `step`; `max ≥ min`.
A PIECE product can only ever be sold in PIECE; a KG product can be sold in KG or PIECE.

| Case | Unit | min / step / max | Basis |
|---|---|---|---|
| Packaged product (anything with a stated pack size, bottle, can, box) | PIECE | 1 / 1 / 24 | house default; matches existing packaged products (existing ones keep their own 12–120 maxima) |
| Loose fruit & vegetables | KG | 500 / 100 / 10000 | same as the existing produce products |
| Loose meat, poultry, fish | KG | 500 / 100 / 5000 | same family as existing `daurade`, `poulet-entier` |
| Loose cheese / deli cut | KG | 100 / 50 / 2000 | same as existing `fromage-emmental` |
| Loose pantry (spices, nuts, dried fruit, dates) | KG | 250 / 50 / 5000 (or the source's "Conditionné par N g" as min) | same as existing `dattes`, `olives-vertes` |
| Sold per piece/bunch ("La pièce", "La botte", "Le sachet") | PIECE | 1 / 1 / 24 | source states it is sold by the piece |

{kg} KG products, {N - kg} PIECE products. **No product uses L**: bottles are PIECE, as the existing catalog does.
`L` is only for loose liquids, and none was found.
These are catalog **defaults**. A store's price, unit, quantity rules, stock and availability are untouched and set per StoreProduct.

Evidence for KG: Géant's own wording (`Le KG`, `Conditionné par 500 g/100 g`, loose market items), Carrefour's loose-counter flag
carried over from the earlier conversion, or the Carrefour product page saying "Au poids" / "Au Kg". Where the source gives no sale basis the product is PIECE.

## 6. Categories assignment

Géant Drive sub-category → category map (`tools/taxonomy.py`), then name-based overrides for the meat/poultry/fish/charcuterie/frozen
family (Géant files sausages under "bœuf", frozen escalopes under "hachées"). Carrefour products reuse the earlier conversion's
category, re-split by name. Aziza/MG/OFF products are classified by keyword (`tools/build_candidates.py`, `guess_category`).
Classification is rule-based with an explicit correction layer (`classification-corrections.json`, rules C1–C5, M1–M12); it is **not manually reviewed per product**.

## 7. Out of scope

Non-food (hygiene, cosmetics, cleaning, electronics, kitchenware, baby care, pet food), alcoholic beverages, dietary supplements,
promotional bundles / mixed lots / "gratuit" offers, anything where the name could not be read or classified from the source.
Counts: see `exclusions.json`.
"""
open(O + 'taxonomy-and-rules.md', 'w').write(taxo)

# -------------------------------------------------------------------------------------------------
c = val['counts']
exr = collections.Counter()
for e in st2['excludedPre']:
    exr[(e['source'], e['reason'])] += 1
exrows = [(s, r, n) for (s, r), n in sorted(exr.items(), key=lambda kv: (-kv[1], kv[0]))]
cross = [p for p in st2['products'] if len({m['src'] for m in p['members']}) > 1]
cross_by = collections.Counter(tuple(sorted({m['src'] for m in p['members']})) for p in cross)
samples = [(p['name'], p['brand'] or '—', ' + '.join(f"{m['src']}:{m['srcFullName'][:28]}" for m in p['members'])) for p in cross[:10]]
unc = st2['uncertain']
unc_top = sorted(unc, key=lambda u: -u['similarity'])[:20]
bv = st2['brandVariants'][:30]
val_md = f"""# Catalogue v2 — validation and deduplication report

Generated 2026-10-10. Read-only: no importer run, no database write, no migration, no application code changed.

## 1. Result in one table

{tbl([(n, 'PASS' if ok else '**FAIL**', d) for n, ok, d in checks], ['Check', 'Result', 'Detail'])}

### How the importer contract was checked

`node tools/validate.mjs catalog.v2.json existing_snapshot.json` loads the **compiled importer modules from this working tree**
(`backend/dist/catalog/catalog-file.js` → `parseCatalog`, `catalog-plan.js` → `planCatalog`, built after the sources last changed)
and runs them in-process against a read-only snapshot of the dev database (categories, products, offerings; 0 brands).
No database connection is opened by the validator. `npm run catalog:import -- --dry-run --file seed/catalog-v2/catalog.v2.json`
is the same planner against the live dev database and is the next step for you or me once this is approved.

### Plan the importer would produce (against the dev snapshot)

{tbl([('Brands', c['brands']['created'], c['brands']['updated'], c['brands']['unchanged'], c['brands']['archived']),
      ('Categories', c['categories']['created'], c['categories']['updated'], c['categories']['unchanged'], c['categories']['archived']),
      ('Products', c['products']['created'], c['products']['updated'], c['products']['unchanged'], c['products']['archived'])],
     ['Entity', 'Created', 'Updated', 'Unchanged', 'Archived'])}

Planner warnings ({len(val['warnings'])}):
{chr(10).join('- ' + w for w in val['warnings'])}
- This single warning is expected: it is the explicit, listed archive of `viandes-poissons` (see the impact report).
- The same warning is also a false positive in effect: the offering's product (`escalope-de-poulet`) is moved to `volaille` in the same transaction.

The 13 product updates are listed one by one in `impact-existing.md`; none changes a unit or a quantity field.

## 2. Counts

| | |
|---|---|
| Products in catalog.v2.json | {N} (42 existing + {N - 42} new) |
| Brands | {len(cat['brands'])} (dev database has 0) |
| Brandless products | {brandless} |
| KG / PIECE | {kg} / {N - kg} |
| Categories | {len(cat['categories'])} ({len(cat['categories']) - 7} new, 7 existing, 1 archived) |
| With a photo / null photo | {len(photos)} / {len(nulls)} |

Per category: {', '.join(f'`{s}` {len(C[s]["products"])}' for s in C)}.

## 3. Deduplication

**Exact duplicates merged: {len(cross)} products** that appeared in more than one source, same brand + same size + same normalised wording:
{', '.join(f'{" + ".join(k)} {v}' for k, v in cross_by.most_common())}. Examples:

{tbl(samples, ['Product', 'Brand', 'Merged source records'])}

**Same-source collisions: {len(st2['sameSourceCollisions'])} records not kept.** Same brand, size and wording as another record of the
*same* source but a different record id (e.g. three Tymbark "Boisson au jus 1 L" whose flavour only appears in the photo). They are
not provably identical and the database requires unique names per brand, so only the first record was kept and the others are listed
in `exclusions.json` → `sameSourceCollisions`. These are candidates for a later manual pass.

**Name collisions: {len(st2['nameCollisions'])}** products not created because their display name equals an existing/other brandless product
({', '.join(f'`{n["name"]}`' for n in st2['nameCollisions'])}).

**Uncertain matches (not merged): {len(unc)} pairs** in `uncertain-matches.json` — mostly a size-less Carrefour record vs a sized
Géant/Aziza record of the same brand with similar wording. Highest similarity first:

{tbl([(u['brand'], u['a'], '+'.join(u['aSources']), u['b'], '+'.join(u['bSources']), u['similarity']) for u in unc_top], ['Brand', 'A', 'src', 'B', 'src', 'sim'])}

**Look-alike brands not merged: {len(st2['brandVariants'])}** pairs in `brands.json`. First 30:
{', '.join(f'`{a}` / `{b}`' for a, b in bv)}.

## 4. Exclusions (read from a source, not in the file)

{tbl(exrows, ['Source', 'Reason', 'Records'])}

Plus {sum(gd_unmapped.values())} Géant Drive records in non-food sub-categories (hygiene, make-up, electronics, baby, pet, cleaning…) which
were never candidates (`exclusions.json` → `geantOutOfScopeSubcategories`), and {len(st2['sameSourceCollisions'])} same-source collisions above.

## 5. Source coverage

| Source | How it was read | Raw food-scope records | Records in final products |
|---|---|---|---|
| Géant Drive (Tunis City) | public category pages, robots.txt allows; full names via product pages | {sum(1 for r in gd_raw if (re.search(r'/tunis-city/([^/]+)/', r['url'] or '') or [None, None])[1] in GD_MAP)} (of {len(gd_raw)} crawled) | {per_src_final['geant']} |
| Carrefour Tunisie | existing CSV of 500 rows (not re-crawled); categories from the earlier conversion | 500 | {per_src_final['carrefour']} |
| Aziza | public weekly promo catalogue page rendered in a browser (one week) | 124 food rows (of 262) | {per_src_final['aziza']} |
| MG | public category pages `/15-alimentaire`, `/74-cuisine`… | 57 products | {per_src_final['mg']} |
| Open Food Facts | open API, `countries=tunisia`; **throttled (HTTP 503) after 200 of 3,883 records** | 200 | {per_src_final['off']} |

Records count towards "final products" once per merged source record; a merged product counts in each of its sources.

## 6. Known limitations

- **Open Food Facts was only partly read** (200/3,883) because the API answered 503 repeatedly. Brand/quantity data there is crowd-sourced.
- **Monoprix** (JavaScript shop, 403 to non-browser clients) and **Géant's "hypermarket" site** (flyers only) were not usable; **manufacturer sites** (Délice, Vitalait, Saïda…) were not discoverable by search. No manufacturer catalogue was ingested; manufacturer coverage is via retailer and OFF listings.
- **Aziza** shows one week of promotions, not its range. Aziza and MG name/size are source wording.
- Carrefour rows carry **no pack size**, so they can't be merged with sized rows; {sum(1 for p in prov.values() if any(m['source']=='carrefour' for m in p['sources']) and len(p['sources'])==1)} Carrefour-only products have no size in their name.
- Category assignment is rule-based; misclassifications are expected at the margin (e.g. chamia/bsissa under `chocolat-confiserie`).
- Fresh butcher/fishmonger coverage is thin ({len(C['viandes']['products'])} `viandes`, {len(C['volaille']['products'])} `volaille`, {len(C['poissons-fruits-de-mer']['products'])} `poissons-fruits-de-mer`): sources mostly list packed/frozen items.
- **Size of the catalogue**: {N} products. The owner picker loads the whole catalogue in one request (`GET /owner/catalog/products`); that contract was designed for "a few hundred". Not measured here — see summary.
- Prices were seen in the sources but are **not** in any deliverable.
- Pork products (e.g. bacon/chorizo de porc, jambon de Paris) exist in the Géant range and are included as food; review if undesired.
"""
open(O + 'validation-report.md', 'w').write(val_md)

# -------------------------------------------------------------------------------------------------
summ = photo['summary']
cand = {r['url']: r for r in photo['urls']}
review_in = {u: r for u, r in review.items() if u in cand}
by_src_rev = collections.defaultdict(collections.Counter)
for u, r in review_in.items():
    by_src_rev[r['source']][r['verdict']] += 1
# claims made in the report are checked, not assumed
cand_by_primary = collections.defaultdict(list)
for u, r in cand.items():
    cand_by_primary[r['sources'][0]].append(u)
for src in ('aziza', 'mg', 'off'):
    missing = [u for u in cand_by_primary[src] if cand[u]['urlValid'] and u not in review_in]
    assert not missing, (src, len(missing))
for s_, e_ in [(x, y) for x, y in prov.items() if y['existingProduct'] and y.get('photo', {}).get('url')]:
    assert e_['photo']['visuallyInspected'], s_
chosen_not_inspected = collections.Counter()
for _, p_ in allp:
    if p_['photo'] and p_['slug'] not in db and not prov[p_['slug']]['photo']['visuallyInspected']:
        chosen_not_inspected[prov[p_['slug']]['photo']['source']] += 1
for slug_ in db:
    if prov[slug_].get('photo', {}).get('url') and not prov[slug_]['photo']['visuallyInspected']:
        chosen_not_inspected['existing'] += 1
used_by_src = collections.Counter()
for _, p in allp:
    if p['photo']:
        used_by_src[prov[p['slug']]['photo']['source']] += 1
host_rows = collections.Counter()
for r in photo['urls']:
    host_rows[(urlparse(r['url']).netloc, 'valid' if r['urlValid'] else 'INVALID')] += 1
rej = [(r['n'], r['source'], r['name'][:50], r['verdict'].replace('rejected-', ''), r['reason']) for u, r in review_in.items() if r['verdict'] != 'accepted']
rej.sort()
photo_md = f"""# Catalogue v2 — photo URL validation report

Generated 2026-10-10. Photos are direct third-party URLs stored as plain strings; nothing was downloaded into the project.

## 1. Basic validity — **every** candidate URL

All {summ['uniqueUrls']} distinct candidate URLs (every photo of every source record, not only the chosen one) were requested
(HEAD, falling back to a ranged GET). A URL is "valid" only if the answer is HTTP 200/206, `Content-Type: image/*`, and the size is ≥ 1.5 KB.

{tbl([(h, v, n) for (h, v), n in sorted(host_rows.items())], ['Host', 'Result', 'URLs'])}

- Valid: **{summ['urlValid']}**, invalid: **{summ['urlInvalid']}** (all Géant `cdn.geantdrive.tn` HTTP 404: the product page references an image that no longer exists).
- Invalid URLs are never used; the product falls back to another source's valid photo, or to `null`.
- No placeholder/"no image" clusters were found (the largest identical-size cluster was 3 files, all different products' real photos).
- mg.tn file names are not reliable as a relevance signal: several URLs carry another product's slug but show the right product (and vice-versa could occur). Only visual inspection was used for MG.

## 2. Visual inspection — exactly what was and was not inspected

**{len(review_in)} distinct images were looked at** (contact sheets of 20, numbered, compared with the product name and brand).
What was verified for each: the picture shows the product named (right type; right flavour/variant when the name states one; brand when legible),
is a product photo (not a label scan, back of pack, nutrition table or screenshot), and carries no other shop's watermark.
What was **not** verified: net weight/size printed on the pack, colour accuracy, current packaging design, image resolution beyond "readable".

| Source | Photos in the catalogue's candidate set | Inspected | Accepted | Rejected: wrong | Rejected: approximate |
|---|---|---|---|---|---|
{chr(10).join(f"| {s} | {len(cand_by_primary[s])} | {sum(by_src_rev[s].values())} | {by_src_rev[s]['accepted']} | {by_src_rev[s]['rejected-wrong']} | {by_src_rev[s]['rejected-approximate']} |" for s in ('geant','aziza','carrefour','mg','off'))}

- **Fully inspected populations:** every Aziza photo, every MG photo, every Open Food Facts photo, and every photo placed on one of the 42 existing products.
- **Sampled only:** Géant Drive — {sum(by_src_rev['geant'].values())} of {sum(1 for r in photo['urls'] if 'geant' in r['sources'] and r['urlValid'])} valid URLs (stratified by category, ≥ 4 per category); Carrefour — {sum(by_src_rev['carrefour'].values())} of {sum(1 for r in photo['urls'] if 'carrefour' in r['sources'] and r['urlValid'])} valid URLs (random).
  Géant sample: {by_src_rev['geant']['rejected-wrong']} wrong variant in {sum(by_src_rev['geant'].values())}. Carrefour: {by_src_rev['carrefour']['rejected-wrong']} of {sum(by_src_rev['carrefour'].values())}. These rates are an estimate for the un-inspected remainder, **not** a verification: {chosen_not_inspected['geant']} Géant and {chosen_not_inspected['carrefour']} Carrefour photos used in the catalogue were checked for URL validity only.
- Aziza photos are weakest: {by_src_rev['aziza']['rejected-wrong'] + by_src_rev['aziza']['rejected-approximate']} of {sum(by_src_rev['aziza'].values())} ({100*(by_src_rev['aziza']['rejected-wrong'] + by_src_rev['aziza']['rejected-approximate'])//max(1,sum(by_src_rev['aziza'].values()))} %) were rejected, mostly one shared multi-flavour assortment image reused for several flavours. OFF: {by_src_rev['off']['rejected-wrong']} of {sum(by_src_rev['off'].values())} rejected (label scans, back of pack, blur, shop watermark, brand mismatch) and the accepted ones are crowd-sourced phone photos of uneven quality.
- MG product photos are correct but small (product occupies a fraction of a 1100×1422 canvas); low visual quality, not a correctness issue.

### Rejected after inspection (replaced by another source's photo or `null`)

{tbl([(f"#{n}", s, nm, k, why) for n, s, nm, k, why in rej], ['Item', 'Source', 'Product', 'Verdict', 'Reason'])}

## 3. Photos actually used

| | Products |
|---|---|
| With a photo | {len(photos)} |
| – inspected and accepted | {inspected_final} |
| – URL valid, **not visually inspected** | {len(photos) - inspected_final} |
| `null` photo | {len(nulls)} |

By source of the photo used: {', '.join(f'{k} {v}' for k, v in used_by_src.most_common())}.

Why `null` ({len(nulls)}): {'; '.join(f'{k}: {v}' for k, v in null_reasons.most_common())}.

Existing products that gain a photo: 9 (all visually inspected and accepted; listed in `impact-existing.md`). The other 33 stay `null`.

## 4. Caveats for using these URLs

- Hot-linked images from `cdn.geantdrive.tn`, `back.carrefour.tn`, `btoc.azizacdn.com`, `mg.tn`, `images.openfoodfacts.org` can change or disappear; the product is then shown without image (the apps already have a placeholder).
- Open Food Facts images are licensed CC BY-SA (attribution to Open Food Facts contributors); Carrefour/Géant/Aziza/MG images belong to the retailers/brands. Accepted for this portfolio project per your decision.
- Per-URL results, HTTP status, content type, size and the visual verdict are in `photo-validation.json`.
"""
open(O + 'photo-validation.md', 'w').write(photo_md)

# -------------------------------------------------------------------------------------------------
before_off = {4: 'baguette', 2: 'cafe-moulu-250g', 3: 'croissant', 1: 'escalope-de-poulet'}
rows = []
for s, e in db.items():
    p = next(x for _, x in allp if x['slug'] == s)
    newcat = next(c['slug'] for c in cat['categories'] if any(x['slug'] == s for x in c['products']))
    ch = []
    if newcat != e['category']:
        ch.append(f"category {e['category']} → **{newcat}**")
    if (p['photo'] or None) != (e['photo'] or None):
        ch.append('photo null → ' + ('`' + urlparse(p['photo']).netloc + '`'))
    rows.append((f'`{s}`', e['name'], e['offerings'], f"{e['defaultSaleUnit']} {e['defaultMinQuantity']}/{e['defaultQuantityStep']}/{e['defaultMaxQuantity']}", '; '.join(ch) or 'unchanged'))
with_changes = [r for r in rows if r[4] != 'unchanged']
imp_md = f"""# Catalogue v2 — impact on existing records

Generated 2026-10-10. Against the dev database `grocery_db` (read-only snapshot; the test database is empty).
Importer plan (computed in-process): **13 products updated, 29 unchanged, 1 category archived, 0 products archived, 0 deleted**.
Nothing is written until you approve and run the import.

## 1. Needs your approval

| Item | Proposed | Why | Effect |
|---|---|---|---|
| Archive category `viandes-poissons` | `archived: true` after its 4 products leave it | You replaced the combined taxonomy with three categories | Empty category disappears from the owner picker and from customer listings. It holds the live offering of `escalope-de-poulet`, which moves to `volaille` in the **same** import transaction, so the offering is never orphaned. Importer prints a warning for it (expected). |
| `escalope-de-poulet` → `volaille` | category move | chicken | StoreProduct 1 (store 17) keeps price 19 000 millimes, KG 500/250/5000, stock untracked, availability. It is listed under "Volaille" instead of "Viandes et poissons". |
| `poulet-entier` → `volaille`, `viande-hachee-boeuf` → `viandes`, `daurade` → `poissons-fruits-de-mer` | category move | split taxonomy | No offerings. |
| `fromage-emmental` → `fromages` | category move | new `fromages` category | No offerings. |

**No default unit and no default quantity field of any existing product changes.** No existing product is archived.
(Carrefour's data says `laitue` and `persil` should be KG; the file keeps both as PIECE, the current values.)

## 2. All 42 existing products — before / after

{tbl(rows, ['Slug', 'Name', 'Offerings', 'Unit & min/step/max (unchanged)', 'Change'])}

Names and descriptions (all null) are restated exactly. Photo is the only field that changes (null → URL, 9 products, all visually inspected)
besides the 5 category moves above. {len(with_changes)} of 42 products have any change.

## 3. Categories

| Slug | Before | After |
|---|---|---|
| fruits, legumes, produits-laitiers, boulangerie, epicerie, boissons | active, name unchanged | active, name unchanged (importer: unchanged), now also contain new products |
| viandes-poissons | active, 4 products | **archived**, 0 active products |
| viandes, volaille, poissons-fruits-de-mer, fromages, charcuterie-traiteur, surgeles, petit-dejeuner, biscuits-gateaux, chocolat-confiserie, snacks-aperitif | — | new |

## 4. Brands

Before: 0 rows. After: {len(cat['brands'])} created. Brands are never archived; no existing product has a brand, and none is given one.

## 5. StoreProducts (4 active offerings, store 17) — **not touched**

| Id | Product | Unit | Price (millimes) | min/step/max | Stock | Catalog-side change |
|---|---|---|---|---|---|---|
| 1 | `baguette` | PIECE | 200 | 3 / 1 / 20 | tracked 37 | none |
| 2 | `cafe-moulu-250g` | PIECE | 5 000 | 1 / 1 / 12 | tracked 27 | none |
| 3 | `croissant` | PIECE | 1 200 | 1 / 1 / 24 | untracked | none |
| 4 | `escalope-de-poulet` | KG | 19 000 | 500 / 250 / 5000 | untracked | category display only; catalog photo added |

The importer has no code path that writes StoreProduct. Product `defaultSaleUnit` of these four is unchanged, so the
`allowedSaleUnits` constraint cannot be violated. A customer's view gains the product photo for #4 (Carrefour image, inspected).

## 6. Orders and history

4 orders, 8 order items, 16 status events. `OrderItem` stores `productNameSnapshot`, `saleUnitSnapshot`, `unitPriceMillimes`,
`quantity`, and points at StoreProduct (ON DELETE RESTRICT). None of this changes: no product or StoreProduct is deleted, renamed,
re-slugged or re-united. Historical orders keep their snapshots even if a catalogue name changes later.

## 7. Rollback

The import is one transaction (all or nothing). Rolling back after it has run = re-importing the previous `seed/catalog.json`
would **not** undo created rows (the importer never deletes). Safest: take a dump of `grocery_db` immediately before the real import.
"""
open(O + 'impact-existing.md', 'w').write(imp_md)
print('reports written')
print('null reasons', dict(null_reasons))
print([ (n, ok) for n, ok, d in checks if not ok])
