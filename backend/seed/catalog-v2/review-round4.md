# Catalogue v2 — review round 4 (Rev 3.1)

Generated 2026-10-10. **Not imported.** No database write, backup, migration, CLI dry-run or application-code change. Rev 3 is preserved in `history/rev3/` (catalog, provenance, pair-merges, uncertain-matches, duplicate-review, changes-since-rev2); Rev 2 stays in `history/rev2/`.

Scope of this round (as requested): correct the documentation inconsistencies, decide the 28 likely-duplicate pairs, update the review files and change report, re-validate, and re-confirm the protection of existing data. No source was added and nothing was scraped; the only network use was re-downloading 58 already-selected product pictures for the side-by-side review.

## 1. Result

| | Rev 3 | **Rev 3.1** |
|---|---|---|
| Products | 5,702 | **5,685** (42 existing + 5,643 new) |
| Brands | 654 | 654 |
| Categories | 18 (7 existing + 11 new, `viandes-poissons` archived) | 18 (unchanged) |
| KG / PIECE | 344 / 5,358 | **344 / 5,341** |
| Photos (URL) / `null` | 5,494 / 208 | 5,478 / 207 |
| Visually verified photos used / URL-valid only | 757 / 4,737 | 752 / 4,726 |
| Uncertain pairs left | 159 | **143** |
| Importer plan: products created / updated / unchanged / archived | 5,660 / 13 / 29 / 0 | **5,643 / 13 / 29 / 0** |

Per category (Rev 3.1): `fruits` 19, `legumes` 67, `produits-laitiers` 345, `boulangerie` 132, `viandes-poissons` 0, `epicerie` 1,978, `boissons` 628, `viandes` 18, `volaille` 50, `poissons-fruits-de-mer` 88, `fromages` 255, `charcuterie-traiteur` 126, `surgeles` 245, `produits-traditionnels` 212, `petit-dejeuner` 450, `biscuits-gateaux` 525, `chocolat-confiserie` 286, `snacks-aperitif` 261.

## 2. Documentation corrections

1. **KG / PIECE.** The authoritative counts, re-counted from `catalog.v2.json`, are KG 344 and PIECE 5,358 for Rev 3 (5,341 for Rev 3.1). The figure "331 / 5,371" given in the round-3 chat message was wrong; no file ever contained it.
2. **Merge breakdown no longer additive.** The old text "96 + 29 + 56" (181) was compared with 113 merge groups. The 29 descriptor merges were already applied in Rev 2, a group can have several causes, and 96 counted Carrefour records rather than groups. `changes-since-rev2.json` now carries a `reconciliation` block with an exclusive partition (one primary cause per group, sums to the group count) and, separately, the overlapping per-cause counts. For Rev 3: 113 groups (227 products → 113) = 95 Carrefour page size + 17 pack-photo pair + 1 descriptor. For Rev 3.1: 130 groups (261 products → 130) = 104 + 25 + 1.
3. **Removed / added arithmetic.** The lists of 15 removed and 30 added are gross; they do not net. One slug string (`tortillas-de-farine-complete-360-g-deli-sun`) appears in both because a restored variant re-uses the slug of a removed look-alike, but they are different source records. Closing equation, from the provenance sidecars at record level: Rev 3: 5,801 − 114 (net of 113 merge groups) − 15 + 30 = **5,702**; Rev 3.1: 5,801 − 131 (net of 130 groups) − 15 + 30 = **5,685**. Stored in `changes-since-rev2.json` → `reconciliation` and evaluating `true`. (An intermediate draft of this correction netted 14/29; that was wrong and is not in any file.)
4. **Table header.** The §7 table of `review-round3.md` had a 5-column header over 6-column rows (the `Name` column was missing); fixed.
5. Round-3 and current-state reports (`SUMMARY.md`, `validation-report.md`, `photo-validation.md`, `taxonomy-and-rules.md`, `impact-existing.md`, `capacity-assessment.md`) carry the Rev 3.1 numbers. `review-round3.md` stays the record of Rev 3 and has a pointer banner. The capacity measurements were taken on 5,702 products and are left as measured (0.3 % smaller now).

## 3. The 28 likely-duplicate pairs

