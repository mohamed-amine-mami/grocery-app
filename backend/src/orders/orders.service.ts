import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { db } from '../prisma/db.js';
import {
  lineTotalMillimes,
  requestedQuantityErrors,
} from '../products/product-rules.js';
import {
  toStoreProductEntity,
  type OfferingWithCatalog,
} from '../store-products/store-product.mapper.js';
import { OrderActorType } from './order-actor-type.enum.js';
import {
  duplicateLines,
  idempotencyKeyReused,
  insufficientStock,
  invalidPickupTime,
  invalidQuantity,
  productUnavailable,
  storeClosed,
  storeProductsNotFound,
} from './order-errors.js';
import {
  generateOrderCode,
  orderTotalMillimes,
  pickupTimeError,
} from './order-rules.js';
import { loadOrder, type Tx } from './order-records.js';
import { OrderStatus } from './order-status.enum.js';
import type {
  CreateOrderCommand,
  CreateOrderResult,
  InvalidQuantityLine,
  OrderRecord,
  UnavailableLine,
} from './order.types.js';

/** Constraint names created by the orders migration. */
const CODE_UNIQUE = 'Order_code_key';
const IDEMPOTENCY_UNIQUE = 'Order_customerId_idempotencyKey_key';

/** A 6-character code colliding with another is astronomically unlikely; a few retries are plenty. */
const MAX_CODE_ATTEMPTS = 5;

const MAX_IDEMPOTENCY_KEY_LENGTH = 100;

/** The violated unique constraint's name when `error` is a unique violation (SQLSTATE 23505). */
function uniqueViolation(error: unknown): string | undefined {
  if (typeof error !== 'object' || error === null) return undefined;
  const { sqlState, constraint, message } = error as {
    sqlState?: string;
    constraint?: string;
    message?: string;
  };
  if (sqlState !== '23505') return undefined;
  if (constraint) return constraint;
  return [CODE_UNIQUE, IDEMPOTENCY_UNIQUE].find((name) =>
    message?.includes(name),
  );
}

/**
 * Places orders. Channel-agnostic: it takes plain values (`CreateOrderCommand`)
 * and knows nothing about HTTP, JWTs or any channel, so the app's controller
 * and, later, WhatsApp/n8n share it. The contract is `docs/orders.md`; what is
 * orderable and which quantities are valid come from `product-rules.ts`, the
 * pickup bounds and totals from `order-rules.ts`.
 *
 * `createOrder` is one transaction: the order, its items, the initial status
 * event and every stock decrement commit together, or none of them do.
 *
 * Validation order, after the idempotent replay check (see below): customer →
 * store → store open → every store product belongs to the store → every one
 * is orderable → quantities → pickup time → no duplicate lines. Each of the
 * line checks reports *all* offending lines at once.
 *
 * Idempotency: `(customerId, idempotencyKey)` is unique. Retrying a key returns
 * the order it created (`created: false`) — even if the store has closed or the
 * stock has gone since, so the check comes first. If the key is reused for a
 * *different* request (another store, other lines or quantities, or another
 * pickup time) the retry is rejected with 409 `IDEMPOTENCY_KEY_REUSED` rather
 * than silently answered with an order the customer did not ask for. Two
 * simultaneous retries are serialised by the unique index: the loser rolls back
 * (releasing its stock) and returns the winner's order.
 */
