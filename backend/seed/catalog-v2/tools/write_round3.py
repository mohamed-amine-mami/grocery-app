import json,re,collections,sys,os
sys.path.insert(0,os.path.dirname(__file__))
from textlib import fold
S='/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
O='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
cat=json.load(open(O+'catalog.v2.json')); prov={p['slug']:p for p in json.load(open(O+'provenance.json'))['products']}
st2=json.load(open(S+'out/stage2.json')); val=json.load(open(S+'out/validate.json'))
chg=json.load(open(O+'changes-since-rev2.json')); rev=json.load(open(S+'out/photo_review.json'))
db={p['slug']:p for p in json.load(open(S+'src/existing_db_products.json'))}
ex=json.load(open(O+'exclusions.json'))
allp={p['slug']:(c['slug'],p) for c in cat['categories'] for p in c['products']}
N=len(allp); brands={b['slug']:b['name'] for b in cat['brands']}
def tbl(rows,h):
    o=['| '+' | '.join(h)+' |','|'+'|'.join(['---']*len(h))+'|']
    for r in rows: o.append('| '+' | '.join(str(x).replace('|','/') for x in r)+' |')
    return '\n'.join(o)
# ---- sidecars
cf=st2['cfDecisions']
json.dump(dict(note='Every Carrefour record whose CSV row had no pack size, reviewed individually against its own product page on carrefour.tn (the page description gives the pack, e.g. "Le pot de 70g", or "Au poids"). decision: merged = exact duplicate of a record from another source; retained = distinct product kept; excluded = insufficiently distinguishable from a sized sibling.',
    records=cf),open(O+'carrefour-sizeless-review.json','w'),ensure_ascii=False,indent=1)
cfc=collections.Counter(x['decision'] for x in cf)
cfrows=[(x['sid'],x['name'],x['brand'] or '—',x['pageDescription'] or '—',x['decision'],x['reason']) for x in cf]
open(O+'carrefour-sizeless-review.md','w').write(f"""# Carrefour size-less records — individual review

The Carrefour CSV has no pack size. Each of the **{len(cf)}** records without one was opened on its own product page (carrefour.tn; the page description states the pack, e.g. “Le pot de 70g”, or “Au poids” for loose items) and decided individually.

| Decision | Records |
|---|---|
{chr(10).join(f'| {k} | {v} |' for k,v in cfc.items())}

Rules (applied identically, evidence in the table): page gives a size → the product gets it in its name and is compared with sized siblings; identical brand+size+wording to a sibling of another source → **merged** as an exact duplicate; page says "Au poids/Au kg" → **retained** as a loose, weight-sold product (KG); no size on the page and wording identical to a sized sibling → **excluded** (indistinguishable); otherwise **retained** as a distinct product.

{tbl(cfrows,['SKU','Record','Brand','Page description','Decision','Evidence / reason'])}
""")
# brand merges audit
audit=collections.defaultdict(list)
for a in st2['brandMergeAudit']: audit[a['canonical']].append(a)
bm=[]
for m in st2['brandMerges']:
    recs=audit.get(m['canonical'],[])
    bm.append(dict(canonical=m['canonical'],sourceSpellings=m['spellings'],evidence=m['evidence'],records=[dict(source=r['source'],sourceId=r['sid'],rawBrand=r['rawBrand'],line=r['line']) for r in recs]))
json.dump(dict(note='Brands merged in round 3. A pair was merged only when pack photos (or label artwork) of both spellings print the same brand. Nothing else was merged; look-alikes kept apart are listed in brand-review.md.',merges=bm),open(O+'brand-merges.json','w'),ensure_ascii=False,indent=1)
pm=json.load(open(S+'work/pair_merges.json'))
json.dump(dict(note='Same-product merges verified pair by pair on the pack photos (round 3). a/b are source-record ids (source:id).',applied=st2['packPhotoMerges'],candidates=pm),open(O+'pair-merges.json','w'),ensure_ascii=False,indent=1)
vo=json.load(open(S+'out/variant_overrides.json'))
json.dump(dict(note='Same-source look-alikes whose pack photos show a different flavour/edition/pack type; the variant read from the photo was added to the name. Other look-alikes stay excluded (see exclusions.json).',records=vo),open(O+'variant-restores.json','w'),ensure_ascii=False,indent=1)
# exclusions: add cf excluded + pork
ex['carrefourSizelessExcluded']=[x for x in cf if x['decision']=='excluded']
json.dump(ex,open(O+'exclusions.json','w'),ensure_ascii=False,indent=1)