Method: both retailers' pictures for each pair were viewed side by side on contact sheets (the Vitalait butter pack was enlarged to read the label), together with the source name, size and sale unit. A pair was merged only where the packs print the same product, brand, variant and size and the sale format is the same. Different flavours, sizes, formulations, packaging (jar vs pouch, sachet vs tub, promo or edition packs) and sale format (loose KG vs packed PIECE) were kept apart. Full per-pair records: `duplicate-review-round4.json`.

**17 merged**

| # | Brand | Pair | Kept as | Evidence |
|---|---|---|---|---|
| 2 | Mama Mia | Pain de mie nature 14 tranches ↔ Pain de mie naturel 14 tranches | `Pain de mie nature 14 tranches` | Both packs are the Mama Mia 'Pain de mie Nature' bag, same 14-slice format. |
| 9 | Daily'n | Cake Grand Mère marbré 700 g ↔ Cake marbré 700 g | `Cake Grand Mère marbré 700 g` | Both are the Daily'n marbled loaf cake in the same wrapper (chocolate/vanilla marbling, Daily'n band), 700 g; Carrefour calls it 'Grand Mère', Géant 'Cake'. |
| 10 | Daily'n | Cake marbré slice DAYLIN 40 g ↔ Slice Marbré 40 g | `Cake marbré slice 40 g` | Both packs read 'Slice – Recette Grand-Mère – chocolat vanille' (Daily'n 40 g); only the wrapper print generation differs. |
| 26 | Délice | Lait demi-écrémé UHT 1 L ↔ Lait UHT 1/2 écrémé 1 L | `Lait demi-écrémé UHT 1 L` | Carrefour/OFF pack reads 'Demi-écrémé' (Délice UHT 1 L); the Géant record names it '1/2 écrémé' 1 L. The Géant carton art does not show the variant, so the variant rests on the two source names. |
| 41 | Tropico | Boisson au jus cocktail de fruits 1 L ↔ Boisson cocktail 1 L | `Boisson au jus cocktail de fruits 1 L` | Both cartons read 'Tropico – cocktail de fruits – multivitamine', 1 L. |
| 44 | Redbull | Boisson énergétique 25 cl ↔ Boisson énergétique Red Bull 25 cl | `Boisson énergétique 25 cl` | Both are the standard Red Bull 25 cl can. |
| 73 | Natilait | Mon dessert chocolat 100 g ↔ Crème dessert chocolat 100 g | `Mon dessert chocolat 100 g` | Both packs are the Natilait 'mon Dessert' chocolate cup (Géant cup reads 'Dessert Chocolat'), 100 g; Aziza's picture is the same cup in a set. |
| 75 | Natilait | Mon dessert vanille 100 g ↔ Crème dessert vanille 100 g | `Mon dessert vanille 100 g` | Géant cup reads 'mon Dessert Vanille' (Natilait, 100 g); Aziza names it 'Mon dessert vanille'. |
| 84 | L'Epi d'Or | Farine pâtissière 1 kg ↔ Farine Pâtissière L'épi d'or 1 kg | `Farine pâtissière 1 kg` | Both packs are the L'Epi d'Or 'Farine pâtissière' 1 kg bag. |
| 86 | Sicam | Harissa 135 g ↔ Harissa du Cap Bon 135 g | `Harissa du Cap Bon 135 g` | Both cans read 'SICAM – Harissa du Cap Bon – 135 g'. |
| 108 | Souani | Fromage camembert Tomme de Tebourba 280 g ↔ Tomme de TEBOURBA 280 g | `Tomme de Tebourba 280 g` | Both are the Souani 'Tomme de Tebourba' round (red label, 280 g); 'camembert' in the Carrefour name is not on the pack. |
| 112 | Majeste | Fromage 100% mozzarella 250 g ↔ Mozzarella 250 g | `Fromage 100% mozzarella 250 g` | Both packs are the Majesté 'Fromage Mozzarella' 250 g block. |
| 117 | Majeste | Fromage rapé 4 Fromages Rap'cheez 500 g ↔ Râpé 4 fromages 500 g | `Fromage rapé 4 Fromages Rap'cheez 500 g` | Both bags read 'Majesté – Rap'cheez – 4 fromages', 500 g. |
| 121 | Vitalait | Beurre 200 g ↔ Beurre extra fin 200 g | `Beurre extra fin 200 g` | Géant pack, enlarged, reads 'Vitalait – Beurre extra fin – 200 g'; the OFF pack reads 'Vitalait – Beurre extra fin'. |
| 142 | YAB | Crème dessert chocolat liégeois 12 cl ↔ Liégeois chocolat 12 cl | `Crème dessert chocolat liégeois 12 cl` | Both cups read 'YAB – Plaisir Liégeois – goût chocolat', 12 cl (older vs current print). |
| 150 | Goldina | Margarine 100 g ↔ Margarine tartine et cuisson 100 g | `Margarine tartine et cuisson 100 g` | Both tubs read 'Goldina – Tartine & Cuisson – riche en vitamines A et E', 100 g. |
| 158 | Cerealis | Pop corn sucré 75 g ↔ Pop-corn Sweet 75 g | `Pop corn sucré 75 g` | Both bags read 'Céréalis – Sweet Popcorn', 75 g. |

**11 kept separate**

| # | Brand | Pair | Evidence |
|---|---|---|---|
| 45 | Power Horse | Boisson énergétique 25 cl ↔ Boisson énergétique Power Horse 25 cl | Power Horse: the Carrefour can is the Manchester City 'official partner' edition; the Géant can is the standard design. Same drink, different packaging edition, so kept as two products. |
| 46 | Coca-Cola | Coca cola 1,5 L ↔ Coca Cola Original taste 1,5 L | Coca-Cola: the Carrefour picture is a promotional 'goût original – +25 cl gratuit' bottle; the Géant/OFF bottle is the standard 1.5 L. The promotion changes the pack content, so kept separate. |
| 49 | Brava | Café soluble chicorée 200 g ↔ Chicorée café 200 g | Brava chicorée 200 g: the Carrefour/Géant record shows a glass jar, the other Géant record shows a soft pouch. Different packaging, kept separate. |
| 50 | Brava | Chicorée café 100 g ↔ Chicorée Cafe Brava 100 g | Brava chicorée 100 g: the Géant picture is a pouch, the OFF picture a glass jar. Different packaging, kept separate. |
| 74 | Natilait | Mon dessert dessert noisette 100 g ↔ Crème dessert noisette 100 g | Natilait noisette: the Géant picture is the 'Montagne de Goût' layered dessert (another line), while Aziza's is a multi-flavour 'mon Dessert' assortment that does not show noisette. The two cannot be shown to be the same product. |
| 89 | Kartago | Dattes aux sésames Pops ↔ Sésames pops dattes-sésames Energy snacks 250 g | Kartago sesame pops: the Carrefour pack is a 50 g sachet, the Géant one a 250 g tub. Different size and packaging. |
| 109 | President | Fromage blanc fondu 8 portions ↔ Fromage fondu 8 portions | Président 8 portions: the Carrefour record is the rectangular 'Carré – frais & délicieux' block, the Géant record the round 'fromage fondu pour tartine' box. Different products. |
| 114 | Majeste | Fromage edam ↔ Fromage edam 80 g | Majesté edam: the Carrefour record is sold by weight (page says 'Au poids', KG), the Géant record is a packed 80 g wedge (PIECE). Different sale format. |
| 115 | Majeste | Fromage gruyère rapé 100 g ↔ Fromage râpé au gruyère 100% lait | Majesté gruyère râpé: Carrefour is sold by weight ('Au poids', KG); Géant is a packed 100 g bag (PIECE). |
| 132 | Mont Regal | Fromage fondu râpé à l'emmental ↔ Fromage fondu rapé à l'emmental 450 g | Mont Regal râpé emmental: Carrefour is sold by weight ('Au poids', KG); Géant is a packed 450 g bag (PIECE). |
| 134 | Mont Regal | Fromage fondu rapé à la mozzarella 1 kg ↔ Fromage râpé fondu à la Mozzarella | Mont Regal râpé mozzarella: Carrefour is sold by weight ('Au poids', KG); Géant is a packed 1 kg bag (PIECE). |

Notes. Pair #26 (Délice milk) is the weakest merge: the Géant carton does not show the variant, so the merge rests on the Open Food Facts pack ("Demi-écrémé") and both source names. Pair #9 is merged on identical wrapper art (marbled loaf, Daily'n band); the Géant label is not legible at that size. Both are reversible by re-importing a changed file, since none of these slugs has been imported.

Names. For five merges the kept record had a less precise name; `keepName` in `pair-merges.json` records the override (`Tomme de Tebourba 280 g` rather than the Carrefour "camembert …" wording that is not on the pack, `Beurre extra fin 200 g`, `Harissa du Cap Bon 135 g`, `Margarine tartine et cuisson 100 g`, `Cake marbré slice 40 g`).

## 4. Exact changes since Rev 3 (`changes-since-rev3.json`)

- 17 groups merged, 34 Rev 3 products → 17. Each kept slug is listed with the slug it absorbed.
- No product added, no category changed, no brand changed, no existing product touched.
- One kept product gained a photo: `mon-dessert-vanille-100-g-natilait` (the rejected Aziza assortment picture is replaced by the Géant cup photo, viewed in this round). `null` photos: 208 → 207.
- Five kept products took a more precise name (and slug) than the Rev 3 name; none was imported.

## 5. Uncertain pairs after round 4 (`uncertain-matches.json`, 143)

| Risk | Pairs | Meaning |
|---|---|---|
| reviewed-kept-separate | 11 | the pairs above, decided on packs or sale format |
| insufficient-evidence | 52 | cannot be decided from the data held (sizeless water records, generic "Yaourt aromatisé"/"Yaourt brassé" placeholders, Lingot wafers, …) |
| potentially-distinct | 80 | names carry a flavour/type/variant qualifier (includes 1 pair created by this round: vanilla vs marbled slice) |

No pair in the file is a *likely* duplicate any more. 52 insufficient-evidence pairs would need pack photos or sizes that are not available in the sources; they are not merged.

## 6. Validation (read-only; compiled importer modules, in-process, dev-DB snapshot)

| Check | Result |
|---|---|
| `parseCatalog` | **0 errors** |
| `planCatalog` against the dev snapshot | **0 errors**, 1 warning (the expected `viandes-poissons` archive) |
| Plan: brands created 654; categories created 11 / unchanged 6 / archived 1; products created 5,643 / updated 13 / unchanged 29 / archived 0 | as listed |
| Totals in file | 5,685 products, 654 brands, 18 categories |
| Product slugs unique; no brand missing or unused | pass |
| 42 existing slugs present exactly once | pass |
| Existing: name, description, unit, min, step, max identical to the dev DB | 0 differences |
| Existing products archived or given a brand | none |
| Plan's 13 updates | 9 `photo` + 5 `categorySlug` (`escalope-de-poulet` has both); no unit or quantity field in any update |

## 7. Existing data protection

- Live dev DB (read-only SELECT): Product 42, StoreProduct 4, OrderItem 8, Brand 0, Category 7 — unchanged by this round.
- The importer's only writes are `Brand`, `Category` and `Product` (`catalog-import.ts` header and calls; `StoreProduct` is read to compute warnings). No price, stock, availability, sale unit or quantity rule of a StoreProduct, and no OrderItem, can change.
- No existing product took part in a merge or a rename; `escalope-de-poulet` (offering #4, 19,000 millimes, KG, 500/250/5,000) keeps its Product unit and quantities; only its photo and category change, as before.

## 8. Unresolved after this round

- **Scale** (import blocker, separate step).
- 52 insufficient-evidence pairs (not merged); 55 excluded same-source look-alikes; 4 pork-family products excluded until species is known.
- `Tous les jours` (55) ownership unverified; 349 products without a brand.
- 4,726 photos URL-valid but not visually verified; hotlinking of retailer CDN images has not been assessed for availability or rights.
- Category assignment is rule-based and its error rate has not been measured.

## Update after review round 4 — scalability task (application change)

The "Scale" blocker above has been implemented in the application, outside the catalogue data: the owner catalog API now has server-side search, category filtering and keyset paging (`GET /owner/catalog/browse`, `GET /owner/catalog/products/{id}`), and the picker loads and builds products lazily. Catalogue files and counts in this report are unchanged. See `capacity-assessment.md` (status note), `SUMMARY.md` and `docs/owner-domain.md`.
