import json, re, collections, gzip, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from textlib import *
from urllib.parse import urlparse
S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
O = '/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
cat = json.load(open(O + 'catalog.v2.json'))
prov = {p['slug']: p for p in json.load(open(O + 'provenance.json'))['products']}
st2 = json.load(open(S + 'out/stage2.json'))
val = json.load(open(S + 'out/validate.json'))
db = {p['slug']: p for p in json.load(open(S + 'src/existing_db_products.json'))}
pork = json.load(open(S + 'out/pork_candidates.json'))
review = json.load(open(S + 'out/photo_review.json'))
photo = json.load(open(O + 'photo-validation.json'))
snap = json.load(open(S + 'src/existing_snapshot.json'))
dup = json.load(open(O + 'duplicate-review.json'))
chamia = json.load(open(O + 'chamia-bsissa-review.json'))
corr = json.load(open(O + 'classification-corrections.json'))
allp = {p['slug']: (c['slug'], p) for c in cat['categories'] for p in c['products']}
N = len(allp)
def tbl(rows, header):
    out = ['| ' + ' | '.join(header) + ' |', '|' + '|'.join(['---'] * len(header)) + '|']
    for r in rows: out.append('| ' + ' | '.join(str(x).replace('|', '/') for x in r) + ' |')
    return '\n'.join(out)

# ---- item 1 ------------------------------------------------------------------------------------
MOVES = {'escalope-de-poulet': 'volaille', 'poulet-entier': 'volaille', 'viande-hachee-boeuf': 'viandes', 'daurade': 'poissons-fruits-de-mer', 'fromage-emmental': 'fromages'}
mv_rows = [(f'`{s}`', db[s]['name'], db[s]['category'], allp[s][0], db[s]['offerings'], f"{db[s]['defaultSaleUnit']} {db[s]['defaultMinQuantity']}/{db[s]['defaultQuantityStep']}/{db[s]['defaultMaxQuantity']}",
            'unchanged' if (allp[s][1]['defaultSaleUnit'], allp[s][1]['defaultMinQuantity'], allp[s][1]['defaultQuantityStep'], allp[s][1]['defaultMaxQuantity']) == (db[s]['defaultSaleUnit'], db[s]['defaultMinQuantity'], db[s]['defaultQuantityStep'], db[s]['defaultMaxQuantity']) else 'CHANGED') for s in MOVES]
assert all(r[-1] == 'unchanged' and r[3] == MOVES[r[0].strip('`')] for r in mv_rows)
still_in_old = [s for s, (c, p) in allp.items() if c == 'viandes-poissons']
assert not still_in_old
cheese_total = len([1 for s, (c, p) in allp.items() if c == 'fromages'])
# ---- item 2 ------------------------------------------------------------------------------------
brands = {b['slug']: b['name'] for b in cat['brands']}
rows = []
for s, (c, p) in allp.items():
    rows.append(dict(id=10000 + len(rows), slug=p['slug'], name=p['name'], description=None, photo=p['photo'], defaultSaleUnit=p['defaultSaleUnit'],
                     allowedSaleUnits=['KG', 'PIECE'] if p['defaultSaleUnit'] == 'KG' else ['PIECE'], defaultMinQuantity=p['defaultMinQuantity'],
                     defaultQuantityStep=p['defaultQuantityStep'], defaultMaxQuantity=p['defaultMaxQuantity'], category=dict(id=1, slug=c, name=c),
                     brand=dict(id=1, slug=p['brandSlug'], name=brands[p['brandSlug']]) if p['brandSlug'] else None, inMyStore=False, storeProductId=None, storeProductArchived=False))
