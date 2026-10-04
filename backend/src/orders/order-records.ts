import { db } from '../prisma/db.js';
import type { OrderStatus } from './order-status.enum.js';
import type { OrderItemRecord, OrderRecord } from './order.types.js';

/** The transaction context `db.transaction` hands to its callback. */
export type Tx = Parameters<Parameters<typeof db.transaction>[0]>[0];

/** An order row as the ORM returns it. */
export interface OrderRow {
  id: number;
  code: string;
  customerId: number;
  storeId: number;
  status: string;
  requestedPickupAt: string;
  totalMillimes: number;
  idempotencyKey: string;
  createdAt: string;
  updatedAt: string;
}

/** The order with all its items (removed ones included), items by id. */
export async function loadOrder(tx: Tx, row: OrderRow): Promise<OrderRecord> {
  const items = await tx.orm.public.OrderItem.where({ orderId: row.id }).all();
  return {
    id: row.id,
    code: row.code,
    customerId: row.customerId,
    storeId: row.storeId,
    status: row.status as OrderStatus,
    requestedPickupAt: row.requestedPickupAt,
    totalMillimes: row.totalMillimes,
    idempotencyKey: row.idempotencyKey,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    items: (items as OrderItemRecord[]).sort((a, b) => a.id - b.id),
  };
}
