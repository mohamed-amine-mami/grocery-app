# Catalogue v2 — review round 3 (decisions applied)

> **Superseded in part by Rev 3.1 — see `review-round4.md`.** This file records Rev 3 (5,702 products). Review round 4 merged 17 more confirmed duplicates (5,685 products). The merge breakdown and the removed/added arithmetic below were corrected in round 4; numbers that changed in Rev 3.1 are listed in `changes-since-rev3.json`.

Generated 2026-10-10. **Not imported.** No database write, backup, migration, CLI import or application-code change. The previous revision is kept in `history/rev2/` for the exact diff (`changes-since-rev2.json`).

## 0. Result

| | rev 2 | **rev 3** |
|---|---|---|
| Products | 5,801 | **5,702** (42 existing + 5,660 new) |
| Brands | 671 | **654** |
| Categories | 17 | **18** (7 existing + 11 new; `viandes-poissons` archived) |
| Photos (URL) / `null` | 5,591 / 210 | 5,494 / 208 |
| KG / PIECE | 324 / 5,477 | **344 / 5,358** |

**Importer, in-process against the read-only dev snapshot:** `parseCatalog` 0 errors; `planCatalog` 0 errors, 1 warning (the listed `viandes-poissons` archive). Plan: brands created 654; categories created 11 / unchanged 6 / archived 1; products created 5,660 / updated 13 / unchanged 29 / archived 0.

## 1. Catalog scale — recorded, nothing trimmed
**Import blocker recorded:** the 5,702-product catalogue must not be imported until the owner picker and catalogue API are made scale-appropriate (separate step). The candidate keeps full coverage; no product was dropped to fit the current picker (`capacity-assessment.md` has the evidence). Product count went *down* only through exact-duplicate merges and identifiable exclusions listed below.

