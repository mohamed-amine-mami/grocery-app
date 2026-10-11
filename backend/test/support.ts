import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { setupApp } from '../src/app.setup.js';
import { ImageStorageService } from '../src/images/image-storage.service.js';
import { InMemoryImageStorage } from '../src/images/in-memory-image-storage.js';
import { db } from '../src/prisma/db.js';

/** Shared helpers for the e2e suites. They go through the real HTTP endpoints. */

export type Role = 'OWNER' | 'CLIENT';
export interface Account {
  id: number;
  token: string;
  phoneNumber: string;
}

export const validStore = {
  name: 'Menzah Market',
  address: '12 Rue de la Liberté, Menzah 5, Tunis',
};

let app: INestApplication;

/** The storage the running app uses; reset by `startApp`. */
export let imageStorage: InMemoryImageStorage;
let accountCounter = 0;
const createdUserIds: number[] = [];

export const http = () => app.getHttpServer();
export const auth = (account: Account) => ({
  Authorization: `Bearer ${account.token}`,
});

export async function startApp(): Promise<void> {
  // The e2e suites write real rows — never let them run against the dev database.
  expect(new URL(process.env['DATABASE_URL']!).pathname).toMatch(/_test$/);

  // Image storage is always the in-memory fake: no suite may reach Cloudinary.
  imageStorage = new InMemoryImageStorage();
  const moduleFixture = await Test.createTestingModule({
    imports: [AppModule],
  })
    .overrideProvider(ImageStorageService)
    .useValue(imageStorage)
    .compile();
  app = moduleFixture.createNestApplication();
  setupApp(app);
  // Listen once, on one port, for the whole suite. Left unbound, supertest
  // opens and closes a fresh ephemeral port for every request; with hundreds
  // of setup requests some of those connections were answered by an unrelated
  // local listener (404/401/403 on public routes), which made suites flaky.
  await app.listen(0, '127.0.0.1');
}

/** Deletes orders with their events and items (one row per `delete()` call). */
async function deleteOrders(orders: { id: number }[]): Promise<void> {
  for (const order of orders) {
    for (const event of await db.orm.public.OrderStatusEvent.where({
      orderId: order.id,
    }).all()) {
      await db.orm.public.OrderStatusEvent.select('id')
        .where({ id: event.id })
        .delete();
    }
    for (const item of await db.orm.public.OrderItem.where({
      orderId: order.id,
    }).all()) {
      await db.orm.public.OrderItem.select('id')
        .where({ id: item.id })
        .delete();
    }
    await db.orm.public.Order.select('id').where({ id: order.id }).delete();
  }
}

/** Removes everything the suite created (children first), then stops the app. */
export async function stopApp(): Promise<void> {
  for (const id of createdUserIds) {
    const store = await db.orm.public.Store.first({ ownerId: id });
    // Orders reference the customer, the store and its offerings (all Restrict),
    // so they go first — together with their items and status events.
    await deleteOrders(
      await db.orm.public.Order.where({ customerId: id }).all(),
    );
    if (store) {
      await deleteOrders(
        await db.orm.public.Order.where({ storeId: store.id }).all(),
      );
      // `delete()` removes one row per call, so walk the store's offerings first
      // (they reference the store). Global catalog rows are shared and never
      // removed here — a suite that creates any removes them itself.
      const offerings = await db.orm.public.StoreProduct.where({
        storeId: store.id,
      }).all();
      for (const offering of offerings) {
        await db.orm.public.StoreProduct.select('id')
          .where({ id: offering.id })
          .delete();
      }
    }
    await db.orm.public.Store.select('id').where({ ownerId: id }).delete();
    await db.orm.public.User.select('id').where({ id }).delete();
  }
  createdUserIds.length = 0;
  await app.close();
}

/** Registers through the real `/auth/register` endpoint. */
export async function register(role: Role): Promise<Account> {
  accountCounter += 1;
  const unique = `${Date.now()}${accountCounter}`;
  const phoneNumber = `+216${unique.slice(-8)}`;
  const response = await request(http())
    .post('/auth/register')
    .send({
      name: `Test ${role} ${accountCounter}`,
      email: `e2e-${unique}@example.com`,
      password: 'changeme123',
      phoneNumber,
      role,
    });
  if (response.status !== 201) {
    throw new Error(
      `register failed: ${response.status} ${JSON.stringify(response.body)}`,
    );
  }
  createdUserIds.push(response.body.user.id);
  return {
    id: response.body.user.id,
    token: response.body.accessToken,
    phoneNumber,
  };
}

export function trackUser(id: number): void {
  createdUserIds.push(id);
}

export async function registerOwnerWithStore(overrides: object = {}) {
  const owner = await register('OWNER');
  const response = await request(http())
    .post('/owner/store')
    .set(auth(owner))
    .send({ ...validStore, ...overrides })
    .expect(201);
  return { owner, store: response.body };
}