raw = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode()
raw_kb, gz_kb = round(len(raw) / 1024), round(len(gzip.compress(raw)) / 1024)
cap_md = f"""# Catalogue v2 — product volume and UI capacity (code evidence, nothing changed)

Candidate size: **{N:,} products** (today's dev catalogue: 42). Evidence below is from the working tree on 2026-10-10.

## What is returned and how big it is

| Question | Answer | Evidence |
|---|---|---|
| Products in one response | **All {N:,} active products**, in one array, no limit/offset/cursor/search parameter | `backend/src/catalog/catalog.service.ts` `products()` loads every active `Product` with `category` and `brand` included, filters in memory, sorts, returns. The only query parameter is `categoryId` (`dto/list-catalog-products.query.ts`). |
| Payload size | **≈ {raw_kb:,} KB** of JSON (≈ {raw_kb/1024:.1f} MB); **≈ {gz_kb} KB** if gzip were applied | Measured by serialising the exact `CatalogProductEntity` shape for the candidate ({len(raw):,} bytes, ≈ {len(raw)//N} bytes/product). `backend/src/main.ts` installs **no compression middleware**, so the uncompressed size goes over the wire. |
| Are images in the response | **No bytes, only URL strings** (`photo`, avg ≈ 76 chars). Images are fetched separately by the client when a widget shows them | `catalog.entity.ts` `photo: string \\| null`; `mobile/lib/ui/core/widgets/product_image.dart` uses `Image.network` with `cacheWidth`, placeholder and `errorBuilder`. |
| Does the picker show images | **No.** `_ProductRow` in `catalog_picker_view.dart` is text only (name, brand, category · unit, status icon). Images appear in the owner's *store* catalogue, the editor and Quick Add — which scale with the store's own offerings, not the global catalogue | `catalog_view.dart:273`, `quick_add_sheet.dart:125`, `store_product_editor_view.dart:382`, `customer/views/store_catalog_view.dart:506` are the only `ProductImage` uses. |
| Is the picker list built in memory | **Yes, fully, and non-lazily.** `CatalogRepository.products()` `jsonDecode`s the whole body on the UI isolate (no `compute`), maps to `List<CatalogItem>`; `CatalogPickerViewModel.visibleItems` filters the whole list on every build; the view builds `ListView(children: [Card(Column([for item in visible ...]))])` — a **non-builder** list, so *every* visible row is instantiated and laid out, scrolled or not | `catalog_picker_view_model.dart:48`, `catalog_picker_view.dart:215-243`. There is no `ListView.builder` / `SliverList` anywhere in `mobile/lib/ui`. |
| Server-side search / pagination / filtering | **None** beyond `categoryId`. Search is a local, accent-insensitive substring match (`SearchText.matches`) | `catalog.service.ts`, `search_text.dart` |
| Other per-request work | `categories()` loads *all* products just to count them; the sort uses `localeCompare('fr')` per comparison | `catalog.service.ts:17-36`; measured 20 ms for {N:,} rows in Node |

## Measured / estimated cost

| Item | Result | Basis |
|---|---|---|
| Local search filter, per keystroke | **≈ 33 ms** for {N:,} items in a non-release Dart VM (JIT) | `dart run` micro-benchmark of the real `SearchText.matches` over name+brand+category strings of the candidate (JIT, desktop; a mid-range phone in release mode is likely the same order of magnitude, not measured) |
| JSON encode+decode of the whole catalogue | ≈ 26 ms (desktop VM) | same benchmark, 1.9 MB file |
| Widgets instantiated when the picker opens | ≈ {N:,} rows × roughly 15–20 widgets ≈ **90,000–115,000 widgets**, all built in one frame, rebuilt (whole `_Browser`) on every keystroke | counted from `_ProductRow` source; **not measured on a device** |
| Server response time | not measured — would need the data in the database, which this phase must not do | the in-memory sort is 20 ms; the ORM load of {N:,} rows with two includes is untested |

## Likely problems at {N:,} products

1. **Picker jank / possible out-of-memory** on mid and low-end phones: opening and every keystroke rebuild ~100k widgets. This is the real blocker, and it is in the client list construction, not the data volume.
2. **{raw_kb/1024:.1f} MB response, uncompressed**, on every open and every pull-to-refresh (and after any failed add, the picker reloads the whole catalogue).
3. **Category chips**: 16 active categories; fine.
4. Existing smoke tests and the "a few hundred products" comment in the picker assume today's size.
5. Customers are **not** affected: `GET /stores/:id/products` returns only that store's own offerings.

## Recommendation

A scale change **is necessary before importing this volume** (or before the owner picker is used with it). In order of effect/cost:

1. Client: `ListView.builder` (lazy rows) + debounce the search + do the `jsonDecode` off the UI isolate. Removes problem 1 with no API change.
2. Server: gzip, and a `limit/offset` (or cursor) + `q` + `categoryId` contract for `GET /owner/catalog/products` so search and "already in my store" flags are computed on a page. Removes problem 2 and scales past the current catalogue.
3. Alternatively keep the contract and **stage the import** (e.g. a few hundred curated products first); the file supports that without changes since the importer leaves absent products unchanged.

Not implemented in this phase, per your instruction.
"""
open(O + 'capacity-assessment.md', 'w').write(cap_md)

