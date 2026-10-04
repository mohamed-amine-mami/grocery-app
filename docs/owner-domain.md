# Owner Domain

The owner side of GrocerGo (pickup only, no delivery): what is built, the rules that matter, what is postponed. Rules that live in code are referenced, not restated. UI/UX: `design.md`. Conventions and commands: `CLAUDE.md`.

## 1. Model

```
User (role OWNER) 1─1 Store ─* StoreProduct ─> Product ─> Category
```

- **Category and Product are global.** They are curated in `backend/seed/catalog.json` and loaded with `npm run catalog:import`; owners cannot create or edit them.
- A **StoreProduct** is one store's offering of one product: `UNIQUE(storeId, productId)`, archived rather than deleted.
- No Owner entity: an owner is a `User` with role OWNER. V1: one owner = one store (`Store.ownerId` unique); one account = one role.
- The owner is the JWT `sub`; the store is resolved from it and every store query is filtered by `storeId`. Another store's id is a 404.

## 2. Users and authentication

- `POST /auth/register`, `POST /auth/login`, `GET /auth/me`. Login is by phone (required, unique; optional `+`, then 8–15 digits; spaces, dots, dashes and parentheses are stripped). JWT: 7 days, `{ sub, role }`.
- Every `/owner/*` route uses `JwtAuthGuard` + `RolesGuard` + `@Roles(OWNER)` (401 without a valid token, 403 for a CLIENT). Public: `/health`, register, login. `backend/test/route-guards.e2e-spec.ts` pins the route table.
- Payloads with `ownerId`, `storeId`, `archivedAt` or any global product field are rejected (400, global `ValidationPipe`).

## 3. Store

Name (≤100), address (≤200), description (≤1000), photo (http(s) URL, no upload), latitude/longitude (both or neither), `isOpen` (default `false`).

- `GET /owner/store`: the store, or **404** (= owner without a store). `POST`: create (409 if one exists). `PATCH`: partial update, including `isOpen`.
- `isOpen` is a manual switch (no opening hours) and **is not enforced yet**: when orders exist the backend must reject orders for a closed store.

## 4. Owner workflow: catalog → store product

```
Catalogue → "Ajouter depuis le catalogue" → product picker → Quick Add → StoreProduct created → Catalogue refreshed
```

Owners never create or manage global Categories or Products, and there is no Admin UI: the global catalog is managed only by the importer (`backend/seed/catalog.json`, `npm run catalog:import`). Global Product data (name, category, description, image, default unit and rules) is read-only to the owner. Everything store-specific belongs to the **StoreProduct**: price, sale unit, quantity rules, stock, the owner's availability switch and the archive state.

| Route | Purpose |
|---|---|
| `GET /owner/catalog/categories` | Active categories with product counts (not used by a screen today) |
| `GET /owner/catalog/products[?categoryId]` | Picker list; each product has `inMyStore`, `storeProductId`, `storeProductArchived` |
| `GET` / `POST /owner/store-products` | List (`status`, `categoryId`) / add (409 if the store has it, archived included) |
| `GET` / `PATCH` / `DELETE /owner/store-products/:id` | Read / edit price, unit, rules, stock / archive |
| `PATCH /owner/store-products/:id/availability` | The owner's on/off switch |
| `POST /owner/store-products/:id/restore` | Restore an archived one |

- **Rules** (units, quantity granularity, stock validation, the derived `isOrderable` and `unavailabilityReason`, `lineTotalMillimes`) are defined in `backend/src/products/product-rules.ts`. Dart mirrors the unit rules and validation, tested on the same cases.
- **Orderability.** The backend's `isOrderable` / `unavailabilityReason` (`ARCHIVED`, `OWNER_DISABLED`, `CATALOG_ARCHIVED`, `OUT_OF_STOCK`, `STOCK_BELOW_MINIMUM`) is the only source of truth for what customers can order. Flutter displays it and never computes it, and never changes the owner's `isAvailable` because of stock.
- **Stock** belongs to the StoreProduct. Editing `trackStock` or `stockQuantity` requires `expectedStockQuantity` (`null` if untracked); if the stock changed meanwhile the response is 409 `STOCK_CHANGED` with `currentStockQuantity`, and nothing is applied. With tracking on and a stock of 0 the backend makes the product unorderable (`OUT_OF_STOCK`) while the owner's switch is untouched; with tracking off, stock plays no part.
- **Importer** (`npm run catalog:import`, `--dry-run` first). It validates the whole file before writing, matches Categories and Products by `slug` (a changed name updates the same row), applies everything in one transaction, and is idempotent. A catalog entry is archived only when the file flags it `"archived": true` (leaving it out does nothing); the report warns about the active store products an archive affects. It only writes Category and Product, never StoreProduct.
- **Stock edits** go through `PATCH /owner/store-products/:id` (there is no separate stock route); only the owner can change a StoreProduct's stock.
- **Archive, never delete.** An archived StoreProduct, or one whose product or category the catalog archived, is unorderable and kept. Restoring reactivates the same StoreProduct (same id, same configuration); it never creates another, and the add flow is blocked for a product the store already has (409).

