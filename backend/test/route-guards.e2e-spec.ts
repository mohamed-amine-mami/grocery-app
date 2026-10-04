import type { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { setupApp } from '../src/app.setup.js';
import { register, auth, startApp, stopApp, http } from './support.js';

/**
 * A safety net over the *whole* route table, not individual routes: if a route
 * is added (or an old generic CRUD one comes back) without protection, this
 * fails. Routes come from the real Swagger document of the real app.
 */

const PUBLIC_ROUTES = [
  'GET /health',
  'POST /auth/register',
  'POST /auth/login',
];

/** Every route the API is expected to expose. Adding one must be a conscious edit here. */
const EXPECTED_ROUTES = [
  'DELETE /owner/store-products/{id}',
  'GET /auth/me',
  'GET /health',
  'GET /owner/catalog/categories',
  'GET /owner/catalog/products',
  'GET /owner/store',
  'GET /owner/store-products',
  'GET /owner/orders',
  'GET /owner/orders/{id}',
  'GET /owner/store-products/{id}',
  'GET /orders',
  'GET /orders/{id}',
  'GET /stores',
  'GET /stores/{id}/products',
  'PATCH /owner/store',
  'PATCH /owner/store-products/{id}',
  'PATCH /owner/store-products/{id}/availability',
  'POST /auth/login',
  'POST /auth/register',
  'POST /owner/store',
  'POST /orders',
  'POST /orders/{id}/cancel',
  'POST /owner/orders/{id}/cancel',
  'POST /owner/orders/{id}/complete',
  'POST /owner/orders/{id}/confirm',
  'POST /owner/orders/{id}/no-show',
  'POST /owner/orders/{id}/ready',
  'POST /owner/store-products',
  'POST /owner/store-products/{id}/restore',
];

let routes: { method: string; path: string; label: string }[] = [];

beforeAll(async () => {
  await startApp();
  // Build the document from a second app instance: `startApp` keeps its own private.
  const moduleFixture = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();
  const app: INestApplication = moduleFixture.createNestApplication();
  setupApp(app);
  await app.init();
  const document = SwaggerModule.createDocument(
    app,
    new DocumentBuilder().build(),
  );
  routes = Object.entries(document.paths).flatMap(([path, operations]) =>
    Object.keys(operations as object).map((method) => ({
      method,
      path,
      label: `${method.toUpperCase()} ${path}`,
    })),
  );
  await app.close();
});

afterAll(stopApp);

const concrete = (path: string) => path.replace('{id}', '1');
const call = (method: string, path: string) =>
  (request(http()) as unknown as Record<string, (p: string) => request.Test>)[
    method
  ](concrete(path));

describe('the route table', () => {
  it('is exactly the expected set (no accidental routes)', () => {
    expect(routes.map((route) => route.label).sort()).toEqual(
      [...EXPECTED_ROUTES].sort(),
    );
  });

  it('never exposes a route that takes an owner or store id from the client', () => {
    for (const { path } of routes) {
      expect(path).not.toMatch(/\{(ownerId|storeId)\}/);
    }
    expect(routes.some((route) => /^\/users\b/.test(route.path))).toBe(false);
    // Customers only browse stores: nothing under /stores writes.
    const storeRoutes = routes.filter((route) =>
      /^\/stores\b/.test(route.path),
    );
    expect(storeRoutes.length).toBeGreaterThan(0);
    expect(storeRoutes.map((route) => route.method)).toEqual(
      storeRoutes.map(() => 'get'),
    );
  });
});

describe('the global catalog has no write route', () => {
  it('exposes only GET under /owner/catalog', () => {
    const catalogRoutes = routes.filter((route) =>
      route.path.startsWith('/owner/catalog'),
    );
    expect(catalogRoutes.length).toBeGreaterThan(0);
    expect(catalogRoutes.map((route) => route.method)).toEqual(
      catalogRoutes.map(() => 'get'),
    );
  });

  it('has no route that reaches the catalog tables or the removed per-store catalog', () => {
    const labels = routes.map((route) => route.label);
    expect(
      labels.filter((label) => /\/owner\/(categories|products)/.test(label)),
    ).toEqual([]);
  });

  it('allows writes only on the store, the store products, orders and auth', () => {
    const writers = routes
      .filter((route) => route.method !== 'get')
      .map((route) => route.path.split('/').slice(0, 3).join('/'));
    expect([...new Set(writers)].sort()).toEqual([
      '/auth/login',
      '/auth/register',
      '/orders',
      '/orders/{id}',
      '/owner/orders',
      '/owner/store',
      '/owner/store-products',
    ]);
  });
});

describe('every customer route (/orders, /stores) is CLIENT-only', () => {
  it('returns 403 for an authenticated OWNER', async () => {
    const owner = await register('OWNER');
    const customerRoutes = routes.filter((route) =>
      /^\/(orders|stores)(\/|$)/.test(route.path),
    );
    expect(customerRoutes.length).toBeGreaterThan(0);
    for (const { method, path, label } of customerRoutes) {
      const response = await call(method, path).set(auth(owner)).send({});
      expect({ label, status: response.status }).toEqual({
        label,
        status: 403,
      });
    }
  });
});

describe('every non-public route requires a valid token', () => {
  it('returns 401 with no token', async () => {
    for (const { method, path, label } of routes) {
      if (PUBLIC_ROUTES.includes(label)) continue;
      const response = await call(method, path).send({});
      expect({ label, status: response.status }).toEqual({
        label,
        status: 401,
      });
    }
  });

  it('returns 401 with a forged or malformed token', async () => {
    for (const { method, path, label } of routes) {
      if (PUBLIC_ROUTES.includes(label)) continue;
      for (const header of ['Bearer not-a-token', 'Basic abc', 'Bearer']) {
        const response = await call(method, path)
          .set('Authorization', header)
          .send({});
        expect({ label, header, status: response.status }).toEqual({
          label,
          header,
          status: 401,
        });
      }
    }
  });
});

describe('every /owner route is OWNER-only', () => {
  it('returns 403 for an authenticated CLIENT', async () => {
    const client = await register('CLIENT');
    const ownerRoutes = routes.filter((route) =>
      route.path.startsWith('/owner'),
    );
    expect(ownerRoutes.length).toBeGreaterThan(0);
    for (const { method, path, label } of ownerRoutes) {
      const response = await call(method, path).set(auth(client)).send({});
      expect({ label, status: response.status }).toEqual({
        label,
        status: 403,
      });
    }
  });

  it('lets a CLIENT use /auth/me (it is not an owner route)', async () => {
    const client = await register('CLIENT');
    await request(http()).get('/auth/me').set(auth(client)).expect(200);
  });
});
