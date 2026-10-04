import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { db } from '../prisma/db.js';
import { OrderActorType } from './order-actor-type.enum.js';
import {
  decideTransition,
  orderStateChanged,
  orderTotalMillimes,
} from './order-rules.js';
import { loadOrder, type OrderRow, type Tx } from './order-records.js';
import { OrderStatus } from './order-status.enum.js';
import type { OrderItemRecord, OrderRecord } from './order.types.js';

/** The user behind a transition. Only customers and owners act on orders here. */
export interface OrderActor {
  type: OrderActorType.CLIENT | OrderActorType.OWNER;
  userId: number;
}

export interface OrderTransitionResult {
  order: OrderRecord;
  /**
   * `false` when the order was already in the requested status: nothing was
   * done and no event was written, and `order` is the current state.
   */
  changed: boolean;
}

export interface ConfirmOptions {
  /** `OrderItem` ids the owner cannot fulfil; they are removed, not deleted. */
  removeItemIds?: number[];
}

const MAX_REASON_LENGTH = 500;

/**
 * Moves orders through their lifecycle. Like `OrdersService` it is
 * channel-agnostic: plain values in, no HTTP, JWT or channel. The contract is
 * `docs/orders.md`; which moves exist is `order-rules.ts`.
 *
 * Every transition runs in one transaction and follows the same shape:
 *
 * 1. Load the order and check the actor may touch it (anyone else gets the same
 *    404 as for a missing order).
 * 2. Same status as requested → return the current order, `changed: false`, no
 *    event, no side effect. A move the lifecycle does not allow → 409
 *    `ORDER_STATE_CHANGED`.
 * 3. Validate anything that could still reject the request (a removal that
 *    would empty the order), before changing anything.
 * 4. The guarded update `UPDATE "Order" SET status = next WHERE id = ? AND
 *    status = <the status read in 1>`. Only the transaction whose update
 *    changes a row may go on. If it changes none, the order was moved by someone
 *    else: reload it; already in the requested status → `changed: false`;
 *    otherwise 409 `ORDER_STATE_CHANGED` (the caller may retry from the new status).
 * 5. The side effects of the winning transition, then its `OrderStatusEvent`,
 *    all in the same transaction. A loser writes no event and touches no stock.
 *
 * Stock. `OrderItem.stockDecrementedQuantity` is the historical record of what
 * the order took from a StoreProduct. It is never modified, and it is the only
 * source of what is given back: not the quantity, not the product's current
 * rules, price, availability, archive state or tracking. Giving back is exactly
 * once because it only happens in a transaction that has just won a one-way
 * change: the move to `CANCELLED` or `NO_SHOW` (restores every line not yet
 * removed), or the removal of a line during confirmation (guarded by
 * `removedAt IS NULL`, and only the winner of the confirmation removes lines).
 * A removed line is excluded from a later cancellation, so it is never restored
 * twice, and `COMPLETED` restores nothing.
 *
 * The restore is `stockQuantity = stockQuantity + n` on the StoreProduct. If the
 * owner has since stopped tracking stock there is no counter to credit, so
 * nothing is written (the transition still succeeds); if tracking was switched
 * on after the order, the line's historical quantity is 0 and nothing is added.
 */
@Injectable()
export class OrderTransitionsService {
  /** Customer: cancel their own `PENDING` or `CONFIRMED` order. The reason is optional. */
  async cancelByCustomer(
    orderId: number,
    customerId: number,
    reason?: string | null,
  ): Promise<OrderTransitionResult> {
    return this.cancel(
      orderId,
      { type: OrderActorType.CLIENT, userId: customerId },
      normalizeReason(reason, false),
    );
  }

  /** Owner: cancel a `PENDING` or `CONFIRMED` order of their store. The customer reads the reason, so it is required. */
  async cancelByOwner(
    orderId: number,
    ownerId: number,
    reason: string,
  ): Promise<OrderTransitionResult> {
    return this.cancel(
      orderId,
      { type: OrderActorType.OWNER, userId: ownerId },
      normalizeReason(reason, true),
    );
  }

  /** Owner: `PENDING → CONFIRMED`, optionally removing the lines they cannot fulfil. */
  async confirm(
    orderId: number,
    ownerId: number,
    options: ConfirmOptions = {},
  ): Promise<OrderTransitionResult> {
    const removeIds = [...new Set(options.removeItemIds ?? [])];
    return this.transition({
      orderId,
      actor: { type: OrderActorType.OWNER, userId: ownerId },
      target: OrderStatus.CONFIRMED,
      reason: null,
      // Validated before anything changes: a rejected adjustment leaves the
      // order, its lines and the stock exactly as they were.
      prepare: (tx, order) => validateRemoval(tx, order, removeIds),
      apply: async (tx, order) => {
        await removeLines(tx, order.id, removeIds);
        // Never trusts the old total: it is rebuilt from the active lines.
        const items = await loadItems(tx, order.id);
        await tx.orm.public.Order.where({ id: order.id }).update({
          totalMillimes: orderTotalMillimes(items),
        });
      },
    });
  }

