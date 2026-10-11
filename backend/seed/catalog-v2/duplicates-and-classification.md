# Catalogue v2 — duplicates and classification quality (round 2)

> **Superseded in part by round 3.** Carrefour size-less records were resolved from their product pages, pack-photo merges and variant restores were applied, and the counts below are the current run. See `review-round3.md` §5 and §8 and `changes-since-rev2.json`.


Priority used: **identical name + brand + size** first, then same photo, then wording look-alikes.

## A. Exact duplicates — merged (29)
Rule: same brand, same package size, different sources, identical wording after removing pure descriptor words (`canette`, `naturelle`, `boisson`, `gazeuse`, `au jus`, `the box`, …) and tolerating 1-letter typos/plurals. Merged records keep every source in `provenance.json`; the name/photo come from the highest-priority source.

| Brand | Kept name | Merged-away name | Sources |
|---|---|---|---|
| Délice | Boisson au jus poire 20 cl | Jus poire 20 cl | geant+aziza |
| Délice | Boisson au jus mangue 20 cl | Jus mangue 20 cl | geant+aziza |
| Viva | Boisson gazeuse citron 24 cl | Boisson gazeuse canette citron 24 cl | geant+aziza |
| Viva | Boisson gazeuse cidre 24 cl | Boisson gazeuse canette cidre 24 cl | geant+aziza |
| Viva | Boisson gazeuse pomme 24 cl | Boisson gazeuse canette pomme 24 cl | geant+aziza |
| Viva | Boisson gazeuse pêche 24 cl | Boisson gazeuse canette pêche 24 cl | geant+aziza |
| Raoua | Boisson gazeuse chani 24 cl | Boisson gazeuse canette chani 24 cl | geant+aziza |
| Natilait | Boisson lactée pêche-Abricot 160 g | Boisson lactée au jus de pêche abricot 160 g | geant+carrefour |
| Le Petit Paris | Tomate concassée 400 g | Tomates concassées 400 g | geant+carrefour |
| El Manar | Filets de thon A' l'huile d'olive et au tomates séchées 200 g | Filet de thon à l'huile d'olive et à la tomate séchée 200 g | geant+carrefour |
| Le Patissier | Madeleine 200 g | Madeleines 200 g | geant+aziza+carrefour |
| Mahboul | Chips barbecue The box 42 g | Chips the box barbacue 42 g | geant+aziza |
| Mahboul | Chips hot and spicy The box 42 g | Chips the box hot spicy 42 g | geant+aziza+carrefour |
| Mahboul | Chips hot and spicy The box 125 g | Chips the box hot et spicy 125 g | geant+aziza |
| Marwa | Eau minérale 0,5 L | Eau minérale naturelle 0,5 L | geant+off |
| Sabrine | Eau minérale 1,5 L | Eau minérale naturelle 1,5 L | geant+off |
| Eden | Vinaigre naturel de cidre 500 ml | Vinaigre de cidre 500 ml | geant+carrefour |
| Ritter Sport | Chocolat blanc noisette 100 g | Chocolat blanc aux noisettes 100 g | geant+carrefour |
| Calnort | Bouillons poulet 8 × 10 g | Bouillon de poulet 8 × 10 g | geant+carrefour |
| Calnort | Bouillons bœuf 8 × 10 g | Bouillon de bœuf 8 × 10 g | geant+carrefour |
| Calnort | Bouillons poisson 8 × 10 g | Bouillon de poisson 8 × 10 g | geant+carrefour |
| Hahne | Flocon d'avoine feuille large 500 g | Flocons d'avoine feuilles larges 500 g | geant+carrefour |
| Hahne | Flocon d'avoine petite feuille 500 g | Flocons d'avoine petites feuilles 500 g | geant+carrefour |
| Hazem | Loukoum noisette 250 g | Loukoum goût noisettes 250 g | geant+carrefour |
| Lingot | Gaufrettes fraise 100 g | Gaufrettes fraises 100 g | geant+carrefour |
| Saïda | Gaufrettes chocolat noir 100 g | Gaufrette au chocolat noir 100 g | geant+aziza |
| Délice | Eau minérale 1,5 L | Eau minérale naturelle 1,5 L | geant+off |
| Tarti Fro | Préparation alimentaire fondue 24 portions | Préparation alimentaire fondu 24 portions | geant+carrefour |
| Kif | Smile ( biscuit Chocolat ) 190 g | Biscuits Smile chocolat 190 g | off+carrefour |

