# Owner Domain — Source of Truth

Owner-side architecture of GrocerGo (pickup-only; **no delivery, ever**). This file describes what is **built**, the **rules that must not be broken**, what is **postponed**, and what is **still undecided**. It is kept equal to the code: if they disagree, fix one of them in the same change. UI/UX lives in `design.md`; engineering conventions in `CLAUDE.md`.

## 1. Domain in one page

```
User (role = OWNER) 1 ──── 1 Store ──┬── * Category
                                     └── * Product ──(optional)──> Category
```

- **No `Owner` entity.** An owner is a `User` with `role = OWNER`.
- **V1: one owner → exactly one store** (`Store.ownerId` is `UNIQUE`).
- **Every catalog/order table belongs to the store through `storeId`** — never to the owner, never to a category. (That is what keeps a later move to multi-store cheap: drop the unique constraint and make the "current store" explicit.) Multi-store is deliberately **not** architected now.
- **Nothing in the API lets a client name an owner or a store.** The owner is the JWT's `sub`; the store is looked up from it.

## 2. Users and authentication

- Accounts are created only through `POST /auth/register` (`role` = `OWNER` or `CLIENT`) and read through `GET /auth/me`. The users module has **no HTTP routes**.
- `User.phoneNumber` is **required and unique** (NOT NULL in the database) — it is the login identifier.
- Phone numbers: optional leading `+`, then 8–15 digits. Spaces, dots, dashes and parentheses are stripped before validation and storage (`98 999 240` ≡ `98999240`), on register and login alike, mirroring the Flutter form validator.
- JWT: 7 days, payload `{ sub, role }` only. Roles come from the token.

## 3. Authorization model

| Rule | Enforced by |
|---|---|
| Every `/owner/*` route needs a valid JWT **and** `role = OWNER` (401 without a token or with a forged one, 403 for a CLIENT) | `JwtAuthGuard` + `RolesGuard` + `@Roles(OWNER)` on each owner controller |
| A route with `@Roles` missing is denied, not open | `RolesGuard` |
| The owner is the JWT `sub`; the store is resolved from it; every query is filtered by that `storeId`. Another store's id is a **404**, indistinguishable from a missing one | `StoresService.findByOwner` + scoped queries in the categories/products services |
| `ownerId`, `storeId`, `archivedAt`, `isOpen` (on create), `isAvailable` (on edit) are rejected in payloads (400) | global `ValidationPipe` (`whitelist` + `forbidNonWhitelisted`), shared through `app.setup.ts` |
| A referenced category must belong to the same store (400) | `ProductsService.assertCategoryInStore` |
| Archived products cannot be edited or toggled (409) | `ProductsService` |
| One store per owner (409) | DB unique constraint, mapped in `StoresService` |