  /** Owner: `CONFIRMED → READY_FOR_PICKUP`. */
  markReady(orderId: number, ownerId: number): Promise<OrderTransitionResult> {
    return this.transition({
      orderId,
      actor: { type: OrderActorType.OWNER, userId: ownerId },
      target: OrderStatus.READY_FOR_PICKUP,
      reason: null,
    });
  }

  /** Owner: `READY_FOR_PICKUP → COMPLETED` (handed over and paid). Never touches stock. */
  complete(orderId: number, ownerId: number): Promise<OrderTransitionResult> {
    return this.transition({
      orderId,
      actor: { type: OrderActorType.OWNER, userId: ownerId },
      target: OrderStatus.COMPLETED,
      reason: null,
    });
  }

  /** Owner: `READY_FOR_PICKUP → NO_SHOW` (never automatic). Gives the stock back. */
  markNoShow(orderId: number, ownerId: number): Promise<OrderTransitionResult> {
    return this.transition({
      orderId,
      actor: { type: OrderActorType.OWNER, userId: ownerId },
      target: OrderStatus.NO_SHOW,
      reason: null,
      apply: (tx, order) => restoreStockOfActiveLines(tx, order.id),
    });
  }

  private cancel(
    orderId: number,
    actor: OrderActor,
    reason: string | null,
  ): Promise<OrderTransitionResult> {
    return this.transition({
      orderId,
      actor,
      target: OrderStatus.CANCELLED,
      reason,
      apply: (tx, order) => restoreStockOfActiveLines(tx, order.id),
    });
  }

  private transition(args: {
    orderId: number;
    actor: OrderActor;
    target: OrderStatus;
    reason: string | null;
    /** Read-only checks that may still reject the request. */
    prepare?: (tx: Tx, order: OrderRow) => Promise<void>;
    /** Side effects, run only by the transaction that won the guarded update. */
    apply?: (tx: Tx, order: OrderRow) => Promise<void>;
  }): Promise<OrderTransitionResult> {
    const { orderId, actor, target, reason } = args;

    return db.transaction(async (tx) => {
      const order = await loadAuthorizedOrder(tx, orderId, actor);
      const current = order.status as OrderStatus;

      const decision = decideTransition(current, target);
      if (decision === 'unchanged') {
        return { order: await loadOrder(tx, order), changed: false };
      }
      if (decision === 'invalid') {
        throw orderStateChanged(current, target);
      }

      await args.prepare?.(tx, order);

      // The guarded update: one `UPDATE … WHERE id = ? AND status = <read>`
      // that changes a row only if the status is still the one we read; whoever
      // it changes a row for owns the side effects. It must be `updateAndCount`:
      // the ORM's single-row `update()` selects the row first and updates it by
      // id, so after waiting for a concurrent winner's lock it would still
      // "win" (the predicate is not re-checked). A plain conditional UPDATE is
      // re-checked by the database once the lock is released.
      const changedRows = await tx.orm.public.Order.where({
        id: orderId,
        status: current,
      }).updateAndCount({ status: target });

      if (changedRows === 0) {
        // Someone else moved the order first. No event, no stock.
        const fresh = await tx.orm.public.Order.first({ id: orderId });
        if (!fresh) throw new NotFoundException(`Order ${orderId} not found`);
        const now = fresh.status as OrderStatus;
        if (now === target) {
          return { order: await loadOrder(tx, fresh), changed: false };
        }
        throw orderStateChanged(now, target);
      }

      await args.apply?.(tx, order);

      await tx.orm.public.OrderStatusEvent.create({
        orderId,
        fromStatus: current,
        toStatus: target,
        actorType: actor.type,
        actorId: actor.userId,
        reason,
      });

      const updated = await tx.orm.public.Order.first({ id: orderId });
      return { order: await loadOrder(tx, updated!), changed: true };
    });
  }
}

// ── Authorization ─────────────────────────────────────────────────────────

/**
 * The order, if this actor may act on it: the customer who placed it, or the
 * owner of its store. Anyone else gets the same 404 as for a missing order.
 */
async function loadAuthorizedOrder(
  tx: Tx,
  orderId: number,
  actor: OrderActor,
): Promise<OrderRow> {
  const order = await tx.orm.public.Order.first({ id: orderId });
  const notFound = new NotFoundException(`Order ${orderId} not found`);
  if (!order) throw notFound;

  if (actor.type === OrderActorType.CLIENT) {
    if (order.customerId !== actor.userId) throw notFound;
  } else {
    const store = await tx.orm.public.Store.first({ id: order.storeId });
    if (!store || store.ownerId !== actor.userId) throw notFound;
  }
  return order;
}