@Injectable()
export class OrdersService {
  async createOrder(command: CreateOrderCommand): Promise<CreateOrderResult> {
    assertWellFormed(command);

    for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt += 1) {
      try {
        return await db.transaction((tx) =>
          this.createInTransaction(tx, command, generateOrderCode()),
        );
      } catch (error) {
        const constraint = uniqueViolation(error);
        if (constraint === CODE_UNIQUE) continue; // try another code
        if (constraint === IDEMPOTENCY_UNIQUE) {
          // A concurrent request with this key committed first. Our transaction
          // has rolled back, so answer with the order that won.
          return db.transaction((tx) => this.replay(tx, command));
        }
        throw error;
      }
    }
    throw new Error('Could not generate a unique order code');
  }

  private async replay(
    tx: Tx,
    command: CreateOrderCommand,
  ): Promise<CreateOrderResult> {
    const existing = await tx.orm.public.Order.first({
      customerId: command.customerId,
      idempotencyKey: command.idempotencyKey,
    });
    if (!existing) {
      // The winner we collided with cannot vanish (orders are never deleted).
      throw new Error('Order for this idempotency key not found');
    }
    const order = await loadOrder(tx, existing);
    assertSameRequest(order, command);
    return { order, created: false };
  }

  private async createInTransaction(
    tx: Tx,
    command: CreateOrderCommand,
    code: string,
  ): Promise<CreateOrderResult> {
    const { customerId, storeId, lines, requestedPickupAt } = command;

    // The idempotent replay comes first: a retry must get its original order
    // even if the store has closed or the stock has run out since.
    const existing = await tx.orm.public.Order.first({
      customerId,
      idempotencyKey: command.idempotencyKey,
    });
    if (existing) {
      const order = await loadOrder(tx, existing);
      assertSameRequest(order, command);
      return { order, created: false };
    }

    // 1. The customer exists and is a CLIENT.
    const customer = await tx.orm.public.User.first({ id: customerId });
    if (!customer) {
      throw new NotFoundException(`Customer ${customerId} not found`);
    }
    if (customer.role !== 'CLIENT') {
      throw new ForbiddenException('Only customers can place orders');
    }

    // 2–3. The store exists and is open.
    const store = await tx.orm.public.Store.first({ id: storeId });
    if (!store) {
      throw new NotFoundException(`Store ${storeId} not found`);
    }
    if (!store.isOpen) {
      throw storeClosed();
    }

    // 4. Every store product belongs to this store (another store's is "not found").
    const offerings = new Map<number, OfferingWithCatalog>();
    for (const { storeProductId } of lines) {
      if (offerings.has(storeProductId)) continue;
      const row = await tx.orm.public.StoreProduct.where({
        id: storeProductId,
        storeId,
      })
        .include('product', (product) => product.include('category'))
        .first();
      if (row) offerings.set(storeProductId, row as OfferingWithCatalog);
    }
    const missing = unique(
      lines
        .map((line) => line.storeProductId)
        .filter((id) => !offerings.has(id)),
    );
    if (missing.length > 0) throw storeProductsNotFound(missing);

    // 5. Every store product is currently orderable — the canonical rule, via
    // the same mapper the API uses; nothing is recomputed here.
    const entities = new Map(
      [...offerings].map(([id, row]) => [id, toStoreProductEntity(row)]),
    );
    const unavailable: UnavailableLine[] = [];
    for (const id of unique(lines.map((line) => line.storeProductId))) {
      const entity = entities.get(id)!;
      if (!entity.isOrderable) {
        unavailable.push({
          storeProductId: id,
          reason: entity.unavailabilityReason!,
        });
      }
    }
    if (unavailable.length > 0) throw productUnavailable(unavailable);

    // 6. Quantities satisfy the store product's min / step / max.
    const badQuantities: InvalidQuantityLine[] = [];
    for (const line of lines) {
      const entity = entities.get(line.storeProductId)!;
      const errors = requestedQuantityErrors(line.quantity, {
        saleUnit: entity.saleUnit,
        minQuantity: entity.minQuantity,
        quantityStep: entity.quantityStep,
        maxQuantity: entity.maxQuantity,
      });
      if (errors.length > 0) {
        badQuantities.push({ storeProductId: line.storeProductId, errors });
      }
    }
    if (badQuantities.length > 0) throw invalidQuantity(badQuantities);

    // 7. The pickup time is within the bounds.
    const pickupError = pickupTimeError(requestedPickupAt, new Date());
    if (pickupError) throw invalidPickupTime(pickupError);

    // 8. No store product appears twice.
    const duplicated = lines
      .map((line) => line.storeProductId)
      .filter((id, index, ids) => ids.indexOf(id) !== index);
    if (duplicated.length > 0) throw duplicateLines(unique(duplicated));

    // Snapshot: name, unit and price come from the server, never the client.
    const snapshots = lines.map((line) => {
      const entity = entities.get(line.storeProductId)!;
      return {
        storeProductId: line.storeProductId,
        tracked: entity.trackStock,
        productNameSnapshot: entity.product.name,
        saleUnitSnapshot: entity.saleUnit,
        unitPriceMillimes: entity.priceMillimes,
        quantity: line.quantity,
        lineTotalMillimes: lineTotalMillimes(
          entity.saleUnit,
          entity.priceMillimes,
          line.quantity,
        ),
      };
    });
    const total = totalOrThrow(snapshots);

    // The order row goes in first: a concurrent request with the same key
    // blocks on the unique index here, before it touches any stock.
    const order = await tx.orm.public.Order.create({
      code,
      customerId,
      storeId,
      requestedPickupAt: requestedPickupAt.toISOString(),
      totalMillimes: total,
      idempotencyKey: command.idempotencyKey,
    });

    // Stock: conditional atomic decrements, in a stable id order so two orders
    // with overlapping lines cannot deadlock. A zero-row update aborts the whole
    // transaction (INSUFFICIENT_STOCK) — except when tracking was switched off
    // since we read the row, in which case there is nothing to decrement.
    const decremented = new Map<number, number>();
    const byId = [...snapshots].sort(
      (a, b) => a.storeProductId - b.storeProductId,
    );
    for (const line of byId) {
      if (!line.tracked) {
        decremented.set(line.storeProductId, 0);
        continue;
      }
      const plan = db.raw
        .sql`UPDATE "StoreProduct" SET "stockQuantity" = "stockQuantity" - ${line.quantity}, "updatedAt" = now() WHERE "id" = ${line.storeProductId} AND "trackStock" = true AND "stockQuantity" >= ${line.quantity}`
        .affectedCount()
        .build();
      const { affectedRows } = await tx.execute(plan);
      if (affectedRows === 1) {
        decremented.set(line.storeProductId, line.quantity);
        continue;
      }
      const current = await tx.orm.public.StoreProduct.first({
        id: line.storeProductId,
      });
      if (current && !current.trackStock) {
        decremented.set(line.storeProductId, 0);
        continue;
      }
      throw insufficientStock(line.storeProductId);
    }

    for (const line of snapshots) {
      await tx.orm.public.OrderItem.create({
        orderId: order.id,
        storeProductId: line.storeProductId,
        productNameSnapshot: line.productNameSnapshot,
        saleUnitSnapshot: line.saleUnitSnapshot,
        unitPriceMillimes: line.unitPriceMillimes,
        quantity: line.quantity,
        lineTotalMillimes: line.lineTotalMillimes,
        stockDecrementedQuantity: decremented.get(line.storeProductId)!,
      });
    }

    await tx.orm.public.OrderStatusEvent.create({
      orderId: order.id,
      fromStatus: null,
      toStatus: OrderStatus.PENDING,
      actorType: OrderActorType.CLIENT,
      actorId: customerId,
      reason: null,
    });

    return { order: await loadOrder(tx, order), created: true };
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

const unique = (ids: number[]) => [...new Set(ids)];

/** Shape checks that need no database: an order needs lines, and the key must be usable. */
function assertWellFormed(command: CreateOrderCommand): void {
  if (command.lines.length === 0) {
    throw new BadRequestException('An order needs at least one line');
  }
  for (const line of command.lines) {
    if (!Number.isInteger(line.storeProductId) || line.storeProductId <= 0) {
      throw new BadRequestException(
        'Every line needs a valid store product id',
      );
    }
  }
  const key = command.idempotencyKey;
  if (key.trim().length === 0 || key.length > MAX_IDEMPOTENCY_KEY_LENGTH) {
    throw new BadRequestException(
      `idempotencyKey must be 1–${MAX_IDEMPOTENCY_KEY_LENGTH} characters`,
    );
  }
}

/** The total, or a 400 when it is out of range for the column or not positive. */
function totalOrThrow(lines: { lineTotalMillimes: number }[]): number {
  let total: number;
  try {
    total = orderTotalMillimes(
      lines.map((line) => ({ ...line, removedAt: null })),
    );
  } catch {
    throw new BadRequestException('The order total is too large');
  }
  if (total <= 0) {
    throw new BadRequestException('The order total must be positive');
  }
  return total;
}

/** A replay must describe the same request: same store, pickup time and lines (removed ones included). */
function assertSameRequest(
  order: OrderRecord,
  command: CreateOrderCommand,
): void {
  const sameStore = order.storeId === command.storeId;
  const samePickup =
    new Date(order.requestedPickupAt).getTime() ===
    command.requestedPickupAt.getTime();
  const signature = (lines: { storeProductId: number; quantity: number }[]) =>
    lines
      .map((line) => `${line.storeProductId}x${line.quantity}`)
      .sort()
      .join(',');
  if (
    !sameStore ||
    !samePickup ||
    signature(order.items) !== signature(command.lines)
  ) {
    throw idempotencyKeyReused();
  }
}
