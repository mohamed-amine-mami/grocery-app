# Grocery Pickup App

Engineering/portfolio project: a **pickup-only** grocery ordering app. No delivery flow exists or is planned.

* `backend/` — NestJS (TypeScript, ESM), Prisma 8 (`@prisma/orm-postgres`), PostgreSQL
* `mobile/` — Flutter/Dart
* `infrastructure/` — docker-compose (Postgres for local dev)
* `docs/` — architecture notes, API contracts, decisions (put detail here, not in this file). Owner domain rules: `docs/owner-domain.md`; UI/UX: `docs/design.md`

No root-level package manager — each app is built/run from its own directory.

## Current phase

Early development. Authentication (phone + password, JWT, roles) and the **Owner V1** (store, categories, products, dashboard) are built — see `docs/owner-domain.md`; orders and the customer side are next. The backend and database foundation come first; Flutter is wired up feature-by-feature only after the corresponding API exists and works.

Per-feature loop: implement in NestJS → document in Swagger → test via Swagger UI → fix → connect Flutter → verify end-to-end → move on.

**Do not build ahead of what's asked.** Leave these until explicitly requested, even though a `User` model with a `role` already exists in the Prisma schema:

WhatsApp integration, n8n workflows, LLM/AI parsing, payments, notifications, deployment setup.

## Backend (`backend/`)

* Package manager: npm. Module system: ESM (`"type": "module"`) — use `import`/`export`, not `require`.
* ORM: **Prisma 8** (`@prisma/orm-postgres`, still pre-1.0) — not TypeORM. Schema lives at `backend/src/prisma/contract.prisma`; run `npm run contract:emit` after editing it.
* Lint: `npm run lint` (oxlint, not eslint). Format: `npm run format` (prettier — single quotes, trailing commas).
* Tests: `npm run test` (vitest, not jest). E2E: `npm run test:e2e` — runs against a separate `*_test` database and refuses the dev one (setup in `docs/owner-domain.md`).
* Migrations: `backend/migrations/` (Prisma 8 `migration plan` + `db migrate`); commit them with the contract change. Workflow in `docs/owner-domain.md`.
* Authorization: owner routes use `JwtAuthGuard` + `RolesGuard` + `@Roles(...)`. Identify the owner from the JWT, never from the request body or URL; scope catalog/order data by `storeId`.
* Keep controllers thin; business logic in services; validate input via DTOs (class-validator).
* Every endpoint must be documented in Swagger and reflect real behavior — no documenting unbuilt functionality. Verify endpoints through Swagger UI, not just by reading the code.
* After changing an API contract, re-check the Swagger schema and manually test the affected endpoints before connecting or updating Flutter.
* Don't add a DB column, relation, or index without a concrete current requirement.
* Do not manually edit generated Prisma/client files; change the Prisma contract/schema and use the project's defined generation commands.

## Mobile (`mobile/`)

* Standard `flutter analyze` / `flutter test` — config in `analysis_options.yaml` (flutter_lints defaults, unmodified). `mobile/test_smoke/` holds an end-to-end owner smoke test against a real backend (how to run it: `docs/owner-domain.md`).
* Keep API/data logic out of widgets. No hardcoded data once a screen is wired to a real endpoint.
* Before adding new screens, reuse the existing theme/design-system foundations (colors, typography, spacing, shared components) rather than redesigning per screen.

## Working style

* Read the relevant existing code before changing it; make focused edits, don't touch unrelated files.
* No new dependencies, abstractions, or unrequested features without a concrete need.
* State important/irreversible architectural decisions before making them.
* Verify claims: run the tests/lint/Swagger check you're relying on rather than asserting it works.
* Use installed skills (`nestjs-expert`, `design-system`, `accessibility-review`, `n8n-*` skills, Context7 for library docs) when they fit the task; don't invoke unrelated ones.
* Never commit secrets or `.env` files. Keep commits scoped to one feature/fix.