## 5. Flutter owner experience

**Routing.** `SplashGate` restores the session; `AuthenticatedHome` is the single post-auth entry.

| State | Result |
|---|---|
| No stored token | Splash → Connexion |
| Token rejected by `GET /auth/me` (401, or 404 for a deleted user) | Token discarded → Connexion |
| Token stored, backend unreachable (offline / 5xx) | **Session kept**; retry screen |
| `CLIENT` | `HomeView` (customer placeholder) |
| `OWNER` | `OwnerGate` → `GET /owner/store`: store → `OwnerShell`; 404 → `StoreCreateView`; failure → retry screen |
| Logout | Straight to Connexion, token cleared |

**Shell.** Tabs **Accueil · Catalogue · Magasin**. The enum `OwnerTab` also declares `orders`, which stays out of the list until orders exist, so there is no dead tab.

- **Accueil:** greeting, store card, and a setup checklist (*Ajouter des produits · Ouvrir le magasin*) until complete.
- **Magasin:** open/closed switch, store details form, sign out.
- **Catalogue:** the store's active StoreProducts, grouped by their global Category, with category filter chips. Each row shows the product image (placeholder when none), name, price per sale unit, step, and stock when tracked (`Stock : 20 kg`, or **Rupture de stock** when the count is 0). A product that is not orderable per the backend shows "Indisponible" (icon + text). The row's switch is the owner's availability toggle and works without opening the editor; tapping the row opens the editor. Archived products are not listed. The empty state and the "Ajouter depuis le catalogue" button open the picker; the list reloads when the picker closes.
- **Picker** (`CatalogPickerView`): the whole global catalog, read-only, loaded once; search (accent-insensitive) and category filters run locally. Rows already in the store read "Ajouté" and are not selectable. A product to add opens **Quick Add**. A product the store archived reads "Archivé" and opens the editor, where it can be restored; it can never be added a second time.
- **Quick Add** (bottom sheet): shows the product read-only (image, name, category, default unit and rules). The owner types a price; unit, minimum, step, maximum, stock tracking, initial stock and availability are prefilled from the catalog defaults and tucked under one collapsible section. On success the picker row becomes "Ajouté" and the owner can keep adding. A 409/404 (already added elsewhere, or gone from the catalog) reloads the picker and says what is true now.
- **StoreProduct editor** (full page): a read-only "Catalogue — lecture seule" card, the backend-derived status (available · désactivé par vous · rupture de stock · stock insuffisant · archivé · retiré du catalogue, each with icon and explanation), then the editable "Votre magasin" form: price, sale unit (a selector only when the product allows two units: its default or piece), minimum / step / optional maximum (blank = no maximum, sent as `null`), stock tracking with the current stock, and the availability switch. Quick Add and the editor share one form and its validation. Changing the unit resets the rules and requires a new price (and stock). Save sends only what changed; a stock conflict keeps the owner's input and offers the current stock. "Archiver ce produit" asks for confirmation and archives; an archived product opens read-only with "Restaurer ce produit".

## 6. Scope

- **Built:** auth and roles, store, global catalog + importer, store products with stock, owner shell, dashboard, and the Owner catalog (Catalogue, picker, Quick Add, StoreProduct editor, archive and restore).
- **Next:** orders.
- **Decided for orders (not built):** lifecycle `PENDING → CONFIRMED → READY_FOR_PICKUP → COMPLETED`, `PENDING`/`CONFIRMED → CANCELLED`, `READY_FOR_PICKUP → NO_SHOW` (set manually, never automatic), no `PREPARING`; a customer may cancel only while `PENDING`; `requestedPickupAt` is an advisory time, not a slot; stock is decremented at placement and restored on `CANCELLED`, `NO_SHOW` or a removed line, not on `COMPLETED`; items snapshot name, unit and price.
- **Not planned:** delivery, online payment, loyalty, promotions, analytics.

## 7. Known limitations

- Owner sign-up is open. Photos are URL strings (no upload); the owner app shows catalog images, with a placeholder when there is none. A JWT expiring while the app is open is not handled centrally (the app-start check is).
- No login rate limiting; Swagger (`/api`) is public — fine locally, revisit before deployment.
- `app.module.ts` still registers `ObserveModule` with placeholder credentials (scaffold; logs a harmless telemetry 401).

## 8. Open decisions

Weighed items: estimated vs real weight · pickup-time bounds (30 min minimum, 48 h maximum proposed) · out-of-stock handling (removing a line is leading, unconfirmed) · store contact number · `NO_SHOW → COMPLETED` and `READY_FOR_PICKUP → CANCELLED` · an `OrderEvent` audit table · new-order awareness without push · opening hours · image upload · owner sign-up approval · one person as owner and customer · `design.md` still shows `Preparing` and `Uncollected`.