# ---- item 3 brands ------------------------------------------------------------------------------
def B(name): return next((s for s, n in brands.items() if fold(n) == fold(name)), None)
PROBABLE = [("Nablia", "Neblia"), ("Tifanny", "Tiffanny"), ("Seniatna", "Senietna"), ("Furketta", "Furkitta"), ("Jardin d'Emma", "Jardins d'Emma"),
            ("Royaume des Abeilles", "Royaumes des Abeilles"), ("Tijen", "Tijen Water"), ("Gazelle", "La Gazelle"), ("Le Petit Paris", "Petit Paris"),
            ("Weepo", "Weepop's"), ("Lovege", "Lovego"), ("Lebanese Factory", "The Lebanese Factory"), ("Dorra", "El Dorra"), ("Daily", "Daily'n"),
            ("Raoua", "Raoua Chani"), ("Tanit", "Tanit le Jardin"), ("Olina", "Frideal Olina"), ("Al Jazia", "El Jazia"), ("Spiga", "Spipa"), ("Reflet", "Reflets de Tunisie"),
            ("Calife Souani", "Vieux Calife Souani"), ("Calife Souani", "Souani")]
LINES = ["Dolce Vitalait", "Milkana Delice", "Tarti Frais Delice", "Delice Deli'o", "Délice Végétal", "Goldina Plus", "Campi Plus", "Fromy Plus", "Candy Papillon", "Caramello Papillon",
         "Jellino Papillon", "Jellino Mini Papillon", "Golden Chips", "Golden Coffee", "Golden River", "Golden Sweets", "Golden Twister", "Max Golden", "Break Kids", "Roll Break Lago", "Party Lago",
         "Poker Lago", "Primo Lingot", "Chahia Tayba", "Aura Maestro", "Adoro Moulin d'Or", "Happy Full", "Happy's", "Bugles/chips Up", "Chips Up+finger Snax", "Madame Loïk Paysan Breton",
         "Rondele President", "Ovita El Mazraa", "Grissini Cerealis", "Plaisir Y'ab", "Dolce Banana", "Dolce Coffee", "Up Biskart", "Vitupti"]
DISTINCT = [("Safia", "Sadia"), ("Safia", "Safaa"), ("Safia", "Safir"), ("Milka", "Milkana"), ("Melina", "Melita"), ("Major", "Mayor"), ("Crispo", "Crispy"), ("Cristal", "Cristaline"),
            ("Darna", "Darta"), ("Olina", "Ovolina"), ("Grano", "Granoro"), ("Ledoux", "Leroux"), ("Carthage", "Sanabel Carthage"), ("Dorra", "Durra"), ("El Rayen", "Rayen"),
            ("Epices et Saveurs", "Saveurs"), ("Délice", "Delices de la Mer"), ("Vitup", "Vitupti"), ("Al Jazia", "Al Jazira"), ("Biskart", "Up Biskart")]
bv = st2['brandVariants']
def cls(a, b):
    for x, y in PROBABLE:
        if {fold(a), fold(b)} == {fold(x), fold(y)}: return 'probable spelling / naming variant of one brand'
    for x, y in DISTINCT:
        if {fold(a), fold(b)} == {fold(x), fold(y)}: return 'distinct brands with similar names'
    if fold(a) in map(fold, LINES) or fold(b) in map(fold, LINES): return 'product-line / sub-brand of the other (source gave it as the brand)'
    return 'uncertain — not classified'
