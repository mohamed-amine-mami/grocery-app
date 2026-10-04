# Orders V1 contract

Frozen before implementation; the services and HTTP API are now built. This is the source of truth for the Orders phase; if code and this file disagree, fix one of them deliberately. Rules that live in code are referenced, not restated: whether a StoreProduct can be ordered, and the unit, quantity and stock validation, are in `backend/src/products/product-rules.ts`. Catalog and StoreProduct architecture: `owner-domain.md`. UI/UX: `design.md`.

## 1. Principles

- Pickup only, pay at the store. One order belongs to exactly one Store and one customer (a `User` with role CLIENT).
- Money is integer millimes and quantities are integer base units (pieces / g / mL), as everywhere else. The client never sends prices.
- The core logic lives in a channel-agnostic order service (create and transitions) that takes plain parameters (customer, store, lines, pickup time, idempotency key) and knows nothing about HTTP or the JWT. Controllers only authenticate, validate DTOs and call it. Flutter and, later, WhatsApp/n8n use the same service.
- No Cart table: the cart is local to the Flutter app, scoped to one Store.

## 2. Data (conceptual; exact types and constraints are chosen at schema design)

**Order**: `id` (integer), `code` (short, human-friendly, unique), `storeId`, `customerId`, `status`, `requestedPickupAt`, `totalMillimes`, `idempotencyKey` (unique per customer), `createdAt`, `updatedAt`.
There are no `confirmedAt`, `readyAt`, `completedAt`, `cancelledAt` or `storeAdjusted` columns and no payment fields: history comes from the events, and `storeAdjusted` is derived (any item with `removedAt`).

**OrderItem**: `orderId`, `storeProductId` (`Restrict` foreign key), `productNameSnapshot`, `saleUnitSnapshot`, `unitPriceMillimes`, `quantity` (base units), `lineTotalMillimes`, `stockDecrementedQuantity`, `removedAt` (nullable).

**OrderStatusEvent** (append-only): `orderId`, `fromStatus` (null for the creation event), `toStatus`, `actorType`, `actorId` (null when not applicable), `reason` (nullable), `createdAt`.

## 3. Lifecycle

```
PENDING → CONFIRMED → READY_FOR_PICKUP → COMPLETED
PENDING → CANCELLED
CONFIRMED → CANCELLED
READY_FOR_PICKUP → NO_SHOW
```

Terminal: `COMPLETED`, `CANCELLED`, `NO_SHOW`. There is no `PREPARING`, `REJECTED` or `EXPIRED`, and nothing reopens a terminal order.

| Transition | Who |
|---|---|
| `PENDING → CONFIRMED` | owner (may remove lines, see 6) |
| `CONFIRMED → READY_FOR_PICKUP` | owner |
| `READY_FOR_PICKUP → COMPLETED` | owner (handed over and paid at the store) |
| `READY_FOR_PICKUP → NO_SHOW` | owner, manually; never automatic. UI label: "Non retirée" (a calm state, see `design.md`) |
| `PENDING` or `CONFIRMED → CANCELLED` | the customer or the owner (see 8) |

- Owner declining a pending order is `CANCELLED` with `cancelledBy = STORE` and a reason. `cancelledBy` is not a column: it is the actor type of the cancellation event.
- Every transition is a guarded update (`WHERE status = <expected>`) written together with its event in one transaction. Whoever loses a race changes nothing.
- A request for the status the order already has returns the current order with HTTP 200 and writes no event. A genuinely invalid transition is 409 `ORDER_STATE_CHANGED`.

## 4. Creating an order

The customer submits `storeId`, lines `{ storeProductId, quantity }`, `requestedPickupAt` and an idempotency key. The backend, in one transaction:

1. checks the caller is a CLIENT and the store is open (6);
2. checks every StoreProduct belongs to that store and is currently orderable per `product-rules.ts`, and every quantity satisfies its unit and min/step/max rules; duplicate lines are rejected;
3. validates the pickup time (7);
4. snapshots name, unit and price, and computes line totals and the total;
5. decrements tracked stock atomically (5);
6. creates the order, its items and the initial event.

