# Catalogue v2 — validation and deduplication report

Generated 2026-10-10. Read-only: no importer run, no database write, no migration, no application code changed.

## 1. Result in one table

| Check | Result | Detail |
|---|---|---|
| Importer parseCatalog: schema, slug format, uniqueness, brand/category references, quantity rules, photo URL format | PASS | 0 errors |
| Importer planCatalog against the dev-database snapshot: no name collisions / planner errors | PASS | 0 errors |
| Product slugs unique across the file | PASS | 5685 products |
| Every product brandSlug exists in brands[] | PASS | 654 brands referenced |
| No brand in brands[] is unused | PASS | 0 unused |
| No Carrefour-branded product (brand or name) | PASS |  |
| All 42 existing slugs still present exactly once | PASS |  |
| Existing products: name, description, unit and all quantity fields restated exactly as in the dev database | PASS | 0 differences |
| No existing slug reused for a different product | PASS |  |
| Units used are PIECE or KG only (no L products, no unit not allowed by product-rules) | PASS |  |
| Every non-null photo URL answered HTTP 200 with an image/* content type and >= 1.5 KB | PASS | 5478 non-null photos |
| No photo URL rejected in visual inspection is used | PASS |  |
| Active names unique per brand (database unique index) | PASS |  |

### How the importer contract was checked

`node tools/validate.mjs catalog.v2.json existing_snapshot.json` loads the **compiled importer modules from this working tree**
(`backend/dist/catalog/catalog-file.js` → `parseCatalog`, `catalog-plan.js` → `planCatalog`, built after the sources last changed)
and runs them in-process against a read-only snapshot of the dev database (categories, products, offerings; 0 brands).
No database connection is opened by the validator. `npm run catalog:import -- --dry-run --file seed/catalog-v2/catalog.v2.json`
is the same planner against the live dev database and is the next step for you or me once this is approved.

### Plan the importer would produce (against the dev snapshot)

| Entity | Created | Updated | Unchanged | Archived |
|---|---|---|---|---|
| Brands | 654 | 0 | 0 | 0 |
| Categories | 11 | 0 | 6 | 1 |
| Products | 5643 | 13 | 29 | 0 |

Planner warnings (1):
- Archiving category "viandes-poissons" while 1 store(s) sell products in it: customers can no longer order them through this category
- This single warning is expected: it is the explicit, listed archive of `viandes-poissons` (see the impact report).
- The same warning is also a false positive in effect: the offering's product (`escalope-de-poulet`) is moved to `volaille` in the same transaction.

The 13 product updates are listed one by one in `impact-existing.md`; none changes a unit or a quantity field.

## 2. Counts

| | |
|---|---|
| Products in catalog.v2.json | 5685 (42 existing + 5643 new) |
| Brands | 654 (dev database has 0) |
| Brandless products | 349 |
| KG / PIECE | 344 / 5341 |
| Categories | 18 (11 new, 7 existing, 1 archived) |
| With a photo / null photo | 5478 / 207 |

Per category: `fruits` 19, `legumes` 67, `produits-laitiers` 345, `boulangerie` 132, `viandes-poissons` 0, `epicerie` 1978, `boissons` 628, `viandes` 18, `volaille` 50, `poissons-fruits-de-mer` 88, `fromages` 255, `charcuterie-traiteur` 126, `surgeles` 245, `produits-traditionnels` 212, `petit-dejeuner` 450, `biscuits-gateaux` 525, `chocolat-confiserie` 286, `snacks-aperitif` 261.

## 3. Deduplication

**Products built from records of more than one source: 175** (same brand + same size + same normalised wording, or confirmed on the pack photos in rounds 3 and 4): carrefour + geant 108, aziza + geant 39, geant + off 20, aziza + carrefour + geant 3, aziza + off 2, carrefour + off 2, aziza + carrefour 1. Examples:

| Product | Brand | Merged source records |
|---|---|---|
| Barre biscuitée chocolat 3 × 33 g | Momento | geant:Barre biscuitée + carrefour:Chocolat barre biscuitée lai |
| Biscuits fourrés cacaote-Chocolat-Noisette Kingo 120 g | LBM | geant:Biscuits fourrés + carrefour:Biscuits fourrés chocolat no |
| Brownies aux pépites de chocolat 60 g | Daily'n | carrefour:Brownies aux pépites de choc + geant:Brownies |
| Brownies caramel-Beurre salé 60 g | Bolerio | geant:Brownies + carrefour:Brownies caramel beurre salé |
| Cake marbré 42 g | Le Patissier | carrefour:Cake marbré + geant:Cake marbré en tranche |
| Croustina au Lait 100 g | Saïda | off:Croustina au Lait + aziza:Gaufrette croustina lait |
| Gaufrettes chocolat noir 100 g | Saïda | geant:Gaufrettes + aziza:Gaufrette au chocolat noir |
| Gaufrettes fraise 100 g | Lingot | geant:Gaufrettes + carrefour:Gaufrettes fraises |
| Madeleine 200 g | Le Patissier | geant:Madeleine + aziza:Groupage madeleine + carrefour:Madeleines |
| Smile ( biscuit Chocolat ) 190 g | Kif | off:Smile ( biscuit  Chocolat ) + carrefour:Biscuits Smile chocolat |

**Same-source collisions: 55 records not kept.** Same brand, size and wording as another record of the
*same* source but a different record id (e.g. three Tymbark "Boisson au jus 1 L" whose flavour only appears in the photo). They are
not provably identical and the database requires unique names per brand, so only the first record was kept and the others are listed
in `exclusions.json` → `sameSourceCollisions`. These are candidates for a later manual pass.

**Name collisions: 4** products not created because their display name equals an existing/other brandless product
(`Pain complet`, `Farine 1 kg`, `Epinard`, `Pot au feu`).

**Uncertain matches (not merged): 143 pairs** (rev 3: 159; 17 merged in round 4, 1 new) in `uncertain-matches.json` — mostly a size-less Carrefour record vs a sized
Géant/Aziza record of the same brand with similar wording. Highest similarity first:

| Brand | A | src | B | src | sim | risk |
|---|---|---|---|---|---|---|
| Maestro | Chocolat noir extra fin 90 g | geant+off | Chocolat Noir Extra Fin aux Noisettes 90 g | off | 0.86 | potentially-distinct |
| Délice | Lait demi-écrémé UHT 1 L | off+geant | Lait UHT demi écrémé sans lactose 1 L | geant | 0.83 | potentially-distinct |
| Ovolina | Œufs frais jaune 30 pièces | geant+carrefour | Œufs frais jaune-Junior 30 pièces | carrefour+geant | 0.83 | potentially-distinct |
| Saïda | Gaufrette chocolat 100 g | geant | Gaufrette croustina chocolat 100 g | aziza | 0.8 | insufficient-evidence |
| Lingot | Gaufrettes chocolat 100 g | carrefour | Gaufrettes chocolat lait 100 g | geant | 0.8 | insufficient-evidence |
| Lingot | Gaufrettes crème au lait 100 g | carrefour | Gaufrettes lait 100 g | geant | 0.8 | insufficient-evidence |
| Délice | Yaourt aromatisé 100 g | carrefour+aziza | Yaourt aromatisé à l’abricot 100 g | aziza | 0.8 | insufficient-evidence |
| Délice | Yaourt aromatisé 100 g | carrefour+aziza | Yaourt aromatisé à la fraise 100 g | aziza | 0.8 | insufficient-evidence |
| Délice | Yaourt aromatisé 100 g | carrefour+aziza | Yaourt aromatisé à la vanille 100 g | aziza | 0.8 | insufficient-evidence |
| Brava | Café soluble chicorée 200 g | carrefour+geant | Chicorée café 200 g | geant | 0.8 | reviewed-kept-separate |
| Brava | Chicorée café 100 g | geant | Chicorée Cafe Brava 100 g | off | 0.8 | reviewed-kept-separate |
| President | Fromage blanc fondu 8 portions | carrefour | Fromage fondu 8 portions | geant+carrefour | 0.8 | reviewed-kept-separate |
| Vitalait | Lait demi- écrémé UHT 1 L | off | Lait UHT écrémé 1 L | geant | 0.8 | potentially-distinct |
| Vitalait | Le yaourt aromatisé vanille 100 g | off | Yaourt aromatisé 100 g | carrefour | 0.8 | insufficient-evidence |
| Vitalait | Yaourt aromatisé 100 g | carrefour | Yaourt aromatisé fraise 100 g | off | 0.8 | insufficient-evidence |

**Look-alike brands not merged: 70** pairs in `brands.json`. First 30:
`Adoro Moulin d'Or` / `Moulin d'Or`, `Aljazia` / `Al Jazira`, `Aura Maestro` / `Maestro`, `Biskart` / `Up Biskart`, `Break` / `Break Kids`, `Break` / `Roll Break Lago`, `Bugles` / `Bugles/chips Up`, `Bugles/chips Up` / `Chips'up`, `Campi` / `Campi Plus`, `Candy Papillon` / `Papillon`, `Caramello Papillon` / `Papillon`, `Carthage` / `Sanabel Carthage`, `Cerealis` / `Grissini Cerealis`, `Chahia` / `Chahia Tayba`, `Crispo` / `Crispy`, `Cristal` / `Cristaline`, `Daily` / `Daily'n`, `Darna` / `Darta`, `Délice` / `Delice Deli'o`, `Délice` / `Delices de la Mer`, `Délice` / `Délice Végétal`, `Délice` / `Milkana Delice`, `Délice` / `Tarti Frais Delice`, `Dolce` / `Dolce Banana`, `Dolce` / `Dolce Coffee`, `Dolce` / `Dolce Vitalait`, `Dolce Vitalait` / `Vitalait`, `Dorra` / `Durra`, `Dorra` / `El Dorra`, `El Jawhara` / `Jawhara`.

## 4. Exclusions (read from a source, not in the file)

| Source | Reason | Records |
|---|---|---|
| geant | promotional bundle or offer text in the product record | 47 |
| off | product name not descriptive (brand or product-line name only) | 34 |
| off | Open Food Facts record incomplete (needs name, brand, quantity and a front photo) | 33 |
| mg | non-food merchandise (kitchenware, cleaning, hygiene, appliances) | 15 |
| geant | pork-family charcuterie whose species (pork vs beef/turkey) cannot be established from the source | 4 |
| aziza | name cannot be verified or classified from the source alone | 3 |
| off | no French product name | 3 |
| carrefour | Carrefour-branded product (excluded by decision) | 2 |
| aziza | promotional bundle of assorted flavours | 1 |
| aziza | promotional bundle of different products | 1 |
| geant | alcoholic beverage (out of scope) | 1 |
| geant | non-food item inside a food sub-category | 1 |
| off | quantity not parseable | 1 |
| off | quantity unit inconsistent with the product type (data error) | 1 |

Plus 2809 Géant Drive records in non-food sub-categories (hygiene, make-up, electronics, baby, pet, cleaning…) which
were never candidates (`exclusions.json` → `geantOutOfScopeSubcategories`), and 55 same-source collisions above.

## 5. Source coverage

| Source | How it was read | Raw food-scope records | Records in final products |
|---|---|---|---|
| Géant Drive (Tunis City) | public category pages, robots.txt allows; full names via product pages | 5156 (of 7965 crawled) | 5048 |
| Carrefour Tunisie | existing CSV of 500 rows (not re-crawled); categories from the earlier conversion | 500 | 493 |
| Aziza | public weekly promo catalogue page rendered in a browser (one week) | 124 food rows (of 262) | 124 |
| MG | public category pages `/15-alimentaire`, `/74-cuisine`… | 57 products | 39 |
| Open Food Facts | open API, `countries=tunisia`; **throttled (HTTP 503) after 200 of 3,883 records** | 200 | 127 |

Records count towards "final products" once per merged source record; a merged product counts in each of its sources.

## 6. Known limitations

- **Open Food Facts was only partly read** (200/3,883) because the API answered 503 repeatedly. Brand/quantity data there is crowd-sourced.
- **Monoprix** (JavaScript shop, 403 to non-browser clients) and **Géant's "hypermarket" site** (flyers only) were not usable; **manufacturer sites** (Délice, Vitalait, Saïda…) were not discoverable by search. No manufacturer catalogue was ingested; manufacturer coverage is via retailer and OFF listings.
- **Aziza** shows one week of promotions, not its range. Aziza and MG name/size are source wording.
- Carrefour rows carry **no pack size**, so they can't be merged with sized rows; 388 Carrefour-only products have no size in their name.
- Category assignment is rule-based; misclassifications are expected at the margin (e.g. chamia/bsissa under `chocolat-confiserie`).
- Fresh butcher/fishmonger coverage is thin (18 `viandes`, 50 `volaille`, 88 `poissons-fruits-de-mer`): sources mostly list packed/frozen items.
- **Size of the catalogue**: 5685 products. The owner picker loads the whole catalogue in one request (`GET /owner/catalog/products`); that contract was designed for "a few hundred". Not measured here — see summary. *Update: the picker and API were since made paged and searchable server-side (`GET /owner/catalog/browse`); see `capacity-assessment.md`.*
- Prices were seen in the sources but are **not** in any deliverable.
- Pork products (e.g. bacon/chorizo de porc, jambon de Paris) exist in the Géant range and are included as food; review if undesired.
