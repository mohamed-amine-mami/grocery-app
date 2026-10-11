# GrocerGo — pickup-only grocery app

Portfolio project. Pickup only: no delivery. `backend/` NestJS (ESM) + Prisma 8 (`@prisma/orm-postgres`) + PostgreSQL · `mobile/` Flutter · `infrastructure/` docker-compose (Postgres) · `docs/`. No root package manager: run each app from its own directory.
Docs: `docs/owner-domain.md` (owner workflow and API surface) · `docs/orders.md` (Orders V1 contract; backend services, HTTP API, owner orders UI and customer ordering UI built) · `docs/design.md` (UI/UX source of truth — read it before any Flutter UI work).

## Conventions
- UI text is French; API error messages are English (Flutter maps status/`code` to French). The only stable error `code` built so far is `STOCK_CHANGED` (409); the Orders codes are listed in `docs/orders.md`.
- Money = integer millimes (1800 = 1,800 DT). Quantities = integer base units (pieces / grams / mL). No floats for money or quantities.
- Owner routes: `JwtAuthGuard` + `RolesGuard` + `@Roles(OWNER)`. The owner comes from the JWT, never the body or URL; scope by `storeId`.
- Controllers thin, logic in services, DTOs with class-validator. Every endpoint is documented in Swagger and matches real behavior. After an API change, check the OpenAPI document (the route-guards e2e builds it) and the e2e tests before touching Flutter.
- Flutter: data/logic out of widgets; reuse the theme and shared widgets; no new design tokens.

## Architecture (decided; schema in `backend/src/prisma/contract.prisma`)
Category → Product (global catalog) → StoreProduct (a store's offering) → Store.
- Global Category/Product carry no store, price, stock or availability. Owners cannot write them; only the importer does. A `slug` is a permanent identity: renaming keeps the slug. The importer never touches StoreProduct.
- StoreProduct owns price, sale unit, quantity rules, stock, owner availability and archive state. Archive, never delete.
- Customer availability is derived, never stored. `isOrderable` / `unavailabilityReason`, and the unit and stock validation, live in `backend/src/products/product-rules.ts` — that file is the rule; don't restate it.
- Stock edits send `expectedStockQuantity`. Orders (`docs/orders.md`) decrement tracked stock atomically at placement, inside one `db.transaction`, with order logic in a channel-agnostic service, not in controllers.
- Images: `backend/src/images/` — depend on `ImageStorageService` (import `ImagesModule`), never on Cloudinary directly; only `CloudinaryImageStorage` imports the SDK. Tests use `InMemoryImageStorage`. `CLOUDINARY_*` env vars (server-side only); unset → app starts, uploads answer 503.
- Not started — don't build unless asked: WhatsApp/n8n/LLM, payments, notifications, deployment.

## Commands and environment
- Postgres: Docker Desktop running (`open -a Docker`), then `docker compose up -d` in `infrastructure/`. Test DB `grocery_db_test` (= dev `DATABASE_URL` + `_test`).
- Backend (`backend/`): `npm run lint | test | test:e2e | build | format`. E2E refuses any non-`_test` DB. Never hand-edit the generated `contract.d.ts` / `contract.json`: run `npm run contract:emit`.
- Catalog: `npm run catalog:import` (use `-- --dry-run` first). Source: `backend/seed/catalog.json`.
- Migrations: edit the contract → `contract:emit` → `npx prisma migration plan --name <slug>` (add `--from <migration-dir>` when the `db` ref is stale; `migrations/app/refs/db.json` currently is) → `npx prisma db migrate --db "<url>"`, on the dev AND the test DB. A hand-edited `migration.ts` must be re-emitted with `node migrations/app/<dir>/migration.ts`. Destructive migrations carry an opt-in guard: only the user applies them; never run one on your own.
- Flutter (`mobile/`): `flutter analyze && flutter test`. Smoke tests (`test_smoke/`: the owner lifecycle and the whole customer → owner → customer ordering journey, real UI over real HTTP; not part of `flutter test`): run `catalog:import` against the test DB, start the backend with `DATABASE_URL=<…>_test PORT=3001 node dist/main`, then `flutter test test_smoke --dart-define=API_BASE_URL=http://localhost:3001`. Empty the test DB afterwards (the smoke tests leave their stores and users behind). The app itself talks to `http://localhost:3000` (`ApiClient.defaultBaseUrl`).

## Gotchas
- `tsc --noEmit` reports old TS2883 errors in migration/config files — not regressions. `nest build` is the real check.
- `backend/test/route-guards.e2e-spec.ts` pins the exact route set: adding a route means editing it.
- E2E suites share one database: seed tagged catalog rows with `test/catalog-helpers.ts`, delete store products before products, and never assume the global tables are empty.
- zsh on macOS: no `echo =====`; use `pipestatus`, not `PIPESTATUS`. The iOS simulator types with an AZERTY mapping: use letters identical on both layouts in passwords.

- iOS simulator: build with `flutter build ios --simulator --debug` (signed). A `--no-codesign` build installs but hangs on the splash (the Keychain read never returns).

## Working style
- Phase by phase: do exactly what the prompt asks, then stop and report; never start the next phase. Read the relevant code first; make focused edits; no new dependencies, abstractions, columns or features without a concrete need.
- State irreversible or architectural decisions before making them. Never commit secrets or `.env`. Keep commits scoped to one feature or fix.
- Verify by running the tests/lint/build. Report honestly: what ran, what failed, what was not run or could not be verified, and anything changed beyond the ask. Keep reports short: results, deviations, open decisions.
- Use the installed skills (`nestjs-expert`, `design-system`, `accessibility-review`, `n8n-*`, Context7 for library docs) only when they fit the task.