function normalizeReason(
  reason: string | null | undefined,
  required: boolean,
): string | null {
  const text = reason?.trim() ?? '';
  if (text.length === 0) {
    if (required) throw new BadRequestException('A reason is required');
    return null;
  }
  if (text.length > MAX_REASON_LENGTH) {
    throw new BadRequestException(
      `The reason must be at most ${MAX_REASON_LENGTH} characters`,
    );
  }
  return text;
}

// ── Confirmation adjustment ───────────────────────────────────────────────

async function loadItems(tx: Tx, orderId: number): Promise<OrderItemRecord[]> {
  return (await tx.orm.public.OrderItem.where({
    orderId,
  }).all()) as OrderItemRecord[];
}

/**
 * Rejects a removal that cannot be applied, before anything changes: an item
 * that is not on this order or is already removed, or a removal that would
 * leave no active line (the owner must cancel the order instead) or a total of
 * zero.
 */
async function validateRemoval(
  tx: Tx,
  order: OrderRow,
  removeIds: number[],
): Promise<void> {
  if (removeIds.length === 0) return;
  const items = await loadItems(tx, order.id);
  const byId = new Map(items.map((item) => [item.id, item]));

  const foreign = removeIds.filter((id) => !byId.has(id));
  if (foreign.length > 0) {
    throw new BadRequestException({
      statusCode: 400,
      error: 'Bad Request',
      message: 'Some lines are not part of this order',
      itemIds: foreign,
    });
  }
  const alreadyRemoved = removeIds.filter(
    (id) => byId.get(id)!.removedAt !== null,
  );
  if (alreadyRemoved.length > 0) {
    throw new BadRequestException({
      statusCode: 400,
      error: 'Bad Request',
      message: 'Some lines were already removed',
      itemIds: alreadyRemoved,
    });
  }

  const remaining = items.filter(
    (item) => item.removedAt === null && !removeIds.includes(item.id),
  );
  if (remaining.length === 0) {
    throw new BadRequestException(
      'Removing these lines would leave the order empty; cancel the order instead',
    );
  }
  if (orderTotalMillimes(remaining) <= 0) {
    throw new BadRequestException(
      'The remaining lines must have a positive total; cancel the order instead',
    );
  }
}

/**
 * Removes lines during the winning confirmation: each is marked removed (only
 * if still active) and its historical stock quantity is given back, together.
 * A line that cannot be marked removed aborts the whole transaction.
 */
async function removeLines(
  tx: Tx,
  orderId: number,
  removeIds: number[],
): Promise<void> {
  if (removeIds.length === 0) return;
  const items = (await loadItems(tx, orderId))
    .filter((item) => removeIds.includes(item.id))
    .sort((a, b) => a.storeProductId - b.storeProductId);

  for (const item of items) {
    // `updateAndCount`, for the same reason as the status guard above.
    const removed = await tx.orm.public.OrderItem.where({
      id: item.id,
      orderId,
    })
      .where((row) => row.removedAt.isNull())
      .updateAndCount({ removedAt: new Date().toISOString() });
    if (removed === 0) {
      // Cannot happen while only the winner of the confirmation removes lines;
      // if it ever does, giving back the stock a second time would be wrong.
      throw new Error(`Order item ${item.id} was already removed`);
    }
    await giveBackStock(tx, item);
  }
}

// ── Stock ─────────────────────────────────────────────────────────────────

/** Gives back what a cancelled or no-show order still holds: every line not removed. */
async function restoreStockOfActiveLines(
  tx: Tx,
  orderId: number,
): Promise<void> {
  const active = (await loadItems(tx, orderId))
    .filter((item) => item.removedAt === null)
    // A stable product order, like order creation, so overlapping orders
    // cannot deadlock on the same StoreProduct rows.
    .sort((a, b) => a.storeProductId - b.storeProductId);
  for (const item of active) {
    await giveBackStock(tx, item);
  }
}

/**
 * Adds the line's historical `stockDecrementedQuantity` back to its
 * StoreProduct. Nothing else is consulted. A line that took no stock adds
 * nothing; a product that has no stock counter any more (tracking switched
 * off) has nothing to credit, so the update changes no row.
 */
async function giveBackStock(tx: Tx, item: OrderItemRecord): Promise<void> {
  const quantity = item.stockDecrementedQuantity;
  if (quantity <= 0) return;
  await tx.execute(
    db.raw
      .sql`UPDATE "StoreProduct" SET "stockQuantity" = "stockQuantity" + ${quantity}, "updatedAt" = now() WHERE "id" = ${item.storeProductId} AND "stockQuantity" IS NOT NULL`
      .affectedCount()
      .build(),
  );
}