brand_rows = [(a, b, cls(a, b)) for a, b in bv]
brand_cls = collections.Counter(r[2] for r in brand_rows)
tlj = [(s, p) for s, (c, p) in allp.items() if p.get('brandSlug') == 'tous-les-jours']
tlj_src = collections.Counter(x['source'] for s, p in tlj for x in prov[s]['sources'])
tlj_cat = collections.Counter(allp[s][0] for s, p in tlj)
mgj = [s for s, (c, p) in allp.items() if p.get('brandSlug') == 'mg-j-aime']; kol = [s for s, (c, p) in allp.items() if p.get('brandSlug') == 'koll-youm']
cfc = [s for s, (c, p) in allp.items() if 'carrefour' in fold(p['name']) or 'carrefour' in fold(brands.get(p.get('brandSlug'), ''))]
# same product under probable-variant brands (potential duplicates)
brand_md = f"""# Catalogue v2 — brand verification

## Decisions applied
- **Carrefour:** 0 products and 0 brands contain "Carrefour" in the file ({len(cfc)} found by name/brand scan). The 2 Carrefour-branded CSV rows (`Café soluble aggloméré`, `Café soluble lyophilisé`, brand `CARREFOUR`) stay excluded. Brands Carrefour merely *sells* are kept (e.g. Délice, Vitalait, Saïda, Sanabel).
- **No brand merges were applied** in this round: nothing below was merged automatically.

## MG J'aime and Koll Youm — kept, evidence
| Brand | Products | Evidence |
|---|---|---|
| `MG J'aime` | {len(mgj)} | mg.tn (Magasin Général's own site) sells it throughout its food range and publishes press items titled "MG J'aime élue marque de distributeur de l'année 2026 …"; the same fact is reported by African Manager ("MG J'aime élue marque de distributeur de l'année 2026 en Tunisie pour la 3ᵉ fois"). → **verified retailer private label of Magasin Général.** |
| `Koll Youm` | {len(kol)} | Sold only on mg.tn, in the same product listings and carousels as `MG J'aime`, with the same "Kollection" textile range. **No page I could reach states ownership explicitly**, and a web search found no third-party mention. → treated as an MG-exclusive label by observation, **not independently verified.** |
Both are genuine brands that exist in the source (not invented); the file carries no ownership field, so no attribution is asserted. The provenance records `privateLabelOf: MG` as an observation only.

## "Tous les jours" — ownership not verifiable
Evidence collected: the brand has {len(tlj)} products, all from Géant Drive (sources: {dict(tlj_src)}), across {dict(tlj_cat)}. It appears on Géant Drive as a brand page (`/tunis-city/brand/2036-tous-les-jours`, listed prominently in the shop header) and **nowhere else** (not in the Carrefour CSV, Aziza's catalogue, MG, or the Open Food Facts records I could read — OFF throttled, so that check is weak). The Géant Drive page has no description. A web search found no source that says it is Géant's own label (or anyone's). A search result mentioned Magasin Général, not Géant, as the Tunisian distributor-brand leader.
- **Conclusion:** it is a real brand string supplied by a retailer, but its owner is **unknown**. Retailer-exclusive + prominent placement makes "house label" *likely* but that is inference.
- **Safest treatment (applied):** keep the brand under the name the source gives, with no ownership claim in the catalog (the provenance does not label it a private label). Alternative if you prefer zero risk: drop the {len(tlj)} products or set `brandSlug: null` for them — your call.
- Affected: {', '.join('`' + s + '`' for s, p in tlj[:8])} … ({len(tlj)} total, full list: filter `brandSlug == "tous-les-jours"` in `catalog.v2.json`).

## Brand duplicates and spelling variants (rechecked)
{len(bv)} look-alike pairs (was 90 before the merges and exclusions of this round). Classification, **none merged**:

{tbl(sorted(brand_cls.items()), ['Class', 'Pairs'])}

### Probable spelling / naming variants (candidates for a merge, awaiting your decision)
{tbl([r for r in brand_rows if r[2].startswith('probable')], ['Brand A', 'Brand B', 'Class'])}

Each pair above is the same *kind* of product from the same retailer with a near-identical name; it remains unproven without the packs. If merged, products with identical name+size under the two spellings would collide on the unique `(name, brand)` index — the planner would flag them.

### Distinct brands with similar names (keep apart)
{tbl([r for r in brand_rows if r[2].startswith('distinct')], ['Brand A', 'Brand B', 'Class'])}

### Product lines / sub-brands given as the brand by the source ({sum(1 for r in brand_rows if r[2].startswith('product-line'))} pairs)
Kept as the source states them (e.g. `Dolce Vitalait` vs `Vitalait`, `Milkana Delice` vs `Délice`). The full list with product counts and all raw spellings is in `brands.json`.

### Unclassified ({sum(1 for r in brand_rows if r[2].startswith('uncertain'))} pairs)
{', '.join(f'`{a}` / `{b}`' for a, b, c in brand_rows if c.startswith('uncertain')) or 'none'}
"""
open(O + 'brand-review.md', 'w').write(brand_md)

