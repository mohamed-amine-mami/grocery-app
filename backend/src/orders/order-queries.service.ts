import { Injectable, NotFoundException } from '@nestjs/common';
import { db } from '../prisma/db.js';
import type { OrderActorType } from './order-actor-type.enum.js';
import type { OrderRow } from './order-records.js';
import type { OrderStatus } from './order-status.enum.js';
import type { OrderItemRecord, OrderRecord } from './order.types.js';

export const DEFAULT_ORDERS_PAGE_LIMIT = 20;
export const MAX_ORDERS_PAGE_LIMIT = 50;

export interface OrderEventRecord {
  fromStatus: OrderStatus | null;
  toStatus: OrderStatus;
  actorType: OrderActorType;
  reason: string | null;
  createdAt: string;
}

/** An order with its history and the two parties it connects. */
export interface OrderView {
  order: OrderRecord;
  events: OrderEventRecord[];
  store: { id: number; name: string; address: string };
  customer: { id: number; name: string; phoneNumber: string };
}

export interface OrderPage {
  items: OrderView[];
  page: number;
  limit: number;
  total: number;
}

export interface PageRequest {
  page?: number;
  limit?: number;
}

/**
 * Reads orders. Like the other order services it takes plain values. Access is
 * decided by the query itself — `WHERE id = ? AND customerId = ?` for a
 * customer, `WHERE id = ? AND storeId = <the owner's store>` for an owner — so
 * an order that belongs to someone else is indistinguishable from one that does
 * not exist (404), and is never loaded.
 */
@Injectable()
export class OrderQueriesService {
  async listForCustomer(
    customerId: number,
    request: PageRequest = {},
  ): Promise<OrderPage> {
    return this.list({ customerId }, request);
  }

  async getForCustomer(
    customerId: number,
    orderId: number,
  ): Promise<OrderView> {
    return this.one({ id: orderId, customerId }, orderId);
  }

  /** `status` narrows the list; no other filter exists in V1. */
  async listForOwner(
    ownerId: number,
    request: PageRequest & { status?: OrderStatus } = {},
  ): Promise<OrderPage> {
    const storeId = await ownerStoreId(ownerId);
    return this.list(
      request.status ? { storeId, status: request.status } : { storeId },
      request,
    );
  }

  async getForOwner(ownerId: number, orderId: number): Promise<OrderView> {
    const storeId = await ownerStoreId(ownerId);
    return this.one({ id: orderId, storeId }, orderId);
  }

  private async one(
    scope: Record<string, number>,
    orderId: number,
  ): Promise<OrderView> {
    const row = await db.orm.public.Order.where(scope).first();
    if (!row) throw new NotFoundException(`Order ${orderId} not found`);
    return (await toViews([row]))[0]!;
  }

  private async list(
    scope: Record<string, number | string>,
    request: PageRequest,
  ): Promise<OrderPage> {
    const limit = Math.min(
      request.limit ?? DEFAULT_ORDERS_PAGE_LIMIT,
      MAX_ORDERS_PAGE_LIMIT,
    );
    const page = request.page ?? 1;

    const counted = await db.orm.public.Order.where(scope).aggregate((agg) => ({
      total: agg.count(),
    }));
    const rows = await db.orm.public.Order.where(scope)
      // Newest first; the id breaks ties so pages never overlap or skip.
      .orderBy([(o) => o.createdAt.desc(), (o) => o.id.desc()])
      .limit(limit)
      .offset((page - 1) * limit)
      .all();

    return {
      items: await toViews(rows),
      page,
      limit,
      total: Number(counted.total ?? 0),
    };
  }
}

async function ownerStoreId(ownerId: number): Promise<number> {
  const store = await db.orm.public.Store.first({ ownerId });
  if (!store) throw new NotFoundException('This owner has no store yet');
  return store.id;
}

/** Loads items, events, stores and customers for a batch of orders (a fixed number of queries). */
async function toViews(rows: OrderRow[]): Promise<OrderView[]> {
  if (rows.length === 0) return [];
  const orderIds = rows.map((row) => row.id);
  const storeIds = [...new Set(rows.map((row) => row.storeId))];
  const customerIds = [...new Set(rows.map((row) => row.customerId))];

  const [items, events, stores, customers] = await Promise.all([
    db.orm.public.OrderItem.where((i) => i.orderId.in(orderIds)).all(),
    db.orm.public.OrderStatusEvent.where((e) => e.orderId.in(orderIds)).all(),
    db.orm.public.Store.where((s) => s.id.in(storeIds)).all(),
    db.orm.public.User.where((u) => u.id.in(customerIds)).all(),
  ]);

  return rows.map((row) => {
    const store = stores.find((candidate) => candidate.id === row.storeId)!;
    const customer = customers.find(
      (candidate) => candidate.id === row.customerId,
    )!;
    return {
      order: {
        ...row,
        status: row.status as OrderStatus,
        items: (items as OrderItemRecord[])
          .filter((item) => item.orderId === row.id)
          .sort((a, b) => a.id - b.id),
      },
      events: events
        .filter((event) => event.orderId === row.id)
        .sort((a, b) => a.id - b.id)
        .map((event) => ({
          fromStatus: event.fromStatus as OrderStatus | null,
          toStatus: event.toStatus as OrderStatus,
          actorType: event.actorType as OrderActorType,
          reason: event.reason,
          createdAt: event.createdAt,
        })),
      store: { id: store.id, name: store.name, address: store.address },
      customer: {
        id: customer.id,
        name: customer.name,
        phoneNumber: customer.phoneNumber,
      },
    };
  });
}
