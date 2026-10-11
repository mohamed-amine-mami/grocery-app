import json,collections
O='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
S='/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
cat=json.load(open(O+'catalog.v2.json')); db={p['slug']:p for p in json.load(open('/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/src/existing_db_products.json'))}
val=json.load(open('/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/out/validate.json'))
allp={p['slug']:(c['slug'],p) for c in cat['categories'] for p in c['products']}
old=[s for s,(c,p) in allp.items() if c=='viandes-poissons']
chees=sum(1 for s,(c,p) in allp.items() if c=='fromages'); pl=sum(1 for s,(c,p) in allp.items() if c=='produits-laitiers')
sec=f"""

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
All four are classified; **there are no exceptions**: chicken escalope and whole chicken → `volaille`; minced beef → `viandes`; sea bream → `poissons-fruits-de-mer`. After the import `viandes-poissons` holds **{len(old)} products** in the file (the planner confirms 4 `categorySlug` updates, 0 products left).

### 8.3 Can the archive hide a product?
- The archive applies to a category that, in the same file, has **0** products ({len(old)} listed under it). No new product was assigned to it.
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
The file now holds **{chees} cheese products** (portions, slices, spreads, grated, cooking cheeses). Without a separate category, `produits-laitiers` would hold {pl + chees:,} products, mixing cheese with milk, yoghurt, eggs and cream; Carrefour's own departments and Géant's navigation also separate "Fromages". `fromage-emmental` is the only existing cheese; it is a loose, cut-to-weight KG product (100/50/2000), which matches the new category's KG cheese rules; it has no offering, so the move changes display grouping only. If you prefer not to split, the alternative is zero moves for it and `fromages` merged back — a one-line taxonomy change.

### 8.7 Unresolved classification in this area
None for the existing products. Residual risks are in *new* products (see `duplicates-and-classification.md` §F).
"""
s=open(O+'impact-existing.md').read().split('\n<!-- round2 -->')[0]+sec
open(O+'impact-existing.md','w').write(s)
print('ok',len(old),chees,pl)