# ---- item 5 pork & chamia ------------------------------------------------------------------------
def pk_row(r):
    slug, name, brand, c, ev, srcs = r
    s0 = srcs[0]
    return (f'`{slug}`', name, brand or '—', c, '; '.join(ev) or '—', f'{s0[0]} #{s0[1]} “{s0[2]}”' + (f' ({s0[3]})' if s0[3] else ''))
tc = collections.Counter((r['type'], r['finalCategory']) for r in chamia)
pork_md = f"""# Catalogue v2 — pork products, chamia and bsissa

## 1. Pork products

Method: every product whose source name/description contains porc, bacon, lardons, chorizo, serrano, jambon (de Paris/cru…), saucisson sec, pepperoni, etc. was pulled with its source evidence.
The catalog has **no schema field for ingredients/diet**, so this is a review list; nothing was removed or flagged in the file.

### Confirmed pork ({len(pork['explicit'])}) — source says "porc" and/or files it under Géant's *Porc* sub-category
{tbl([pk_row(r) for r in pork['explicit']], ['Slug', 'Name', 'Brand', 'Category', 'Evidence', 'First source record'])}

`Jambon de Paris` (Jean Caby) never says "porc" in the text; its evidence is the sub-category alone (Jambon de Paris is conventionally pork) — **medium confidence**.

### Species not stated — not shown to be pork ({len(pork['ambiguous'])})
{tbl([pk_row(r) for r in pork['ambiguous']], ['Slug', 'Name', 'Brand', 'Category', 'Evidence', 'First source record'])}

These are Mliha / Chahia / El Mazraa lines; those brands also sell beef and turkey charcuterie (elsewhere in the catalog `Chorizo de bœuf`, `Bacon de bœuf`, `Salami de dinde` exist). Without the pack, the species is **unknown**; I did not assume pork. Kept in `charcuterie-traiteur`.

### Treatment options
(a) keep all ({len(pork['explicit'])} confirmed + {len(pork['ambiguous'])} unknown) as food — current state; (b) exclude the {len(pork['explicit'])} confirmed; (c) exclude confirmed + unknown. No technical difference: the importer treats them as any product.

## 2. Chamia, bsissa, zrir — review

How Tunisian retailers file them (evidence): **Géant Drive files them under *Épicerie › Petit déjeuner › "Chamia, bsissa et zrir"*** (breadcrumb of the product page). Carrefour's CSV spreads chamia-type items over unrelated departments (traditional pastry, candy, semolina/flour, baking preparations), so it is no guide; Aziza and MG list it as grocery. They are traditional breakfast/pantry foods — halva-type sweet spread, roasted-grain flour mix, sesame/almond paste — not confectionery in the candy sense.

Decision (applied, rule `C5`): chamia/bsissa/zrir → **`petit-dejeuner`** ("Petit déjeuner", which now says so in its scope). Individual review of the {len(chamia)} products touching these words (full per-item list: `chamia-bsissa-review.json`):

{tbl([(t, c, n) for (t, c), n in sorted(tc.items())], ['Food type', 'Final category', 'Products'])}

Exceptions made item by item:
- `Bonbons fourrés chamia` (Papillon) — a *candy* filled with chamia → stays `chocolat-confiserie` (rule C1).
- `Glace chamia Gold mythic` — ice cream → `surgeles`.
- `Tahina` ×3 (La Gazelle, Le Moulin, Papillon) — plain sesame paste → `epicerie` (rule C3).
- `Ghrayba hommes` — shortbread biscuit → `biscuits-gateaux` (C2).
- `… pops` (Kartago date/sesame energy bites, 5 products) → `snacks-aperitif` (C4).
- All other Géant sub-category items (chamia ×{sum(n for (t, c), n in tc.items() if t.startswith('chamia') and c == 'petit-dejeuner')}, bsissa ×{sum(n for (t, c), n in tc.items() if t == 'bsissa')}, zrir ×{sum(n for (t, c), n in tc.items() if t == 'zrir')}) → `petit-dejeuner`.
Open point: if you would rather have a dedicated `produits-traditionnels` category (they are 179 items now in `petit-dejeuner`, which has {len(next(c for c in cat['categories'] if c['slug']=='petit-dejeuner')['products'])} products), that is a one-line taxonomy change; I did not add a category unasked.
"""
open(O + 'pork-and-traditional-products.md', 'w').write(pork_md)