## 2. Tous les jours — retained provisionally, ownership unverified
55 products kept under the source's brand name `Tous les jours`. **Ownership is marked `unverified`** in the sidecar: `provenance.json` → `brandOwnership` on each product, and `brands.json` → `ownership`. No claim that it belongs to Géant; no database field added. Koll Youm is marked `unverified (observed MG-exclusive)`; MG J'aime `verified private label` (MG's own site and press).

## 3. Pork
- **Retained (9, confirmed pork by source text and/or Géant's *Porc* sub-category):** `bacon-fume-de-porc-100-g-bastides`, `chorizo-de-porc-80-g-bastides`, `jambon-de-paris-180-g-4-tranches-jean-caby`, `jambon-serrano-de-porc-100-g-bastides`, `lardons-de-porc-160-g-bastides`, `saucisson-sec-de-porc-au-noix-80-g-bastides`, `saucisson-sec-de-porc-au-roquefort-80-g-bastides`, `saucisson-sec-de-porc-nature-80-g-bastides`, `saucisson-sec-enrobe-poivre-de-porc-80-g-bastides`.
- **Excluded (4, species unknown):**

| Géant id | Name | Brand | Evidence |
|---|---|---|---|
| 89168 | Chorizo | MLIHA | pork-family charcuterie whose species (pork vs beef/turkey) cannot be established from the source |
| 139025 | Salami pepperoni | CHAHIA | pork-family charcuterie whose species (pork vs beef/turkey) cannot be established from the source |
| 35958 | Chorizo | MLIHA | pork-family charcuterie whose species (pork vs beef/turkey) cannot be established from the source |
| 33442 | Salami pepperoni | EL MAZRAA | pork-family charcuterie whose species (pork vs beef/turkey) cannot be established from the source |

They can be re-added if the species is established (e.g. from the pack).

## 4. Brand spelling variants — merged only with pack evidence
15 merges, each backed by pack photos of both spellings printing the same brand (audit: `brand-merges.json`, which lists every source record re-pointed):

| Canonical brand | Merged spellings | Evidence |
|---|---|---|
| Furketta | Furkitta | Packs of both records print the same logo "Furketta" (harissa berbère / tradition 190 g appear under both spellings) |
| Les Jardins d'Emma | Jardin d'Emma, Jardins d'Emma | Cans of both records print "Les Jardins d'Emma" |
| Le Petit Paris | Petit Paris | Cans and jars of the "Petit Paris" records print "Le Petit Paris" |
| Olina | Frideal Olina | Oil bottles of both records print the Olina logo; "Fridéal" is the product line on the label |
| Lovege | Lovego | Cartons of both records print "Lovege" |
| Neblia | Nablia | Cans of both records print "Neblia" (harissa / hrous) |
| Raoua | Raoua Chani | Can of "Raoua Chani" prints the Raoua logo with "Chani" as the flavour; the product name already says "chani" |
| Reflets de Tunisie | Reflet | Jars/bags of both records print "Reflets de Tunisie" |
| Royaume des Abeilles | Royaumes des Abeilles | Honey jars of both records carry identical label artwork (label text too small to read; spelling follows the majority form) |
| Seniatna | Senietna | Boxes of both records print "Seniatna" |
| Tanit le Jardin | Tanit | Cans of both records print "Tanit le Jardin" |
| Tiffany | Tifanny, Tiffanny | Bottles of both spellings print "Tiffany" |
| Tijen | Tijen Water | Bottles of both records carry the identical "tijen" label |
| Aljazia | Al Jazia, El Jazia | Tins of both records print the same "Aljazia" logo |
| Souani | National Souani, Calife Souani, Vieux Calife Souani | Packs print the SOUANI mark with the line name (National / Calife / Vieux Calife); the line is moved into the product name |

**Not merged** (evidence absent or contradicting): Daily / Daily'n (different logos on pack), Dorra / El Dorra / Durra (different logos and product types), Gazelle / La Gazelle (unlabelled tub), El Jawhara / Jawhara (labels unreadable), Spiga / Spipa (packs print different names), Weepo / Weepop's (different pack names), plus every pair classed "distinct" or "product line" in `brand-review.md`. The Souani lines (National, Calife, Vieux Calife) became brand `Souani` with the line moved into the product name (`Camembert National 250 g`, …), so the three camembert products stay separate.
Because slugs embed the brand, the products under the merged spellings have **new slugs** (none was live); the old→new mapping is in `changes-since-rev2.json`.

## 5. Carrefour size-less records — reviewed individually
`carrefour-sizeless-review.md/.json`. The CSV had no pack size; each of the 414 size-less records was opened on its Carrefour product page, which states the pack ("Le pot de 70g", "Au poids" …).
| Decision | Records |
|---|---|
| merged | 96 |
| retained | 314 |
| excluded | 4 |
- **96 were exact duplicates** of Géant/Aziza/OFF records once their size was known (merged, all sources kept in provenance).
- **314 retained** as distinct products (own pack size from the page; or sold by weight).
- **4 excluded**: no size on the page and wording identical to a sized sibling — LBM *Biscuit P'tit matin spéculoos*, YAB *Crème dessert Plaisir zgougou*, Hazem *Sirop de menthe*, Délice *Yaourt nature*.
Evidence side effect: **"Au poids" items are now KG products** (cut cheeses, fresh turkey, dried-fruit mixes) instead of PIECE.

## 6. `produits-traditionnels` — evaluated and adopted
**Evaluation.** Géant itself groups these foods in two dedicated sub-categories (*Chamia, bsissa et zrir* and *Préparations traditionnelles*), they are not confectionery, not generic breakfast cereal, and not a staple: chamia/zrir are halva-type spreads, bsissa/droo/assida/mesfouf are roasted-grain or pulse preparations with their own preparation. The importer needs no change (a category is just a slug + name; `produits-traditionnels` is unique and not an existing slug); no existing product belongs to it, so nothing existing moves. Adopted.

**Membership (212 products):** chamia 136, bsissa 31, droo/sorgho 15, ground pulse/grain/nut paste & other 15, assida 7, mesfouf 4, zgougou 3, zrir 1.
**Deliberately left out** (kept where a shopper expects them): pasta and dough types (hlalem, nouasser, mhamsa, malsouka, mlewi, samsa, brik sheets) → `epicerie`; baking mixes and *Préparation … droo/cake* → `epicerie`; baklawa, ghrayba, kaak, loukoum → `biscuits-gateaux` / `chocolat-confiserie`; tahina → `epicerie`; candies *filled with* chamia → `chocolat-confiserie`; chamia ice cream → `surgeles`; sesame/date "pops" → `snacks-aperitif`; harissa and spice blends → `epicerie`.
**Category changes:** 205 products changed category versus rev 2 (almost all `petit-dejeuner`/`epicerie` → `produits-traditionnels`; list in `changes-since-rev2.json` → `recategorised`). Product names and identities are unchanged.

## 7. Category moves and the `viandes-poissons` archive — re-verified on the final candidate
| Slug | Name | Old category | New category | Offerings | Unit & quantities |
|---|---|---|---|---|---|
| `escalope-de-poulet` | Escalope de poulet | viandes-poissons | volaille | 1 | unchanged |
| `poulet-entier` | Poulet entier | viandes-poissons | volaille | 0 | unchanged |
| `viande-hachee-boeuf` | Viande hachée de bœuf | viandes-poissons | viandes | 0 | unchanged |
| `daurade` | Daurade | viandes-poissons | poissons-fruits-de-mer | 0 | unchanged |
| `fromage-emmental` | Fromage emmental | produits-laitiers | fromages | 0 | unchanged |
- Products left in `viandes-poissons`: **0**; new products assigned to it: **0**. The archive is applied in the same importer transaction as the moves.
- StoreProduct 4 (price 19000, KG, 500/250/5000, untracked, available) and the 8 OrderItems are untouched (the plan's 13 product updates change only `photo` and `categoryId`).
- No existing product has a unit or quantity change; none is archived.

## 8. Remaining uncertain pairs and same-source look-alikes
**Uncertain pairs (159 left, was 342 in rev 2).** same brand; same size, similar wording: 130, same brand; size unknown on one side: 29. Every same-size pair with wording similarity ≥ 0.7 (about 80 pairs over two review passes) was decided on the pack photos: **56 merged** (`pair-merges.json`); the rest are *different flavours/types that must stay separate* (e.g. Vitalait lait demi-écrémé vs écrémé 0 %, Maestro noir vs noisettes, Ovolina Junior vs jaune orange, Bonna moutarde vs à l'ancienne, El Manar thym vs citron, Lune de Miel doux vs acacia) or have photos that do not settle it (left separate, listed). Lower-similarity pairs are flavour/line variants and were not individually inspected.
**Same-source look-alikes.** 70 groups (79 records) in rev 2. By pack photo: **30 groups were different products** (different flavour, edition or pack type) → 65 records named with the variant read from the pack (`variant-restores.json`); 55 records remain excluded because the photos show the *same* product, are too alike to name, or one has no image (`exclusions.json`). No look-alike was merged silently; one (Confiture La Fruitière orange) was left out because the flavour is not legible.

## 9. Exact changes since rev 2 (`changes-since-rev2.json`) — corrected in round 4
Rev 2 had 5,801 products; Rev 3 has 5,702. The per-cause categories are **not** additive; the count closes as follows (record-level, from the provenance sidecars):

| Change | Count | Notes |
|---|---|---|
| **Merge groups** | **113** | 227 Rev 2 products became 113 products: net **−114** |
| Removed (no counterpart in Rev 3) | **15** | 4 pork species unknown, 4 Carrefour indistinguishable, 6 look-alikes, 1 jam with illegible flavour |
| Added (no Rev 2 parent) | **30** | variants restored from look-alikes |
| Renamed / re-slugged | 310 | size from the Carrefour page, brand merge, variant name, Souani line (of the products not in a merge group) |
| Category only | 205 | almost all → `produits-traditionnels` |
| Unchanged (same slug, name, category) | 5,135 | |

**Closing arithmetic:** 5,801 − 114 (merges) − 15 (removed) + 30 (added) = **5,702**.
One slug string, `tortillas-de-farine-complete-360-g-deli-sun`, appears in both the removed and the added list: a variant restored in round 3 re-uses the slug of a removed look-alike record; they are two different source records, so the lists do not net.

**Why the merge causes are not additive.** The earlier text read "96 Carrefour + 29 descriptor + 56 pack-photo", which sums to 181 and cannot be compared with 113 groups: the 29 descriptor merges were already applied in Rev 2, a group can have several causes, and 96 counted Carrefour records rather than groups. Each of the 113 groups is now assigned to exactly one primary cause: **95** Carrefour pack size read from the product page (96 Carrefour records fall in these groups), **17** pack-photo pair merges (56 pairs in total; 55 fall in groups that also have a Carrefour record or another pair), **1** descriptor-only. Overlapping per-cause counts (not additive): Carrefour 95, pack-photo pair 55, brand merge 4, descriptor 1.

## 10. Unresolved
- **Scale** (import blocker, separate step).
- 4 pork-family products excluded until species is known; `Tous les jours` ownership unverified.
- 159 uncertain pairs not individually inspected (low similarity) and 55 excluded look-alikes: listed, not resolved.
- ~4737 photos are URL-valid but not visually verified (see `photo-validation.md`).
- Rule-based classification is not reviewed product by product.
