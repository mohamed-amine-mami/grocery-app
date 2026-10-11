# Catalogue v2 — product volume and UI capacity (code evidence, nothing changed)

> **Status update (scalability task, after Rev 3.1):** the problems and recommendations below were addressed in the application. `GET /owner/catalog/browse` (server-side search, category filter and keyset paging, 50 per page by default) and `GET /owner/catalog/products/{id}` were added; the owner picker now loads 40 products at a time into a lazy list and sends the search to the backend; the whole-catalogue `GET /owner/catalog/products` is kept, deprecated and unchanged. The measurements and the analysis below are the original Rev 3 findings and are left as they were. Not done: response compression, and no device measurement of the new picker. A page query over 5,700 synthetic products measured about 121 ms on the test database (rolled back, not real data). See `docs/owner-domain.md`.


> **Round 3:** your decision is recorded — no trimming; the catalogue must not be imported until the owner picker and API are made scale-appropriate in a separate step. Figures below are recomputed for the current candidate.


Candidate size: **5,685 products** in Rev 3.1 (today's dev catalogue: 42). The measurements below were taken on the Rev 3 file (5,702 products); the 0.3 % difference changes none of them or of the conclusions. Evidence below is from the working tree on 2026-10-10.

## What is returned and how big it is

| Question | Answer | Evidence |
|---|---|---|
| Products in one response | **All 5,702 active products**, in one array, no limit/offset/cursor/search parameter | `backend/src/catalog/catalog.service.ts` `products()` loads every active `Product` with `category` and `brand` included, filters in memory, sorts, returns. The only query parameter is `categoryId` (`dto/list-catalog-products.query.ts`). |
| Payload size | **≈ 2,838 KB** of JSON (≈ 2.8 MB); **≈ 170 KB** if gzip were applied | Measured by serialising the exact `CatalogProductEntity` shape for the candidate (2,905,623 bytes, ≈ 509 bytes/product). `backend/src/main.ts` installs **no compression middleware**, so the uncompressed size goes over the wire. |
| Are images in the response | **No bytes, only URL strings** (`photo`, avg ≈ 76 chars). Images are fetched separately by the client when a widget shows them | `catalog.entity.ts` `photo: string \| null`; `mobile/lib/ui/core/widgets/product_image.dart` uses `Image.network` with `cacheWidth`, placeholder and `errorBuilder`. |
| Does the picker show images | **No.** `_ProductRow` in `catalog_picker_view.dart` is text only (name, brand, category · unit, status icon). Images appear in the owner's *store* catalogue, the editor and Quick Add — which scale with the store's own offerings, not the global catalogue | `catalog_view.dart:273`, `quick_add_sheet.dart:125`, `store_product_editor_view.dart:382`, `customer/views/store_catalog_view.dart:506` are the only `ProductImage` uses. |
| Is the picker list built in memory | **Yes, fully, and non-lazily.** `CatalogRepository.products()` `jsonDecode`s the whole body on the UI isolate (no `compute`), maps to `List<CatalogItem>`; `CatalogPickerViewModel.visibleItems` filters the whole list on every build; the view builds `ListView(children: [Card(Column([for item in visible ...]))])` — a **non-builder** list, so *every* visible row is instantiated and laid out, scrolled or not | `catalog_picker_view_model.dart:48`, `catalog_picker_view.dart:215-243`. There is no `ListView.builder` / `SliverList` anywhere in `mobile/lib/ui`. |
| Server-side search / pagination / filtering | **None** beyond `categoryId`. Search is a local, accent-insensitive substring match (`SearchText.matches`) | `catalog.service.ts`, `search_text.dart` |
| Other per-request work | `categories()` loads *all* products just to count them; the sort uses `localeCompare('fr')` per comparison | `catalog.service.ts:17-36`; measured 20 ms for 5,702 rows in Node |

## Measured / estimated cost

| Item | Result | Basis |
|---|---|---|
| Local search filter, per keystroke | **≈ 33 ms** for 5,702 items in a non-release Dart VM (JIT) | `dart run` micro-benchmark of the real `SearchText.matches` over name+brand+category strings of the candidate (JIT, desktop; a mid-range phone in release mode is likely the same order of magnitude, not measured) |
| JSON encode+decode of the whole catalogue | ≈ 26 ms (desktop VM) | same benchmark, 1.9 MB file |
| Widgets instantiated when the picker opens | ≈ 5,702 rows × roughly 15–20 widgets ≈ **90,000–115,000 widgets**, all built in one frame, rebuilt (whole `_Browser`) on every keystroke | counted from `_ProductRow` source; **not measured on a device** |
| Server response time | not measured — would need the data in the database, which this phase must not do | the in-memory sort is 20 ms; the ORM load of 5,702 rows with two includes is untested |

## Likely problems at 5,702 products

1. **Picker jank / possible out-of-memory** on mid and low-end phones: opening and every keystroke rebuild ~100k widgets. This is the real blocker, and it is in the client list construction, not the data volume.
2. **2.8 MB response, uncompressed**, on every open and every pull-to-refresh (and after any failed add, the picker reloads the whole catalogue).
3. **Category chips**: 16 active categories; fine.
4. Existing smoke tests and the "a few hundred products" comment in the picker assume today's size.
5. Customers are **not** affected: `GET /stores/:id/products` returns only that store's own offerings.

## Recommendation

A scale change **is necessary before importing this volume** (or before the owner picker is used with it). In order of effect/cost:

1. Client: `ListView.builder` (lazy rows) + debounce the search + do the `jsonDecode` off the UI isolate. Removes problem 1 with no API change.
2. Server: gzip, and a `limit/offset` (or cursor) + `q` + `categoryId` contract for `GET /owner/catalog/products` so search and "already in my store" flags are computed on a page. Removes problem 2 and scales past the current catalogue.
3. Alternatively keep the contract and **stage the import** (e.g. a few hundred curated products first); the file supports that without changes since the importer leaves absent products unchanged.

Not implemented in this phase, per your instruction.