The old generic `/users` and `/stores` CRUD was **removed** (it was unauthenticated and could change roles, passwords and other owners' stores). When customers need to browse stores, add a dedicated read-only endpoint — do not resurrect generic CRUD.

**Regression net:** `backend/test/route-guards.e2e-spec.ts` reads the real route table from the Swagger document and asserts that (a) the set of routes is exactly the expected list, (b) every non-public route is 401 without/with a bad token, (c) every `/owner/*` route is 403 for a CLIENT, (d) no route takes an owner/store id. Adding a route requires a conscious edit of that list.

Public routes: `GET /health`, `POST /auth/register`, `POST /auth/login`.

## 4. Store

| Field | Required | Notes |
|---|---|---|
| `id`, `ownerId` | ✓ | `ownerId` unique, FK → `User` |
| `name` | ✓ | trimmed, non-empty, ≤ 100 |
| `address` | ✓ | readable pickup address, trimmed, non-empty, ≤ 200 |
| `description` | — | ≤ 1000 |
| `photo` | — | an `http(s)` URL string, ≤ 2048 (**no upload exists**; localhost allowed for dev) |
| `latitude`, `longitude` | — | **both set or both null** — enforced in the DTO (create), the service (update) and a DB `CHECK` (`store_coordinates_together`) |
| `isOpen` | ✓ | default `false` — **new stores start closed**; only `PATCH` can open one |
| `createdAt`, `updatedAt` | ✓ | |

**Meaning of `isOpen`:** `false` = the store is currently not accepting orders. It is a manual switch only — no opening hours. It is stored and shown but **not enforced yet** because orders do not exist; when order creation is built, the **backend** must reject orders for a closed store.

| Route | Behavior |
|---|---|
| `GET /owner/store` | The caller's store, or **`404`** when they have none — this is how the app learns "owner without a store". |
| `POST /owner/store` | Create. `409` if one exists. Never accepts `ownerId` or `isOpen`. |
| `PATCH /owner/store` | Partial update incl. `isOpen`. `latitude`/`longitude` must be sent together; `null` for both clears the location; `null` for `name`/`address` is a 400. Empty body is a no-op. `404` without a store. |

## 5. Category

A store-owned grouping for products.

| Field | Required | Notes |
|---|---|---|
| `id`, `storeId` | ✓ | `storeId` FK → `Store` (`Restrict`), set by the backend |
| `name` | ✓ | trimmed, 1–50 characters |
| `createdAt`, `updatedAt` | ✓ | |

- **Unique per store, ignoring letter case:** unique index on `("storeId", lower("name"))` → `409`. Two different stores may share a name.
- Listed alphabetically; no manual ordering in V1.

| Route | Behavior |
|---|---|
| `GET /owner/categories` | The store's categories, sorted by name. |
| `POST /owner/categories` | `{ name }` → `201`; `400` invalid, `409` duplicate. |
| `PATCH /owner/categories/:id` | `{ name }` (rename); `404` not in this store, `409` duplicate. |
| `DELETE /owner/categories/:id` | `204`; `404` not in this store; **`409` while any non-archived product uses it**. |

**Deletion rule:** active products block deletion; **archived products never do** — `Product.categoryId` is `ON DELETE SET NULL`, so they simply lose their category. The 409 check and the delete are not one transaction: a product created in between would become uncategorized rather than lost (acceptable for a single-owner store).

## 6. Product

A product belongs **directly to a store** (`storeId`). Its category is optional.

| Field | Required | Notes |
|---|---|---|
| `id`, `storeId` | ✓ | `storeId` FK → `Store` (`Restrict`), from the JWT |
| `categoryId` | — | FK → `Category`, `ON DELETE SET NULL`; must be a category of the same store. `null` = "Sans catégorie" |
| `name` | ✓ | trimmed, non-blank, ≤ 100; unique among the store's **active** products, ignoring case (409); archiving frees the name |
| `description` | — | ≤ 1000 |
| `photo` | — | `http(s)` URL string, ≤ 2048 — same URL-string abstraction as store and user photos, **no upload** |
| `saleUnit` | ✓ | enum `PIECE`, `KG`, `L` (text + CHECK) |
| `priceMillimes` | ✓ | integer 1…10 000 000 — price of **one sale unit** |
| `minQuantity`, `quantityStep` | ✓ | integers in base units |
| `maxQuantity` | — | integer in base units |
| `isAvailable` | ✓ | default `true` |
| `archivedAt` | — | set ⇒ archived |
| `createdAt`, `updatedAt` | ✓ | |

### 6.1 Unit and quantity model

- **Units are an enum, not a table.** `PIECE`, `KG`, `L` say *how the price is expressed*. There is no `G`/`ML`, and no bottle/pack/box/dozen: packaging goes in the product name ("Lait 1 L", "Œufs ×6") or a future packaging label.
- **`priceMillimes` is the price of ONE sale unit** (1 piece / 1 kg / 1 L). TND, 3 decimals: `1800` = 1,800 DT. No floats anywhere.
- **Quantities are integers in the unit's base:** `PIECE` → pieces, `KG` → grams, `L` → millilitres. The UI displays `g`/`kg` and `mL`/`L` according to the value (`500` → "500 g", `1500` → "1,5 kg").
- **Orderable quantities:** `min`, `min + step`, `min + 2·step`, … up to `max`; `min` and `max` are multiples of `step`.

| Product | Unit | Price | min / step / max | Customer can order |
|---|---|---|---|---|
| Tomates | `KG` | 1800 | 500 / 500 / 10000 | 500 g, 1 kg, 1,5 kg… |
| Fromage | `KG` | 28000 | 100 / 100 / — | 100 g, 200 g, 300 g… |
| Œufs | `PIECE` | 350 | 1 / 1 / — | 1, 2, 3 pièces… |
| Lait 1 L | `PIECE` | 1350 | 1 / 1 / — | 1, 2, 3 pièces… |

**Validation** lives in `backend/src/products/product-rules.ts` (pure, framework-free). The database repeats the numeric invariants as CHECK constraints (positive price/min/step, `min % step = 0`, `max % step = 0`, `max ≥ min`).

- `min`, `step`, `max` are positive integers; `min % step = 0`; `max % step = 0`; `max ≥ min`.
- **Unit-dependent:** `KG`/`L` quantities must be multiples of **10** (g/mL) — this catches the classic mix-up of typing `1` for one kilo, which would be 1 gram. `PIECE` accepts single pieces. Ceilings: 1 000 pieces, 100 000 g, 100 000 mL.
- Defaults when omitted: step = 1 (`PIECE`) or 100 (`KG`/`L`); `min` = one step.

**Changing `saleUnit` never silently reinterprets old values:** the `PATCH` must also send `priceMillimes`, `minQuantity`, `quantityStep` (and `maxQuantity` when one is set); the merged result is then fully re-validated.

### 6.2 Line total (for the future `OrderItem`)

`lineTotalMillimes(unit, priceMillimes, quantity) = round_half_up(priceMillimes × quantity / baseFactor)`, `baseFactor` = 1 for `PIECE`, 1000 for `KG`/`L`. Integer arithmetic only — BigInt on the backend, Dart `int` in Flutter — and both implementations are tested against the same cases: `1800 × 500 g → 900`, `28000 × 300 g → 8400`, `350 × 12 → 4200`. Orders must compute the total **once** at order time and snapshot it.

### 6.3 Availability vs archive

- `isAvailable = false` — "out of stock today". The product stays in the catalog, flagged "Indisponible". Never delete a product for this.
- `DELETE` **archives** (`archivedAt = now`). Rows are never hard-deleted (history). Archived products are hidden from the active catalog and cannot be edited or toggled (409). Archiving is idempotent. There is no restore in V1.

### 6.4 API

| Route | Behavior |
|---|---|
| `GET /owner/products?categoryId=&status=active\|archived\|all` | Default `active`; sorted by name. |
| `POST /owner/products` | `201`. `400` invalid fields / quantity rules / foreign category; `409` duplicate active name. |
| `GET /owner/products/:id` | One product, archived or not. |
| `PATCH /owner/products/:id` | Partial. `null` clears `description`, `photo`, `categoryId`, `maxQuantity`; other fields reject `null`. `409` if archived or duplicate name. |
| `PATCH /owner/products/:id/availability` | `{ isAvailable }`. `409` if archived. |
| `DELETE /owner/products/:id` | `204`, archives. |

## 7. Flutter owner experience

### 7.1 Routing and session lifecycle

`SplashGate` (app start) restores the session; `AuthenticatedHome` is the single post-auth entry point (login, registration, session restore):

| State | Result |
|---|---|
| No stored token | Splash → Connexion |
| Token rejected by `GET /auth/me` (401, or 404 for a deleted user) | Token discarded → Splash → Connexion |
| Token stored but backend unreachable (offline / 5xx) | **Session kept**; "Impossible de joindre le serveur" with **Réessayer** |
| `CLIENT` | `HomeView` (customer side, placeholder) |
| `OWNER` | `OwnerGate` → `GET /owner/store`: store → `OwnerShell`; none (404) → `StoreCreateView`; request failed → retry screen (never falls through to owner screens) |
| Owner registration | Whole auth stack dropped → `AuthenticatedHome` (new owner → store creation; no way "back" to the signup screens while signed in) |
| Logout (Magasin tab, store-creation app bar, retry screen) | Straight to Connexion; token cleared |

Snackbars are owned by their screen (`ScaffoldMessenger` per owner tab and for the category screen) so they are dismissed with it and never cover another screen's floating button.

### 7.2 Owner shell

Bottom `NavigationBar`: **Accueil · Catalogue · Magasin**. The enum `OwnerTab` also declares `orders` ("Commandes"), but it is not in the list of available tabs — the owner never sees a dead tab; adding orders later is one list entry plus one page. No customer-side navigation exists in the owner shell.

| Tab | Content |
|---|---|
| **Accueil** | Greeting; store card (open/closed with icon + text, name, address); **setup checklist** while incomplete; pull-to-refresh. |
| **Catalogue** | Active products grouped by category (+ "Sans catégorie"), category filter chips (when categories exist), a switch on each row, unavailable rows labelled "Indisponible" (icon + text), "Ajouter un produit", "Gérer les catégories" in the app bar, pull-to-refresh, empty / loading / error states. |
| **Magasin** | Open/closed switch (saves immediately), store details form + **Enregistrer**, sign out. |

**Dashboard (V1, deliberately minimal):** store state + checklist *Créer une catégorie · Ajouter un produit · Ouvrir le magasin*. Steps are read from the backend (≥ 1 category, ≥ 1 **active** product, `isOpen`). The checklist disappears when all three are done; if the owner later closes the store it returns with only "Ouvrir le magasin" open. Open steps are tappable (to the category screen, the Catalogue tab, the Magasin tab). Refreshes when the Accueil tab is opened. Order counters will be added as another section of the same list (marked in `owner_home_view.dart`). No charts, revenue, fake numbers or shortcut grid.

### 7.3 Catalogue and product editor

- Category screen: list, add / rename (one shared dialog — the only field is the name), delete with confirmation; server errors (duplicate name) stay inside the dialog.
- **Product editor** (one screen for create and edit): sale unit first (À la pièce / Au kilo / Au litre) → the price label adapts; "Par tranche de" chips per unit; minimum and optional maximum are steppers that move by the step, so values stay aligned by construction; a live preview **generated from the settings** ("Le client pourra commander : 500 g, 1 kg, 1,5 kg…" / "1, 2, 3 pièces…") plus the exact price of the minimum quantity. Changing the unit resets quantities to that unit's defaults. Edit mode adds "Supprimer du catalogue" (confirmation, then archives).
- Prices are typed in dinars (`1,8` or `1.800`) and parsed to millimes without floating point.
- Client-side validation mirrors the backend limits (text length, http(s) photo link) with French messages.

## 8. Database

- Migrations live in `backend/migrations/` (Prisma 8 formal path: `migration plan` → `db migrate`): `baseline` (schema that existed before migrations were tracked), `owner_store_foundation`, `add_category`, `add_product`.
- `owner_store_foundation` **backfilled** rows that predate it: stores without an address got `Adresse à renseigner`; users without a phone got `inconnu-<id>` (they could never log in by phone). Only local dev data existed.
- Workflow: edit `contract.prisma` → `npm run contract:emit` → `npx prisma migration plan --name <slug>` → fill any data-transform placeholders → `node migrations/app/<dir>/migration.ts` → `npx prisma db migrate --db "$DATABASE_URL"`.
- `contract.d.ts`/`contract.json` are generated; do not hand-edit (Prettier will flag `contract.d.ts` — that is expected).

## 9. Testing

| Suite | Command | What it covers |
|---|---|---|
| Backend unit | `cd backend && npm run test` | DTO validation, `RolesGuard`, product rules + line totals |
| Backend e2e | `cd backend && npm run test:e2e` | HTTP + real Postgres: auth, roles, store/category/product behavior, isolation, constraints, the route-table regression net |
| Flutter | `cd mobile && flutter test` | Widget + unit tests with fake repositories: routing, session lifecycle, dashboard, catalogue, editor, formatters |
| Owner smoke | see below | The real app UI against a real backend, whole lifecycle |

The e2e suite writes real rows, so it runs against a **separate database** (`<DATABASE_URL db name>_test`, or `TEST_DATABASE_URL`) and refuses to start otherwise. One-time setup (dev Postgres container):

```bash
docker exec infrastructure-postgres-1 psql -U grocery_user -d postgres -c 'CREATE DATABASE grocery_db_test'
cd backend && npx prisma db migrate --db "<DATABASE_URL>_test"
```

Re-run the `db migrate` whenever new migrations are added.

**Owner smoke test** (`mobile/test_smoke/owner_smoke_test.dart`, not part of `flutter test`): registers an owner, creates/edits the store, creates/renames a category, creates a piece and a kg product, toggles availability, edits and archives a product, checks the dashboard checklist, restarts the app (new app instance over the stored session) at each routing state, logs out and restarts once more. Run it against a throwaway backend on the test database:

```bash
cd backend && npm run build
DATABASE_URL="<DATABASE_URL>_test" PORT=3001 node dist/main &      # test DB, never the dev one
cd ../mobile && flutter test test_smoke --dart-define=API_BASE_URL=http://localhost:3001
```

## 10. V1 scope

**MUST HAVE (Owner V1) — built**
Owner authentication and security · store management · categories · products · units and quantity rules · product availability · archiving · owner shell · dashboard/setup state.

**LATER — not built**
Orders (and enforcing `isOpen`) · opening hours · push notifications / new-order awareness · real weight / final price · packaging labels · inventory/stock counts · multi-store · staff accounts · image upload · restoring archived products · manual category/product ordering · WhatsApp / n8n / LLM automation.

**DO NOT BUILD**
Delivery · online payment · loyalty · promotions · analytics/charts · suppliers · accounting.

## 11. Known limitations and issues

- Owner self-registration is open; there is no approval step. One phone number = one account = one role.
- Photos (store, user, product) are URL strings; there is no upload or storage. Product photos are not displayed anywhere yet.
- `isOpen` is not enforced (no orders yet). No opening hours.
- Product names are unique among active products per store; archived products cannot be restored or edited.
- `isAvailable` is a manual flag, not inventory.
- A JWT that expires (7 days) **while the app is in use** is not handled centrally: calls start failing and the owner must restart or log out (the check at app start is handled).
- No rate limiting on login; the Swagger UI (`/api`) is served publicly. Both are fine for local development and must be revisited before any deployment.
- `app.module.ts` still registers `ObserveModule` with placeholder credentials (scaffold); it logs a harmless telemetry 401 at start. It is unrelated to the product and should be removed or configured.
- Client-facing user `photo` on registration is not URL-validated (only store/product photos are).
- No automated test drives a real device/keyboard; keyboard behavior was checked on the iOS simulator only.

## 12. Unresolved business decisions

These gate the phases after this one; nothing built so far depends on them.

1. Currency and minor unit — TND with millimes is **assumed and implemented**; confirm it.
2. Weighed items: "estimated total, settled at the counter" vs recording the real weight. (The line-total rule computes the *estimated* total from the ordered quantity.)
3. Pickup timing: pickup windows? No-show deadline after READY?
4. Out-of-stock during preparation: cancel the whole order, or adjust a line?
5. Can a customer cancel, and until which status?
6. New-order awareness without push notifications (in-app refresh only in V1?).
7. Opening hours: manual toggle only, or also free-text hours?
8. Store contact number: owner's phone/WhatsApp, or a store-level number?
9. Image upload: keep URL strings, or add `image_picker` + storage (local disk vs S3-compatible)? Also whether to add an optional `packagingLabel` to products.
10. Owner sign-up: open or approved.
11. One person as both owner and customer.
12. Order lifecycle vs `design.md` (`Preparing`, `Uncollected`): the review proposed dropping `PREPARING` and naming the terminal state `NO_SHOW`; `design.md` is unchanged until decided.