# ---- item 6 duplicates ---------------------------------------------------------------------------
dm = dup['descriptorMergesApplied']
hi = sorted([u for u in dup['sameBrandSameSizeSimilarWording'] if u['similarity'] >= 0.8], key=lambda u: -u['similarity'])
lo = [u for u in dup['sameBrandSameSizeSimilarWording'] if u['similarity'] < 0.8]
sl = sorted([u for u in dup['sameWordingSizeUnknown'] if u['similarity'] >= 0.75], key=lambda u: -u['similarity'])
coll = dup['sameSourceCollisions']
cc = collections.Counter((r['brand'] or '—') for r in coll)
corr_by = collections.defaultdict(list)
for c in corr: corr_by[c['rule']].append(c)
dup_md = f"""# Catalogue v2 — duplicates and classification quality (round 2)

Priority used: **identical name + brand + size** first, then same photo, then wording look-alikes.

## A. Exact duplicates — merged ({len(dm)})
Rule: same brand, same package size, different sources, identical wording after removing pure descriptor words (`canette`, `naturelle`, `boisson`, `gazeuse`, `au jus`, `the box`, …) and tolerating 1-letter typos/plurals. Merged records keep every source in `provenance.json`; the name/photo come from the highest-priority source.

{tbl([(d['brand'], d['kept'], d['mergedAway'], '+'.join(d['sources'])) for d in dm], ['Brand', 'Kept name', 'Merged-away name', 'Sources'])}

Also checked: **identical photo URLs across products: 0**; **byte-identical image files shared by several products: 14 groups / 28 products** — all inspected: 8 are size variants of the same product (Danup 160/260 g, MAD chips 16/75 g, saupe sizes, entremets), 6 are generic stock photos shared by different brands (chickpeas NFE/Rima, ground coffee Ben Yedder, ham Mliha/Chahia, nuggets El Mazraa/Mliha). None is evidence of a duplicate product; the generic ones are flagged as "generic photo" and kept (they show the right food).

## B. Same brand + same size + similar wording, **not** merged ({len(dup['sameBrandSameSizeSimilarWording'])} pairs)
Highest risk first (similarity ≥ 0.8: {len(hi)} pairs):

{tbl([(u['brand'], u['a'], '+'.join(u['aSources']), u['b'], '+'.join(u['bSources']), u['similarity']) for u in hi[:25]], ['Brand', 'A', 'src', 'B', 'src', 'sim'])}

These need a human glance: some are surely one product (e.g. `Crème fraîche 15 cl` / `Crème fraîche Chef 15 cl` — Chef is the line), others are different (`Chocolat noir extra fin 90 g` vs `… aux noisettes 90 g`).

### Variants that **must remain separate** (same brand and size, different flavour/type — {len(lo)} pairs in the lower-similarity band)
Examples: Diva jus ananas / orange / pomme 1 L; Moulin d'Or pain de mie complet / nature 21 tr.; Natilait Misto céréales–fruits des bois / –fruits exotiques; Délice yaourt aromatisé banane / yaourt brassé banane; Délice lait demi-écrémé / écrémé / sans lactose 1 L; Sanabel Fell n°2 / n°2.5; Maestro chocolat noir / aux noisettes. They look similar to a string matcher and are different products.

## C. Same wording, size unknown on one side ({len(dup['sameWordingSizeUnknown'])} pairs; {sum(1 for u in dup['sameWordingSizeUnknown'] if set(u['aSources']+u['bSources'])=={'carrefour','geant'})} are Carrefour-without-size vs Géant-with-size)
The Carrefour CSV carries no pack size, so these can't be merged or told apart without the packs. Highest similarity:

{tbl([(u['brand'], u['a'], '+'.join(u['aSources']), u['b'], '+'.join(u['bSources']), u['similarity']) for u in sl[:15]], ['Brand', 'A', 'src', 'B', 'src', 'sim'])}

Recommendation (not applied): if you want a tighter catalogue, drop the Carrefour size-less record whenever a sized same-brand sibling with ≥ 0.75 wording similarity exists — about {len([u for u in dup['sameWordingSizeUnknown'] if u['similarity']>=0.75])} records. Needs your approval because it removes products.

## D. Same name and size under several brand spellings
`Camembert 250 g` exists under **Calife Souani / Vieux Calife Souani / National Souani**: three distinct Géant records (product ids 25805, 25804, 25803) with three different photos → **kept as three products** (brand strings differ and the photos differ). `Margarine 200 g` / `400 g` under `Goldina` and `Goldina Plus`: distinct records and photos, kept. Details: `brand-review.md`.

## E. Same-source collisions — {len(coll)} records not kept
Same brand, size and wording, different record id, from one source. They cannot be told apart from the text (e.g. 3 Tymbark "Boisson au jus 1 L" differ only on the pack). Listed in `duplicate-review.json` → `sameSourceCollisions`; top brands: {', '.join(f'{b} ×{n}' for b, n in cc.most_common(8))}. Candidates for a later flavour-from-photo pass.

## F. Rule-based classification mistakes: found and corrected ({len(corr)} products)
The review found the classes below (found in the visual sheets or by a second name-based classifier). Corrections were applied as explicit rules, never to the 42 existing products; the list is `classification-corrections.json`.

{tbl([(r.split(' ')[0], ' '.join(r.split(' ')[1:]), len(v), '; '.join(x['name'] for x in v[:3])) for r, v in sorted(corr_by.items())], ['Rule', 'What', 'Products', 'Examples'])}

A disagreement scan between the main classifier and an independent name classifier flagged ~1,200 products, but ~1,100 of them are false alarms (a flavour word such as *fraise* in a biscuit, or *poulet* in a stock cube). **Residual suspected errors I did not correct** (small, listed so they are not hidden): `Banana chips` (epicerie vs snacks); `Barre de céréales…` / `Barre protéinée` in `petit-dejeuner` or `biscuits-gateaux` (arguably snacks); salami/ham de dinde under `charcuterie-traiteur` (correct: cold cuts, not fresh poultry); `Chausson aux pommes` in boulangerie (fine). Because no per-product manual review was done, assume a residual classification error rate of a few percent outside the categories I inspected visually.

## G. Change log of this round (catalog changes, enumerated)
| Change | Count |
|---|---|
| Products removed: promotional "Lot …" bundles (Géant) | 10 |
| Products removed by descriptor-merge (kept in provenance) | {len(dm)} |
| Category corrections (rules C1–C5, M1–M12) | {len(corr)} |
| Photos removed (visual inspection, other-retailer logo, identity unconfirmable) | 5 in this round (+ the 38 of round 1) |
| Brands added/removed | −1 (one merged-away product's brand spelling no longer used) → {len(cat['brands'])} brands |
| Products | 5,824 → **{N:,}** |
"""
open(O + 'duplicates-and-classification.md', 'w').write(dup_md)
print('ok', N, raw_kb, gz_kb)