Also checked: **identical photo URLs across products: 0**; **byte-identical image files shared by several products: 14 groups / 28 products** — all inspected: 8 are size variants of the same product (Danup 160/260 g, MAD chips 16/75 g, saupe sizes, entremets), 6 are generic stock photos shared by different brands (chickpeas NFE/Rima, ground coffee Ben Yedder, ham Mliha/Chahia, nuggets El Mazraa/Mliha). None is evidence of a duplicate product; the generic ones are flagged as "generic photo" and kept (they show the right food).

## B. Same brand + same size + similar wording, **not** merged (130 pairs)
Highest risk first (similarity ≥ 0.8: 17 pairs):

| Brand | A | src | B | src | sim |
|---|---|---|---|---|---|
| Maestro | Chocolat noir extra fin 90 g | geant+off | Chocolat Noir Extra Fin aux Noisettes 90 g | off | 0.86 |
| Délice | Lait demi-écrémé UHT 1 L | off | Lait UHT demi écrémé sans lactose 1 L | geant | 0.83 |
| Ovolina | Œufs frais jaune 30 pièces | geant+carrefour | Œufs frais jaune-Junior 30 pièces | carrefour+geant | 0.83 |
| Saïda | Gaufrette chocolat 100 g | geant | Gaufrette croustina chocolat 100 g | aziza | 0.8 |
| Lingot | Gaufrettes chocolat 100 g | carrefour | Gaufrettes chocolat lait 100 g | geant | 0.8 |
| Lingot | Gaufrettes crème au lait 100 g | carrefour | Gaufrettes lait 100 g | geant | 0.8 |
| Délice | Yaourt aromatisé 100 g | carrefour+aziza | Yaourt aromatisé à l’abricot 100 g | aziza | 0.8 |
| Délice | Yaourt aromatisé 100 g | carrefour+aziza | Yaourt aromatisé à la fraise 100 g | aziza | 0.8 |
| Délice | Yaourt aromatisé 100 g | carrefour+aziza | Yaourt aromatisé à la vanille 100 g | aziza | 0.8 |
| Brava | Café soluble chicorée 200 g | carrefour+geant | Chicorée café 200 g | geant | 0.8 |
| Brava | Chicorée café 100 g | geant | Chicorée Cafe Brava 100 g | off | 0.8 |
| President | Fromage blanc fondu 8 portions | carrefour | Fromage fondu 8 portions | geant+carrefour | 0.8 |
| Vitalait | Lait demi- écrémé UHT 1 L | off | Lait UHT écrémé 1 L | geant | 0.8 |
| Vitalait | Le yaourt aromatisé vanille 100 g | off | Yaourt aromatisé 100 g | carrefour | 0.8 |
| Vitalait | Yaourt aromatisé 100 g | carrefour | Yaourt aromatisé fraise 100 g | off | 0.8 |
| Vitalait | Yaourt brassé 70 g | carrefour+geant | Yaourt brassé pistache 70 g | geant | 0.8 |
| Vitalait | Yaourt brassé 70 g | carrefour+geant | Yaourt brassé vanille 70 g | geant | 0.8 |

These need a human glance: some are surely one product (e.g. `Crème fraîche 15 cl` / `Crème fraîche Chef 15 cl` — Chef is the line), others are different (`Chocolat noir extra fin 90 g` vs `… aux noisettes 90 g`).

### Variants that **must remain separate** (same brand and size, different flavour/type — 113 pairs in the lower-similarity band)
Examples: Diva jus ananas / orange / pomme 1 L; Moulin d'Or pain de mie complet / nature 21 tr.; Natilait Misto céréales–fruits des bois / –fruits exotiques; Délice yaourt aromatisé banane / yaourt brassé banane; Délice lait demi-écrémé / écrémé / sans lactose 1 L; Sanabel Fell n°2 / n°2.5; Maestro chocolat noir / aux noisettes. They look similar to a string matcher and are different products.

## C. Same wording, size unknown on one side (29 pairs; 12 are Carrefour-without-size vs Géant-with-size)
The Carrefour CSV carries no pack size, so these can't be merged or told apart without the packs. Highest similarity:

| Brand | A | src | B | src | sim |
|---|---|---|---|---|---|

Recommendation (not applied): if you want a tighter catalogue, drop the Carrefour size-less record whenever a sized same-brand sibling with ≥ 0.75 wording similarity exists — about 0 records. Needs your approval because it removes products.

