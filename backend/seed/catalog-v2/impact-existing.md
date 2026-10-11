# Catalogue v2 — impact on existing records

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

| Slug | Name | Offerings | Unit & min/step/max (unchanged) | Change |
|---|---|---|---|---|
| `pomme` | Pomme | 0 | KG 500/100/10000 | unchanged |
| `banane` | Banane | 0 | KG 500/100/10000 | unchanged |
| `orange` | Orange | 0 | KG 500/100/10000 | unchanged |
| `citron` | Citron | 0 | KG 500/100/5000 | photo null → `back.carrefour.tn` |
| `fraise` | Fraise | 0 | KG 500/100/5000 | unchanged |
| `raisin` | Raisin | 0 | KG 500/100/5000 | unchanged |
| `tomate` | Tomate | 0 | KG 500/100/10000 | unchanged |
| `pomme-de-terre` | Pomme de terre | 0 | KG 1000/100/20000 | photo null → `cdn.geantdrive.tn` |
| `oignon` | Oignon | 0 | KG 500/100/10000 | unchanged |
| `carotte` | Carotte | 0 | KG 500/100/10000 | unchanged |
| `courgette` | Courgette | 0 | KG 500/100/10000 | photo null → `cdn.geantdrive.tn` |
| `poivron` | Poivron | 0 | KG 500/100/5000 | unchanged |
| `concombre` | Concombre | 0 | KG 500/100/5000 | photo null → `cdn.geantdrive.tn` |
| `laitue` | Laitue | 0 | PIECE 1/1/20 | photo null → `back.carrefour.tn` |
| `persil` | Persil (botte) | 0 | PIECE 1/1/20 | photo null → `cdn.geantdrive.tn` |
| `lait-entier-1l` | Lait entier 1 L | 0 | PIECE 1/1/24 | unchanged |
| `lait-demi-ecreme-1l` | Lait demi-écrémé 1 L | 0 | PIECE 1/1/24 | unchanged |
| `yaourt-nature` | Yaourt nature (pot) | 0 | PIECE 1/1/48 | unchanged |
| `beurre-250g` | Beurre 250 g | 0 | PIECE 1/1/20 | unchanged |
| `fromage-emmental` | Fromage emmental | 0 | KG 100/50/2000 | category produits-laitiers → **fromages** |
| `oeufs` | Œufs frais | 0 | PIECE 1/1/120 | unchanged |
| `baguette` | Baguette | 1 | PIECE 1/1/20 | unchanged |
| `pain-complet` | Pain complet | 0 | PIECE 1/1/20 | photo null → `cdn.geantdrive.tn` |
| `croissant` | Croissant | 1 | PIECE 1/1/24 | unchanged |
| `escalope-de-poulet` | Escalope de poulet | 1 | KG 250/250/5000 | category viandes-poissons → **volaille**; photo null → `back.carrefour.tn` |
| `viande-hachee-boeuf` | Viande hachée de bœuf | 0 | KG 250/250/5000 | category viandes-poissons → **viandes** |
| `poulet-entier` | Poulet entier | 0 | KG 1000/100/5000 | category viandes-poissons → **volaille** |
| `daurade` | Daurade | 0 | KG 500/100/5000 | category viandes-poissons → **poissons-fruits-de-mer** |
| `riz-1kg` | Riz 1 kg | 0 | PIECE 1/1/20 | unchanged |
| `spaghetti-500g` | Spaghetti 500 g | 0 | PIECE 1/1/20 | unchanged |
| `couscous-1kg` | Couscous 1 kg | 0 | PIECE 1/1/20 | unchanged |
| `huile-d-olive-1l` | Huile d'olive 1 L | 0 | PIECE 1/1/12 | unchanged |
| `sucre-1kg` | Sucre 1 kg | 0 | PIECE 1/1/20 | unchanged |
| `farine-1kg` | Farine 1 kg | 0 | PIECE 1/1/20 | unchanged |
| `harissa-170g` | Harissa 170 g | 0 | PIECE 1/1/20 | unchanged |
| `thon-boite` | Thon à l'huile (boîte) | 0 | PIECE 1/1/24 | unchanged |
| `dattes` | Dattes | 0 | KG 250/50/5000 | unchanged |
| `olives-vertes` | Olives vertes | 0 | KG 250/50/5000 | photo null → `back.carrefour.tn` |
| `eau-minerale-1-5l` | Eau minérale 1,5 L | 0 | PIECE 1/1/24 | unchanged |
| `eau-minerale-0-5l` | Eau minérale 0,5 L | 0 | PIECE 1/1/48 | unchanged |
| `jus-d-orange-1l` | Jus d'orange 1 L | 0 | PIECE 1/1/12 | unchanged |
| `cafe-moulu-250g` | Café moulu 250 g | 1 | PIECE 1/1/12 | unchanged |

Names and descriptions (all null) are restated exactly. Photo is the only field that changes (null → URL, 9 products, all visually inspected)
besides the 5 category moves above. 13 of 42 products have any change.

