/**
 * Where an order is in its life. Mirrors the `OrderStatus` enum in
 * `contract.prisma` (a test keeps the two in step). The allowed transitions
 * are in `order-rules.ts`.
 */
export enum OrderStatus {
  PENDING = 'PENDING',
  CONFIRMED = 'CONFIRMED',
  READY_FOR_PICKUP = 'READY_FOR_PICKUP',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
  NO_SHOW = 'NO_SHOW',
}
