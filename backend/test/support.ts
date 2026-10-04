import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { setupApp } from '../src/app.setup.js';
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
let accountCounter = 0;
const createdUserIds: number[] = [];

export const http = () => app.getHttpServer();
export const auth = (account: Account) => ({
  Authorization: `Bearer ${account.token}`,
});

export async function startApp(): Promise<void> {
  // The e2e suites write real rows — never let them run against the dev database.
  expect(new URL(process.env['DATABASE_URL']!).pathname).toMatch(/_test$/);

  const moduleFixture = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();
  app = moduleFixture.createNestApplication();
  setupApp(app);
  await app.init();
}

/** Removes everything the suite created (children first), then stops the app. */
export async function stopApp(): Promise<void> {
  for (const id of createdUserIds) {
    const store = await db.orm.public.Store.first({ ownerId: id });
    if (store) {
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
    })
    .expect(201);
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