The validation phase reports every offending line, each identified by `storeProductId`. Customers are never told actual stock quantities. A repeated creation with the same idempotency key (same customer) returns the original order instead of creating another, even if the store has since closed or the stock run out. If the key is reused for a *different* request (another store, other lines or quantities, or another pickup time) it is rejected with 409 `IDEMPOTENCY_KEY_REUSED` rather than answered with an order the customer did not ask for. Two simultaneous retries cannot both create one: the unique index serialises them, the loser rolls back and returns the winner's order. A retry is checked before anything else, so it is never refused for a reason that arose after the original succeeded.

## 5. Stock

- `StoreProduct.stockQuantity` means **the quantity currently available for new orders**: it is already net of open orders. An owner who counts the shelf should not count goods already set aside for an order.
- Tracked stock is decremented at creation, atomically and conditionally, in a stable line order. If any line cannot be satisfied the whole order fails and nothing is decremented.
- `OrderItem.stockDecrementedQuantity` records exactly how much was decremented for that line. Untracked products get `0` (or the equivalent nullable representation chosen at schema design) and are never restored.
- Stock is restored when the order becomes `CANCELLED` or `NO_SHOW`, and when the owner removes a line. It is never changed on `COMPLETED`.
- Restoration happens exactly once: only after the guarded transition (or the line's `removedAt` update, applied only where it is still null) has succeeded, in the same transaction, using the recorded `stockDecrementedQuantity`. A cancel or no-show restores only the lines that are not removed. The recorded quantity is a historical fact and is not edited. The restore applies only while the StoreProduct still tracks stock.

## 6. Owner adjustment and store state

- When confirming, the owner may remove lines. Removed items stay in the database with `removedAt`, remain visible in the order history, no longer count toward the total (recomputed by the server), and have their stock restored once.
- If every line would be removed, the owner must cancel the order instead.
- Lines can only be removed by the confirmation that moves the order from `PENDING` to `CONFIRMED`, and only the request that wins that guarded transition removes them (together with the stock restore, in the same transaction). A confirm that finds the order already `CONFIRMED` (a retry, or the other of two simultaneous confirms) is the idempotent same-status case: it returns the current order with `changed: false`, and its removal list is **ignored**, not applied and not validated. Once the order is `READY_FOR_PICKUP` or terminal, a confirm is 409 `ORDER_STATE_CHANGED`. Lines are never removed after confirmation; a client must compare the returned order with what it asked for.
- No quantity reduction and no substitution.
- `Store.isOpen = false` prevents **new** orders only (`STORE_CLOSED`). Existing orders, and what the owner and customer can do with them, are unaffected. Customers can still browse a closed store.

## 7. Pickup

`requestedPickupAt` is an advisory time, not a slot and not a capacity reservation. At creation it must be at least 30 minutes and at most 48 hours from now. There are no slots, no capacity and no opening-hours scheduling. Flutter offers 30-minute steps.

## 8. Cancellation

The customer may cancel `PENDING` and `CONFIRMED` orders. The owner may cancel `PENDING` and `CONFIRMED` orders. Neither can cancel `READY_FOR_PICKUP` (it ends in `COMPLETED` or `NO_SHOW`). Cancellation is terminal. An owner cancellation carries a reason the customer can read.

## 9. Pricing and payment

The total is computed by the server from the items, in integer millimes, using the exact line-total function in `product-rules.ts`. For weighed products (kg or L) the customer sees the total as estimated; there is no final-weight workflow. No payment fields exist: payment happens at the store and `COMPLETED` means handed over and paid.

## 10. Identity

An integer primary key, a short unique human-friendly `code`, and a customer-supplied idempotency key (unique per customer). The `code` is the order reference and the pickup code; it is **not** an authentication secret.

## 11. Errors

Stable `code` values, as implemented by the order service (`backend/src/orders/order-errors.ts`; `ORDER_STATE_CHANGED` is in `order-rules.ts`):

| Code | HTTP | Meaning |
|---|---|---|
| `STORE_CLOSED` | 409 | The store is not accepting new orders |
| `PRODUCT_UNAVAILABLE` | 409 | Lines whose StoreProduct is not orderable; `lines: [{ storeProductId, reason }]` lists all of them |
| `INSUFFICIENT_STOCK` | 409 | Tracked stock could not cover a line at the moment of the decrement; names `storeProductId`, reveals no quantity |
| `INVALID_QUANTITY` | 400 | Quantities that break the unit or min/step/max rules; `lines: [{ storeProductId, errors }]` lists all of them |
| `INVALID_PICKUP_TIME` | 400 | `requestedPickupAt` is outside the bounds in 7 |
| `IDEMPOTENCY_KEY_REUSED` | 409 | The key was already used for a different request (see 4) |
| `ORDER_STATE_CHANGED` | 409 | The transition is not valid for the order's current status |

Other creation failures carry no code: 400 for an empty order, a bad idempotency key, duplicate lines (`storeProductIds`) or a total that is not positive or too large; 404 for an unknown customer or store, or for StoreProducts that are not in the requested store (`storeProductIds`; another store's product is indistinguishable from a missing one); 403 when the customer is not a CLIENT.

`STOCK_CHANGED` (owner stock edits) is separate and unchanged.

## 12. API surface

Implemented by `orders.controller.ts` and `owner-orders.controller.ts`; controllers only authenticate, check the role, validate the DTO and call the services. The customer or owner always comes from the JWT.

Customer (CLIENT; owners get 403): `GET /stores`, `GET /stores/:id/products`, `POST /orders`, `GET /orders?page&limit`, `GET /orders/:id`, `POST /orders/:id/cancel` (optional `reason`).
Owner (OWNER, scoped to the owner's store; clients get 403): `GET /owner/orders?page&limit&status`, `GET /owner/orders/:id`, `POST /owner/orders/:id/confirm` (optional `removeItemIds`), `…/ready`, `…/complete`, `…/cancel` (required `reason`), `…/no-show`.

- `GET /stores` lists every store, closed ones included, with customer-safe fields only (id, name, description, photo, address, coordinates, `isOpen`). `GET /stores/:id/products` lists that store's own offerings (its price, unit and quantity rules, the product's name, description, photo and category), by category then name; 404 for an unknown store. Offerings the store archived and products or categories archived in the catalog are not listed; every listed one carries `isOrderable` and, when false, `unavailabilityReason` (`OWNER_DISABLED`, `OUT_OF_STOCK`, `STOCK_BELOW_MINIMUM`), both derived by `product-rules.ts` on each read. No stock figure, tracking flag or owner data is returned. The list is for browsing only: `POST /orders` revalidates every line.
- An order that is not the caller's (another customer's, or another store's) is the same 404 as a missing one, decided inside the query (`WHERE id = ? AND customerId = ?` / `storeId = ?`), never by loading it first. An owner with no store gets 404 on the list.
- `POST /orders` answers **201** for a new order and **200** for an idempotent replay. Transition endpoints answer 200 with `{ changed, order }`; `changed: false` is the same-status case (a confirm's removal list is then ignored, see 6).
- Lists are newest first (`createdAt`, then `id`), `page` from 1, `limit` 1–50 (default 20), and answer `{ items, page, limit, total }`. `status` is the only filter. A bad `page`, `limit` or `status` is a plain 400.
- Responses are explicit DTOs. A customer sees code, status, pickup time, items (snapshot name, unit, quantity, prices, `removedAt`), total, `storeAdjusted`, the store, and the status history with reasons (the actor type tells a store cancellation from a customer one). An owner sees the same plus the customer's name and phone instead of the store. `stockDecrementedQuantity`, `stockQuantity` and the idempotency key appear in no response.
- Body fields that are not in the DTO (prices, totals, status, stock, quantities on a confirm) are rejected with a plain 400.

## 13. Notifications

V1 is polling and pull-to-refresh, with a count of `PENDING` orders for the owner. No push, no WebSockets and no automatic WhatsApp messages.

## 14. Out of V1

Open-order cap (the abuse risk is accepted), pickup slots and capacity, automatic expiry, quantity reduction, substitution, reserved stock, payment status or method, a server-side cart, multi-store orders, per-store order numbers, opening hours.