## 3. Categories

| Slug | Before | After |
|---|---|---|
| fruits, legumes, produits-laitiers, boulangerie, epicerie, boissons | active, name unchanged | active, name unchanged (importer: unchanged), now also contain new products |
| viandes-poissons | active, 4 products | **archived**, 0 active products |
| viandes, volaille, poissons-fruits-de-mer, fromages, charcuterie-traiteur, surgeles, petit-dejeuner, biscuits-gateaux, chocolat-confiserie, snacks-aperitif | — | new |

## 4. Brands

Before: 0 rows. After: 654 created. Brands are never archived; no existing product has a brand, and none is given one.

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


<!-- round2 -->
## 8. Review round 2 — verification of the moves and the archive

Source of every statement: read-only SQL on `grocery_db` (session `default_transaction_read_only=on`) and the code paths named. No live field was changed.

### 8.1 Every affected product
| Slug | Old category | New category | Live offerings | Default unit & min/step/max (before = after) |
|---|---|---|---|---|
| `escalope-de-poulet` | viandes-poissons | **volaille** | 1 (StoreProduct 4, store 17) | KG 500/250/5000 |
| `poulet-entier` | viandes-poissons | **volaille** | 0 | KG 1000/100/5000 |
| `viande-hachee-boeuf` | viandes-poissons | **viandes** | 0 | KG 250/250/5000 |
| `daurade` | viandes-poissons | **poissons-fruits-de-mer** | 0 | KG 500/100/5000 |
| `fromage-emmental` | produits-laitiers | **fromages** | 0 | KG 100/50/2000 |

### 8.2 Classification of the 4 products currently in `viandes-poissons`
All four are classified; **there are no exceptions**: chicken escalope and whole chicken → `volaille`; minced beef → `viandes`; sea bream → `poissons-fruits-de-mer`. After the import `viandes-poissons` holds **0 products** in the file (the planner confirms 4 `categorySlug` updates, 0 products left).

### 8.3 Can the archive hide a product?
- The archive applies to a category that, in the same file, has **0** products (0 listed under it). No new product was assigned to it.
- `catalog-import.ts` `writePlan` runs **inside one `db.transaction`**: category archives are written first, then every product's `categoryId` update. No reader can observe the intermediate state, and the whole file rolls back on any error (the 23505 handler returns "Nothing was written").
- Visibility rule (`products/product-rules.ts` `unavailabilityReason`): a StoreProduct is `CATALOG_ARCHIVED` only when its product **or its category** is archived. After the import `escalope-de-poulet` is in `volaille` (active), so it stays orderable.
- The planner's warning ("1 store(s) sell products in it") is computed from the **pre-move** database state, so it is a true statement about today and a false alarm about the result.
- The owner picker lists only products whose category is active (`catalog.service.ts`); an archived, empty category simply disappears from the chips.
- Mobile stale caches: an owner's open picker may still show the old chip until refresh; no data is lost.

### 8.4 StoreProduct 4 (`escalope-de-poulet`) — before vs after
| Field | Before (read from DB) | After import |
|---|---|---|
| id / storeId / productId | 4 / 17 / 25 | unchanged |
| saleUnit | KG | unchanged |
| priceMillimes | 19000 | unchanged |
| minQuantity / quantityStep / maxQuantity | 500 / 250 / 5000 | unchanged |
| trackStock / stockQuantity | false / null | unchanged |
| isAvailable | true | unchanged |
| archivedAt | null | unchanged |
The importer's `writePlan` only references `Brand`, `Category`, `Product`; `StoreProduct` is read once for warnings. The 13 product updates in the plan touch only `photo` and `categoryId`.

### 8.5 Historical order records
`OrderItem` rows referencing StoreProducts: baguette 2, café moulu 3, croissant 2, escalope 1 (**8 items, 4 orders, 16 status events**). The one escalope line (order 4, item 8) is `Escalope de poulet`, `KG`, unit price 19000, quantity 1000, line total 19000, `removedAt` set, `stockDecrementedQuantity` 0. All FKs (`OrderItem → StoreProduct`, `StoreProduct → Product`, `Product → Category`) are `RESTRICT`, nothing is deleted, and the snapshot columns are not written by the importer. Re-reading the rows after the import should return identical values.

### 8.6 Is `fromages` justified?
The file now holds **255 cheese products** (portions, slices, spreads, grated, cooking cheeses). Without a separate category, `produits-laitiers` would hold 600 products, mixing cheese with milk, yoghurt, eggs and cream; Carrefour's own departments and Géant's navigation also separate "Fromages". `fromage-emmental` is the only existing cheese; it is a loose, cut-to-weight KG product (100/50/2000), which matches the new category's KG cheese rules; it has no offering, so the move changes display grouping only. If you prefer not to split, the alternative is zero moves for it and `fromages` merged back — a one-line taxonomy change.

### 8.7 Unresolved classification in this area
None for the existing products. Residual risks are in *new* products (see `duplicates-and-classification.md` §F).