# ---- numbers
pork_keep=[s for s,(c,p) in allp.items() if re.search(r'\bporc\b|jambon de paris',fold(p['name'])) ]
pork_excl=[e for e in ex['excludedRecords'] if 'pork-family' in e['reason']]
tlj=[s for s,(c,p) in allp.items() if p.get('brandSlug')=='tous-les-jours']
trad=[(s,p) for s,(c,p) in allp.items() if c=='produits-traditionnels']
tcounts=collections.Counter()
for s,p in trad:
    n=fold(p['name']); t=('chamia' if re.search(r'chamia|helva|halwa',n) else 'bsissa' if 'bsissa' in n else 'droo/sorgho' if re.search(r'droo|sorgho',n) else 'assida' if 'assida' in n else 'zgougou' if 'zgougou' in n else 'mesfouf' if 'mesfouf' in n else 'zrir' if 'zrir' in n else 'ground pulse/grain/nut paste & other')
    tcounts[t]+=1
c=val['counts']
unc=st2['uncertain']; uc=collections.Counter(u['reason'] for u in unc)
coll=st2['sameSourceCollisions']
moves={'escalope-de-poulet':'volaille','poulet-entier':'volaille','viande-hachee-boeuf':'viandes','daurade':'poissons-fruits-de-mer','fromage-emmental':'fromages'}
summ=chg['summary']
rn=open(O+'review-round3.md','w')
rn.write(f"""# Catalogue v2 — review round 3 (decisions applied)

Generated 2026-10-10. **Not imported.** No database write, backup, migration, CLI import or application-code change. The previous revision is kept in `history/rev2/` for the exact diff (`changes-since-rev2.json`).

## 0. Result

| | rev 2 | **rev 3** |
|---|---|---|
| Products | 5,801 | **{N:,}** (42 existing + {N-42:,} new) |
| Brands | 671 | **{len(brands)}** |
| Categories | 17 | **{len(cat['categories'])}** (7 existing + 11 new; `viandes-poissons` archived) |
| Photos (URL) / `null` | 5,591 / 210 | {sum(1 for s,(c,p) in allp.items() if p['photo']):,} / {sum(1 for s,(c,p) in allp.items() if not p['photo'])} |

**Importer, in-process against the read-only dev snapshot:** `parseCatalog` {val['parseErrorCount']} errors; `planCatalog` {len(val['planErrors'])} errors, {len(val['warnings'])} warning (the listed `viandes-poissons` archive). Plan: brands created {c['brands']['created']}; categories created {c['categories']['created']} / unchanged {c['categories']['unchanged']} / archived {c['categories']['archived']}; products created {c['products']['created']:,} / updated {c['products']['updated']} / unchanged {c['products']['unchanged']} / archived {c['products']['archived']}.

## 1. Catalog scale — recorded, nothing trimmed
**Import blocker recorded:** the 5,{N-5000:03d}-product catalogue must not be imported until the owner picker and catalogue API are made scale-appropriate (separate step). The candidate keeps full coverage; no product was dropped to fit the current picker (`capacity-assessment.md` has the evidence). Product count went *down* only through exact-duplicate merges and identifiable exclusions listed below.

## 2. Tous les jours — retained provisionally, ownership unverified
{len(tlj)} products kept under the source's brand name `Tous les jours`. **Ownership is marked `unverified`** in the sidecar: `provenance.json` → `brandOwnership` on each product, and `brands.json` → `ownership`. No claim that it belongs to Géant; no database field added. Koll Youm is marked `unverified (observed MG-exclusive)`; MG J'aime `verified private label` (MG's own site and press).

## 3. Pork
- **Retained (9, confirmed pork by source text and/or Géant's *Porc* sub-category):** {', '.join('`'+s+'`' for s in pork_keep)}.
- **Excluded (4, species unknown):**

{tbl([(e['sourceId'],e['name'],e['brand'],e['reason']) for e in pork_excl],['Géant id','Name','Brand','Evidence'])}

They can be re-added if the species is established (e.g. from the pack).

## 4. Brand spelling variants — merged only with pack evidence
{len(st2['brandMerges'])} merges, each backed by pack photos of both spellings printing the same brand (audit: `brand-merges.json`, which lists every source record re-pointed):

{tbl([(m['canonical'],', '.join(m['spellings']),m['evidence']) for m in st2['brandMerges']],['Canonical brand','Merged spellings','Evidence'])}

**Not merged** (evidence absent or contradicting): Daily / Daily'n (different logos on pack), Dorra / El Dorra / Durra (different logos and product types), Gazelle / La Gazelle (unlabelled tub), El Jawhara / Jawhara (labels unreadable), Spiga / Spipa (packs print different names), Weepo / Weepop's (different pack names), plus every pair classed "distinct" or "product line" in `brand-review.md`. The Souani lines (National, Calife, Vieux Calife) became brand `Souani` with the line moved into the product name (`Camembert National 250 g`, …), so the three camembert products stay separate.
Because slugs embed the brand, the products under the merged spellings have **new slugs** (none was live); the old→new mapping is in `changes-since-rev2.json`.

## 5. Carrefour size-less records — reviewed individually
`carrefour-sizeless-review.md/.json`. The CSV had no pack size; each of the {len(cf)} size-less records was opened on its Carrefour product page, which states the pack ("Le pot de 70g", "Au poids" …).
{tbl(cfc.items(),['Decision','Records'])}
- **{cfc['merged']} were exact duplicates** of Géant/Aziza/OFF records once their size was known (merged, all sources kept in provenance).
- **{cfc['retained']} retained** as distinct products (own pack size from the page; or sold by weight).
- **{cfc['excluded']} excluded**: no size on the page and wording identical to a sized sibling — LBM *Biscuit P'tit matin spéculoos*, YAB *Crème dessert Plaisir zgougou*, Hazem *Sirop de menthe*, Délice *Yaourt nature*.
Evidence side effect: **"Au poids" items are now KG products** (cut cheeses, fresh turkey, dried-fruit mixes) instead of PIECE.

## 6. `produits-traditionnels` — evaluated and adopted
**Evaluation.** Géant itself groups these foods in two dedicated sub-categories (*Chamia, bsissa et zrir* and *Préparations traditionnelles*), they are not confectionery, not generic breakfast cereal, and not a staple: chamia/zrir are halva-type spreads, bsissa/droo/assida/mesfouf are roasted-grain or pulse preparations with their own preparation. The importer needs no change (a category is just a slug + name; `produits-traditionnels` is unique and not an existing slug); no existing product belongs to it, so nothing existing moves. Adopted.

**Membership ({len(trad)} products):** {', '.join(f'{k} {v}' for k,v in tcounts.most_common())}.
**Deliberately left out** (kept where a shopper expects them): pasta and dough types (hlalem, nouasser, mhamsa, malsouka, mlewi, samsa, brik sheets) → `epicerie`; baking mixes and *Préparation … droo/cake* → `epicerie`; baklawa, ghrayba, kaak, loukoum → `biscuits-gateaux` / `chocolat-confiserie`; tahina → `epicerie`; candies *filled with* chamia → `chocolat-confiserie`; chamia ice cream → `surgeles`; sesame/date "pops" → `snacks-aperitif`; harissa and spice blends → `epicerie`.
**Category changes:** {summ['recategorised']} products changed category versus rev 2 (almost all `petit-dejeuner`/`epicerie` → `produits-traditionnels`; list in `changes-since-rev2.json` → `recategorised`). Product names and identities are unchanged.

## 7. Category moves and the `viandes-poissons` archive — re-verified on the final candidate
{tbl([(f'`{s}`',db[s]['name'],db[s]['category'],allp[s][0],db[s]['offerings'],'unchanged' if (allp[s][1]['defaultSaleUnit'],allp[s][1]['defaultMinQuantity'],allp[s][1]['defaultQuantityStep'],allp[s][1]['defaultMaxQuantity'])==(db[s]['defaultSaleUnit'],db[s]['defaultMinQuantity'],db[s]['defaultQuantityStep'],db[s]['defaultMaxQuantity']) else 'CHANGED') for s in moves],['Slug','Old category','New category','Offerings','Unit & quantities'])}
- Products left in `viandes-poissons`: **{sum(1 for s,(c,p) in allp.items() if c=='viandes-poissons')}**; new products assigned to it: **0**. The archive is applied in the same importer transaction as the moves.
- StoreProduct 4 (price 19000, KG, 500/250/5000, untracked, available) and the 8 OrderItems are untouched (the plan's 13 product updates change only `photo` and `categoryId`).
- No existing product has a unit or quantity change; none is archived.

## 8. Remaining uncertain pairs and same-source look-alikes
**Uncertain pairs ({len(unc)} left, was 342 in rev 2).** {', '.join(f'{k}: {v}' for k,v in uc.items())}. Every same-size pair with wording similarity ≥ 0.7 (about 80 pairs over two review passes) was decided on the pack photos: **{len(st2['packPhotoMerges'])} merged** (`pair-merges.json`); the rest are *different flavours/types that must stay separate* (e.g. Vitalait lait demi-écrémé vs écrémé 0 %, Maestro noir vs noisettes, Ovolina Junior vs jaune orange, Bonna moutarde vs à l'ancienne, El Manar thym vs citron, Lune de Miel doux vs acacia) or have photos that do not settle it (left separate, listed). Lower-similarity pairs are flavour/line variants and were not individually inspected.
**Same-source look-alikes.** 70 groups (79 records) in rev 2. By pack photo: **30 groups were different products** (different flavour, edition or pack type) → {len(vo)-0} records named with the variant read from the pack (`variant-restores.json`); {len(coll)} records remain excluded because the photos show the *same* product, are too alike to name, or one has no image (`exclusions.json`). No look-alike was merged silently; one (Confiture La Fruitière orange) was left out because the flavour is not legible.

## 9. Exact changes since rev 2 (`changes-since-rev2.json`)
| Change | Products |
|---|---|
| Unchanged (same slug, name, category) | {summ['unchanged']:,} |
| Renamed / re-slugged (size from Carrefour page, brand merge, variant name, Souani line) | {summ['renamed']} |
| Moved category only | {summ['recategorised']} |
| Merged into another product (exact duplicate) | {summ['merged']} groups |
| Removed | {summ['removed']} (4 pork species-unknown, 4 Carrefour indistinguishable, 6 look-alikes, 1 jam whose flavour is not legible) |
| Added | {summ['added']} (variants restored from look-alikes) |

## 10. Unresolved
- **Scale** (import blocker, separate step).
- 4 pork-family products excluded until species is known; `Tous les jours` ownership unverified.
- 159 uncertain pairs not individually inspected (low similarity) and {len(coll)} excluded look-alikes: listed, not resolved.
- ~{len([1 for s,(c,p) in allp.items() if p['photo'] and rev.get(p['photo'],{}).get('verdict')!='accepted'])} photos are URL-valid but not visually verified (see `photo-validation.md`).
- Rule-based classification is not reviewed product by product.
""")
rn.close()
print(N,len(brands),cfc,summ,len(pork_keep),len(tlj),len(trad),tcounts)
