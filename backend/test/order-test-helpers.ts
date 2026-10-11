import type { HttpException } from '@nestjs/common';
import request from 'supertest';
import { db } from '../src/prisma/db.js';
import { auth, http, registerOwnerWithStore, type Account } from './support.js';

/** Shared by the order suites: a store with offerings, and ways to read the database back. */

export const hoursFromNow = (hours: number) =>
  new Date(Date.now() + hours * 3_600_000);

export interface TestStore {
  owner: Account;
  storeId: number;
  /** Adds a catalog product to this store; returns the store product id. */
  offer: (slug: string, body?: object) => Promise<number>;
}

/** A fresh open store with its own owner, so tests never share stock. */
export async function openStore(
  productId: (slug: string) => number,
): Promise<TestStore> {
  const { owner, store } = await registerOwnerWithStore();
  await db.orm.public.Store.where({ id: store.id }).update({ isOpen: true });
  const offer = async (slug: string, body: object = {}) => {
    const response = await request(http())
      .post('/owner/store-products')
      .set(auth(owner))
      .send({ productId: productId(slug), priceMillimes: 4500, ...body });
    if (response.status !== 201) {
      // Say what the API answered: a bare status makes setup failures opaque.
      throw new Error(
        `offering ${slug} failed: ${response.status} ${JSON.stringify(response.body)}`,
      );
    }
    return response.body.id as number;
  };
  return { owner, storeId: store.id, offer };
}

/** Changes a store product through the owner API (price, rules, tracking…). */
export const patchStoreProduct = (store: TestStore, id: number, body: object) =>
  request(http())
    .patch(`/owner/store-products/${id}`)
    .set(auth(store.owner))
    .send(body)
    .expect(200);

export const setAvailability = (
  store: TestStore,
  id: number,
  isAvailable: boolean,
) =>
  request(http())
    .patch(`/owner/store-products/${id}/availability`)
    .set(auth(store.owner))
    .send({ isAvailable })
    .expect(200);

export const archiveStoreProduct = (store: TestStore, id: number) =>
  request(http())
    .delete(`/owner/store-products/${id}`)
    .set(auth(store.owner))
    .expect(204);

/**
 * Opens `connections` database connections up front. Without this the first
 * concurrent requests of a test wait for fresh connections while one of them
 * runs alone, so they never actually race.
 */
export async function warmPool(connections = 10) {
  await Promise.all(
    Array.from({ length: connections }, () =>
      db.transaction(async (tx) => {
        await tx.execute(
          db.raw.sql`SELECT pg_sleep(0.3)`.affectedCount().build(),
        );
      }),
    ),
  );
}

/** The status and JSON body of the exception a promise rejects with. */
export async function failure(promise: Promise<unknown>) {
  try {
    await promise;
  } catch (error) {
    const exception = error as HttpException;
    return {
      status: exception.getStatus(),
      body: exception.getResponse() as Record<string, unknown>,
    };
  }
  throw new Error('expected the promise to reject');
}

export const stockOf = async (storeProductId: number) =>
  (await db.orm.public.StoreProduct.first({ id: storeProductId }))!
    .stockQuantity;
export const ordersOf = (customerId: number) =>
  db.orm.public.Order.where({ customerId }).all();
export const ordersAt = (storeId: number) =>
  db.orm.public.Order.where({ storeId }).all();
/** An order's events in the order they happened (ids are assigned as they are written; a bare SELECT has no guaranteed order). */
export const eventsOf = async (orderId: number) =>
  (await db.orm.public.OrderStatusEvent.where({ orderId }).all()).sort(
    (a, b) => a.id - b.id,
  );
export const itemsOf = (orderId: number) =>
  db.orm.public.OrderItem.where({ orderId }).all();
export const orderRow = (orderId: number) =>
  db.orm.public.Order.first({ id: orderId });
