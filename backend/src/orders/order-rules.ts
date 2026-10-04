import { ConflictException } from '@nestjs/common';
import { randomInt } from 'node:crypto';
import { OrderStatus } from './order-status.enum.js';

/**
 * Pure domain rules for orders — no database, no HTTP — so the same logic backs
 * every channel (the app today, WhatsApp later). The contract is `docs/orders.md`.
 * Quantity and price rules are not restated here: a requested quantity is
 * checked with `requestedQuantityErrors` and a line is priced with
 * `lineTotalMillimes`, both in `products/product-rules.ts`.
 */

// ── Lifecycle ───────────────────────────────────────────────────────────

/** Stable error `code` for a transition the order's current status does not allow (HTTP 409). */
export const ORDER_STATE_CHANGED = 'ORDER_STATE_CHANGED';

/**
 * The only moves between statuses. Who may make each one (customer or owner)
 * is not a lifecycle matter and is decided by the service.
 */
export const ORDER_TRANSITIONS: Readonly<
  Record<OrderStatus, readonly OrderStatus[]>
> = {
  [OrderStatus.PENDING]: [OrderStatus.CONFIRMED, OrderStatus.CANCELLED],
  [OrderStatus.CONFIRMED]: [
    OrderStatus.READY_FOR_PICKUP,
    OrderStatus.CANCELLED,
  ],
  [OrderStatus.READY_FOR_PICKUP]: [OrderStatus.COMPLETED, OrderStatus.NO_SHOW],
  [OrderStatus.COMPLETED]: [],
  [OrderStatus.CANCELLED]: [],
  [OrderStatus.NO_SHOW]: [],
};

/** A terminal order never changes status again. */
export function isTerminalStatus(status: OrderStatus): boolean {
  return ORDER_TRANSITIONS[status].length === 0;
}

/** Whether `from → to` is an allowed *change* of status (staying put is not). */
export function canTransition(from: OrderStatus, to: OrderStatus): boolean {
  return ORDER_TRANSITIONS[from].includes(to);
}

/**
 * What a request to move an order to `requested` means:
 * - `unchanged`: the order is already there. Nothing changes and no event is
 *   written; the caller returns the current order (HTTP 200).
 * - `apply`: an allowed transition.
 * - `invalid`: not allowed from the current status (see `orderStateChanged`).
 */
export type TransitionDecision = 'unchanged' | 'apply' | 'invalid';

export function decideTransition(
  current: OrderStatus,
  requested: OrderStatus,
): TransitionDecision {
  if (current === requested) return 'unchanged';
  return canTransition(current, requested) ? 'apply' : 'invalid';
}

/** The stable 409 for an invalid transition; `currentStatus` lets the client refresh. */
export function orderStateChanged(
  current: OrderStatus,
  requested: OrderStatus,
): ConflictException {
  return new ConflictException({
    statusCode: 409,
    error: 'Conflict',
    code: ORDER_STATE_CHANGED,
    message: `Order is ${current}; it cannot move to ${requested}`,
    currentStatus: current,
    requestedStatus: requested,
  });
}

/** `decideTransition`, throwing `orderStateChanged` for an invalid move. */
export function resolveTransition(
  current: OrderStatus,
  requested: OrderStatus,
): 'unchanged' | 'apply' {
  const decision = decideTransition(current, requested);
  if (decision === 'invalid') throw orderStateChanged(current, requested);
  return decision;
}

// ── Pickup time ─────────────────────────────────────────────────────────

/** `requestedPickupAt` is advisory (no slots, no capacity); these are the only bounds. Both are inclusive. */
export const MIN_PICKUP_LEAD_MINUTES = 30;
export const MAX_PICKUP_LEAD_HOURS = 48;

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;

/** Why `requestedPickupAt` is not acceptable at `now`, or `null` when it is. */
export function pickupTimeError(
  requestedPickupAt: Date,
  now: Date,
): string | null {
  const requested = requestedPickupAt.getTime();
  if (Number.isNaN(requested) || Number.isNaN(now.getTime())) {
    return 'requestedPickupAt must be a valid date';
  }
  const lead = requested - now.getTime();
  if (lead < MIN_PICKUP_LEAD_MINUTES * MINUTE_MS) {
    return `requestedPickupAt must be at least ${MIN_PICKUP_LEAD_MINUTES} minutes from now`;
  }
  if (lead > MAX_PICKUP_LEAD_HOURS * HOUR_MS) {
    return `requestedPickupAt must be at most ${MAX_PICKUP_LEAD_HOURS} hours from now`;
  }
  return null;
}

// ── Totals ──────────────────────────────────────────────────────────────

/** The `Order.totalMillimes` column is a 32-bit integer. */
export const MAX_ORDER_TOTAL_MILLIMES = 2_147_483_647;

export interface OrderLineForTotal {
  lineTotalMillimes: number;
  /** Set when the owner removed the line at confirmation. */
  removedAt: Date | string | null;
}

/**
 * The order total: the sum of the lines that were not removed, in whole
 * millimes (exact integer arithmetic, no floats). Removed lines count for zero.
 * Throws `RangeError` for a line total that is not a non-negative integer, or a
 * total beyond what the column can hold.
 */
export function orderTotalMillimes(
  items: readonly OrderLineForTotal[],
): number {
  let total = 0n;
  for (const item of items) {
    if (
      !Number.isInteger(item.lineTotalMillimes) ||
      item.lineTotalMillimes < 0
    ) {
      throw new RangeError('lineTotalMillimes must be a non-negative integer');
    }
    if (item.removedAt === null) total += BigInt(item.lineTotalMillimes);
  }
  if (total > BigInt(MAX_ORDER_TOTAL_MILLIMES)) {
    throw new RangeError(
      `order total must be at most ${MAX_ORDER_TOTAL_MILLIMES} millimes`,
    );
  }
  return Number(total);
}

// ── Order code ──────────────────────────────────────────────────────────

/**
 * Uppercase letters and digits without the look-alikes 0/O, 1/I and L, so a
 * code can be read out loud or over the counter. 31 symbols; with 6 of them
 * there are about 887 million codes.
 */
export const ORDER_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const ORDER_CODE_LENGTH = 6;

/**
 * A short random reference, also used as the pickup code. It identifies an
 * order for people; it is NOT a secret and never authenticates anything.
 * Uniqueness is enforced by the database (`Order.code`); on a collision the
 * caller generates another. `random(max)` returns an integer in `[0, max)`
 * (injectable for tests; the default is cryptographic and unbiased).
 */
export function generateOrderCode(
  random: (maxExclusive: number) => number = randomInt,
): string {
  let code = '';
  for (let i = 0; i < ORDER_CODE_LENGTH; i += 1) {
    code += ORDER_CODE_ALPHABET[random(ORDER_CODE_ALPHABET.length)];
  }
  return code;
}

const ORDER_CODE_PATTERN = new RegExp(
  `^[${ORDER_CODE_ALPHABET}]{${ORDER_CODE_LENGTH}}$`,
);

/** Whether `value` has the shape of a generated code. */
export function isOrderCode(value: string): boolean {
  return ORDER_CODE_PATTERN.test(value);
}