## D. Same name and size under several brand spellings
`Camembert 250 g` exists under **Calife Souani / Vieux Calife Souani / National Souani**: three distinct Géant records (product ids 25805, 25804, 25803) with three different photos → **kept as three products** (brand strings differ and the photos differ). `Margarine 200 g` / `400 g` under `Goldina` and `Goldina Plus`: distinct records and photos, kept. Details: `brand-review.md`.

## E. Same-source collisions — 55 records not kept
Same brand, size and wording, different record id, from one source. They cannot be told apart from the text (e.g. 3 Tymbark "Boisson au jus 1 L" differ only on the pack). Listed in `duplicate-review.json` → `sameSourceCollisions`; top brands: Jawhara ×6, — ×4, Papillon ×4, Ruspina ×4, Iroise ×3, Tresor Del Rio ×3, Kyufi ×2, Le Moulin ×2. Candidates for a later flavour-from-photo pass.

## F. Rule-based classification mistakes: found and corrected (79 products)
The review found the classes below (found in the visual sheets or by a second name-based classifier). Corrections were applied as explicit rules, never to the 42 existing products; the list is `classification-corrections.json`.

| Rule | What | Products | Examples |
|---|---|---|---|
| C1 | candy filled with chamia stays confectionery | 1 | Bonbons fourrés chamia 150 g |
| C2 | ghrayba is a shortbread biscuit | 2 | Ghrayba droo-Sésame 320 g; Ghrayba hommes 400 g |
| C3 | tahini is a pantry sesame paste | 5 | Hommos tahina 400 g; Houmous tahina 370 g; Tahina 400 g |
| C4 | sesame/date "pops" are snack bites | 9 | Céréales coco pops chocos 330 g; Céréales coco pops chocos 480 g; Choco pops dattes-Cacao-Noix de coco Energy snacks 250 g |
| C5 | traditional Tunisian specialty (chamia/bsissa/zrir): its own food type, neither confectionery nor a generic breakfast item | 5 | Bsissa d'avoine 500 g; Bsissa de blé Vanoise 500 g; Chamia à tartiner nature 350 g |
| C6 | traditional flour / grain / paste preparation | 10 | Assida instantanée noisette 500 g; Assida instantanée zgougou 500 g; Assida instantannée cacahouètes 500 g |
| M1 | citron is a fruit | 1 | Citron Eureka AA |
| M10 | drink | 5 | Boisson d'amande sans sucre-Sans gluten 1 L; Boisson de soja calcium sans sucre-Sans gluten 1 L; Boisson vegan avoine barista oat-San sucre ajouté 33 cl |
| M2 | sardine is fish | 1 | Sardine |
| M3 | soup / noodles / stock / mash is a pantry item | 24 | Pâtes noodles beldi 5 × 70 g; Pâtes noodles bœuf 5 × 70 g; Pâtes noodles bœuf 60 g |
| M4 | ice-cream sandwich | 1 | Glace sandwich vanille 105 g |
| M7 | fermented milk | 1 | Leben (lait fermenté) 420 g |
| M8 | cheese | 7 | Fromage fondu 306 g; Fromage Fondu 612 g; Fromage fondu président 24 portions 306 g |
| M9 | bread / viennoiserie | 7 | Croissant 58 g; Croissant chocolat 60 g; Croissant fraise 60 g |

A disagreement scan between the main classifier and an independent name classifier flagged ~1,200 products, but ~1,100 of them are false alarms (a flavour word such as *fraise* in a biscuit, or *poulet* in a stock cube). **Residual suspected errors I did not correct** (small, listed so they are not hidden): `Banana chips` (epicerie vs snacks); `Barre de céréales…` / `Barre protéinée` in `petit-dejeuner` or `biscuits-gateaux` (arguably snacks); salami/ham de dinde under `charcuterie-traiteur` (correct: cold cuts, not fresh poultry); `Chausson aux pommes` in boulangerie (fine). Because no per-product manual review was done, assume a residual classification error rate of a few percent outside the categories I inspected visually.

## G. Change log of this round (catalog changes, enumerated)
| Change | Count |
|---|---|
| Products removed: promotional "Lot …" bundles (Géant) | 10 |
| Products removed by descriptor-merge (kept in provenance) | 29 |
| Category corrections (rules C1–C5, M1–M12) | 79 |
| Photos removed (visual inspection, other-retailer logo, identity unconfirmable) | 5 in this round (+ the 38 of round 1) |
| Brands added/removed | −1 (one merged-away product's brand spelling no longer used) → 654 brands |
| Products | 5,824 → **5,702** |

> Later review rounds (`review-round3.md`, `review-round4.md`) supersede the counts in this round-2 document.
