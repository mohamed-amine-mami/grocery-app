import request from 'supertest';
import { db } from '../src/prisma/db.js';
import { removeCatalog, seedCatalog } from './catalog-helpers.js';
import {
  eventsOf,
  hoursFromNow,
  itemsOf,
  openStore as openStoreFor,
  stockOf,
  warmPool,
  type TestStore,
} from './order-test-helpers.js';
import {
  auth,
  http,
  register,
  startApp,
  stopApp,
  type Account,
} from './support.js';

/**
 * The Orders HTTP API against the real database. Business rules and races are
 * covered by the service suites; this one checks what the controllers add:
 * authentication, roles, DTO validation, ownership as 404, status codes, error
 * bodies, response shapes and pagination.
 * Fixture catalog (tagged): banane KG min 100 step 100 max 10000;
 * lait-delice-1l PIECE; yaourt PIECE max 24.
 */

const tag = `e2ehttp${Date.now()}`;
let catalog: Awaited<ReturnType<typeof seedCatalog>>;
let keyCounter = 0;

beforeAll(async () => {
  await startApp();
  catalog = await seedCatalog(tag);
});
afterAll(async () => {
  await stopApp();
  await removeCatalog(tag);
});

const nextKey = () => `key-${tag}-${(keyCounter += 1)}`;
const openStore = () => openStoreFor((slug) => catalog.productId(slug));

interface Line {
  storeProductId: number;
  quantity: number;
}

const body = (storeId: number, lines: Line[], extra: object = {}) => ({
  storeId,
  lines,
  requestedPickupAt: hoursFromNow(4).toISOString(),
  idempotencyKey: nextKey(),
  ...extra,
});

const placeOrder = (customer: Account, payload: object) =>
  request(http()).post('/orders').set(auth(customer)).send(payload);

/** A store with milk (10 in stock) and yogurt, and a customer who ordered 2 of each. */
async function scenario() {
  const store = await openStore();
  const lait = await store.offer('lait-delice-1l', {
    trackStock: true,
    stockQuantity: 10,
    priceMillimes: 1800,
  });
  const yaourt = await store.offer('yaourt', {
    trackStock: true,
    stockQuantity: 10,
    priceMillimes: 700,
  });
  const customer = await register('CLIENT');
  const created = await placeOrder(
    customer,
    body(store.storeId, [
      { storeProductId: lait, quantity: 2 },
      { storeProductId: yaourt, quantity: 2 },
    ]),
  ).expect(201);
  return { store, lait, yaourt, customer, order: created.body };
}

const owner = (s: TestStore, method: 'get' | 'post', path: string) =>
  request(http())[method](path).set(auth(s.owner));
const act = (s: TestStore, orderId: number, action: string, payload = {}) =>
  owner(s, 'post', `/owner/orders/${orderId}/${action}`).send(payload);
const cancelAsCustomer = (customer: Account, id: number, payload = {}) =>
  request(http())
    .post(`/orders/${id}/cancel`)
    .set(auth(customer))
    .send(payload);

// ── Customer ──────────────────────────────────────────────────────────────

describe('customer: POST /orders', () => {
  it('creates an order with server-computed values and a customer-safe shape', async () => {
    const { order, store, customer } = await scenario();
    expect(order).toMatchObject({
      status: 'PENDING',
      totalMillimes: 2 * 1800 + 2 * 700,
      storeAdjusted: false,
      store: { id: store.storeId },
    });
    expect(order.code).toMatch(/^[A-Z0-9]{6}$/);
    expect(order.items).toHaveLength(2);
    expect(order.items[0]).toMatchObject({
      productName: expect.any(String),
      saleUnit: 'PIECE',
      quantity: 2,
      unitPriceMillimes: 1800,
      lineTotalMillimes: 3600,
      removedAt: null,
    });
    expect(order.events).toEqual([
      expect.objectContaining({
        fromStatus: null,
        toStatus: 'PENDING',
        actorType: 'CLIENT',
      }),
    ]);
    // Not the owner's view: no customer block.
    expect(order.customer).toBeUndefined();
    void customer;
  });

  it('never exposes stock or internal fields to the customer, anywhere', async () => {
    const { order, customer } = await scenario();
    const list = await request(http()).get('/orders').set(auth(customer));
    const one = await request(http())
      .get(`/orders/${order.id}`)
      .set(auth(customer));
    const cancelled = await cancelAsCustomer(customer, order.id);
    for (const payload of [order, list.body, one.body, cancelled.body]) {
      const text = JSON.stringify(payload);
      expect(text).not.toMatch(
        /stockQuantity|stockDecrementedQuantity|idempotencyKey|customerId/,
      );
    }
  });

  it('rejects client-supplied prices, totals, status and unknown fields', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const customer = await register('CLIENT');
    for (const extra of [
      { totalMillimes: 1 },
      { status: 'CONFIRMED' },
      { customerId: 1 },
    ]) {
      await placeOrder(
        customer,
        body(store.storeId, [{ storeProductId: lait, quantity: 1 }], extra),
      ).expect(400);
    }
    await placeOrder(
      customer,
      body(store.storeId, [
        { storeProductId: lait, quantity: 1, unitPriceMillimes: 1 } as Line,
      ]),
    ).expect(400);
  });

  it('validates the body (plain 400s)', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const customer = await register('CLIENT');
    const good = body(store.storeId, [{ storeProductId: lait, quantity: 1 }]);
    for (const bad of [
      { ...good, lines: [] },
      { ...good, lines: 'x' },
      { ...good, storeId: 'abc' },
      { ...good, requestedPickupAt: 'tomorrow' },
      { ...good, idempotencyKey: '' },
      { ...good, idempotencyKey: 'k'.repeat(101) },
      { ...good, lines: [{ storeProductId: lait }] },
    ]) {
      const response = await placeOrder(customer, bad);
      expect(response.status).toBe(400);
      expect(response.body.code).toBeUndefined();
    }
  });
});

describe('customer: reading orders', () => {
  it('lists only my orders, newest first, with bounded pagination', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 50,
    });
    const customer = await register('CLIENT');
    const other = await register('CLIENT');
    const ids: number[] = [];
    for (let i = 0; i < 3; i += 1) {
      const created = await placeOrder(
        customer,
        body(store.storeId, [{ storeProductId: lait, quantity: 1 }]),
      ).expect(201);
      ids.push(created.body.id);
    }
    await placeOrder(
      other,
      body(store.storeId, [{ storeProductId: lait, quantity: 1 }]),
    ).expect(201);

    const all = await request(http()).get('/orders').set(auth(customer));
    expect(all.status).toBe(200);
    expect(all.body.total).toBe(3);
    expect(all.body.items.map((o: { id: number }) => o.id)).toEqual(
      [...ids].reverse(),
    );

    const second = await request(http())
      .get('/orders?page=2&limit=2')
      .set(auth(customer));
    expect(second.body).toMatchObject({ page: 2, limit: 2, total: 3 });
    expect(second.body.items.map((o: { id: number }) => o.id)).toEqual([
      ids[0],
    ]);

    for (const query of [
      'limit=0',
      'limit=51',
      'page=0',
      'page=x',
      'limit=1.5',
    ]) {
      await request(http())
        .get(`/orders?${query}`)
        .set(auth(customer))
        .expect(400);
    }
  });

  it('gets one of my orders, with its history', async () => {
    const { order, customer } = await scenario();
    const response = await request(http())
      .get(`/orders/${order.id}`)
      .set(auth(customer))
      .expect(200);
    expect(response.body.id).toBe(order.id);
    expect(response.body.events).toHaveLength(1);
  });

  it('answers 404, identically, for another customer’s order and a missing one', async () => {
    const { order } = await scenario();
    const stranger = await register('CLIENT');
    const foreign = await request(http())
      .get(`/orders/${order.id}`)
      .set(auth(stranger));
    const missing = await request(http())
      .get('/orders/2147483000')
      .set(auth(stranger));
    expect(foreign.status).toBe(404);
    expect(missing.status).toBe(404);
    expect({ ...foreign.body, message: '' }).toEqual({
      ...missing.body,
      message: '',
    });
    await request(http()).get('/orders/abc').set(auth(stranger)).expect(400);
  });
});

describe('customer: POST /orders/:id/cancel', () => {
  it('cancels my PENDING order and gives the stock back', async () => {
    const { order, customer, lait, yaourt } = await scenario();
    expect(await stockOf(lait)).toBe(8);
    const response = await cancelAsCustomer(customer, order.id, {
      reason: 'Changed my mind',
    }).expect(200);
    expect(response.body.changed).toBe(true);
    expect(response.body.order.status).toBe('CANCELLED');
    expect(response.body.order.events.at(-1)).toMatchObject({
      toStatus: 'CANCELLED',
      actorType: 'CLIENT',
      reason: 'Changed my mind',
    });
    expect(await stockOf(lait)).toBe(10);
    expect(await stockOf(yaourt)).toBe(10);
  });

  it('cancels my CONFIRMED order (no body at all is fine)', async () => {
    const { order, customer, store, lait } = await scenario();
    await act(store, order.id, 'confirm').expect(200);
    const response = await request(http())
      .post(`/orders/${order.id}/cancel`)
      .set(auth(customer))
      .expect(200);
    expect(response.body.order.status).toBe('CANCELLED');
    expect(await stockOf(lait)).toBe(10);
  });

  it('repeating a cancel is idempotent (200, changed false)', async () => {
    const { order, customer } = await scenario();
    await cancelAsCustomer(customer, order.id).expect(200);
    const again = await cancelAsCustomer(customer, order.id).expect(200);
    expect(again.body.changed).toBe(false);
  });

  it.each([
    ['READY_FOR_PICKUP', ['confirm', 'ready']],
    ['COMPLETED', ['confirm', 'ready', 'complete']],
    ['NO_SHOW', ['confirm', 'ready', 'no-show']],
  ])(
    'cannot cancel a %s order: 409 ORDER_STATE_CHANGED',
    async (status, steps) => {
      const { order, customer, store } = await scenario();
      for (const step of steps) await act(store, order.id, step).expect(200);
      const response = await cancelAsCustomer(customer, order.id);
      expect(response.status).toBe(409);
      expect(response.body).toMatchObject({
        code: 'ORDER_STATE_CHANGED',
        currentStatus: status,
        requestedStatus: 'CANCELLED',
      });
      expect((await db.orm.public.Order.first({ id: order.id }))!.status).toBe(
        status,
      );
    },
  );

  it('cannot cancel another customer’s order (404) and changes nothing', async () => {
    const { order, lait } = await scenario();
    const stranger = await register('CLIENT');
    await cancelAsCustomer(stranger, order.id).expect(404);
    expect(await stockOf(lait)).toBe(8);
    expect(await eventsOf(order.id)).toHaveLength(1);
  });

  it('rejects an over-long reason', async () => {
    const { order, customer } = await scenario();
    await cancelAsCustomer(customer, order.id, {
      reason: 'x'.repeat(501),
    }).expect(400);
  });
});

// ── Owner ─────────────────────────────────────────────────────────────────

describe('owner: reading orders', () => {
  it('lists only the store’s orders, filters by status and shows the customer', async () => {
    const { store, order, customer } = await scenario();
    const second = await register('CLIENT');
    const lait = (
      await db.orm.public.StoreProduct.where({
        storeId: store.storeId,
      }).all()
    )[0]!.id;
    const other = await placeOrder(
      second,
      body(store.storeId, [{ storeProductId: lait, quantity: 1 }]),
    ).expect(201);
    await act(store, order.id, 'confirm').expect(200);

    const all = await owner(store, 'get', '/owner/orders').expect(200);
    expect(all.body.total).toBe(2);
    expect(all.body.items.map((o: { id: number }) => o.id)).toEqual([
      other.body.id,
      order.id,
    ]);
    expect(all.body.items[1].customer).toEqual({
      name: expect.any(String),
      phoneNumber: customer.phoneNumber,
    });

    const pending = await owner(
      store,
      'get',
      '/owner/orders?status=PENDING',
    ).expect(200);
    expect(pending.body.items.map((o: { id: number }) => o.id)).toEqual([
      other.body.id,
    ]);
    await owner(store, 'get', '/owner/orders?status=PREPARING').expect(400);
    await owner(store, 'get', '/owner/orders?limit=500').expect(400);
  });

  it('never exposes stock accounting to the owner either', async () => {
    const { store, order } = await scenario();
    const one = await owner(store, 'get', `/owner/orders/${order.id}`).expect(
      200,
    );
    expect(JSON.stringify(one.body)).not.toMatch(
      /stockDecrementedQuantity|idempotencyKey/,
    );
  });

  it('gets one order of the store', async () => {
    const { store, order } = await scenario();
    const response = await owner(
      store,
      'get',
      `/owner/orders/${order.id}`,
    ).expect(200);
    expect(response.body).toMatchObject({ id: order.id, status: 'PENDING' });
    expect(response.body.customer.name).toEqual(expect.any(String));
  });

  it('answers 404 for another store’s order, like a missing one', async () => {
    const { order } = await scenario();
    const rival = await openStore();
    const foreign = await owner(rival, 'get', `/owner/orders/${order.id}`);
    const missing = await owner(rival, 'get', '/owner/orders/2147483000');
    expect(foreign.status).toBe(404);
    expect(missing.status).toBe(404);
    for (const action of ['confirm', 'ready', 'complete', 'no-show']) {
      await act(rival, order.id, action).expect(404);
    }
    await act(rival, order.id, 'cancel', { reason: 'nope' }).expect(404);
    expect((await db.orm.public.Order.first({ id: order.id }))!.status).toBe(
      'PENDING',
    );
  });

  it('answers 404 to an owner who has no store yet', async () => {
    const lonely = await register('OWNER');
    await request(http()).get('/owner/orders').set(auth(lonely)).expect(404);
    await request(http())
      .post('/owner/orders/1/ready')
      .set(auth(lonely))
      .expect(404);
  });
});

describe('owner: transitions', () => {
  it('runs the whole happy path: confirm → ready → complete', async () => {
    const { store, order, lait, customer } = await scenario();
    const confirmed = await act(store, order.id, 'confirm').expect(200);
    expect(confirmed.body).toMatchObject({
      changed: true,
      order: { status: 'CONFIRMED' },
    });
    const ready = await act(store, order.id, 'ready').expect(200);
    expect(ready.body.order.status).toBe('READY_FOR_PICKUP');
    const done = await act(store, order.id, 'complete').expect(200);
    expect(done.body.order.status).toBe('COMPLETED');
    expect(
      done.body.order.events.map((e: { toStatus: string }) => e.toStatus),
    ).toEqual(['PENDING', 'CONFIRMED', 'READY_FOR_PICKUP', 'COMPLETED']);
    expect(await stockOf(lait)).toBe(8); // completing never gives stock back
    const seen = await request(http())
      .get(`/orders/${order.id}`)
      .set(auth(customer))
      .expect(200);
    expect(seen.body.status).toBe('COMPLETED');
  });

  it('confirms with removed lines: total recomputed, stock restored, line kept', async () => {
    const { store, order, lait, yaourt, customer } = await scenario();
    const laitItem = order.items.find(
      (i: { storeProductId: number }) => i.storeProductId === lait,
    );
    const response = await act(store, order.id, 'confirm', {
      removeItemIds: [laitItem.id],
    }).expect(200);
    expect(response.body.order).toMatchObject({
      status: 'CONFIRMED',
      totalMillimes: 2 * 700,
      storeAdjusted: true,
    });
    const removed = response.body.order.items.find(
      (i: { id: number }) => i.id === laitItem.id,
    );
    expect(removed.removedAt).not.toBeNull();
    expect(await stockOf(lait)).toBe(10);
    expect(await stockOf(yaourt)).toBe(8);

    const seen = await request(http())
      .get(`/orders/${order.id}`)
      .set(auth(customer))
      .expect(200);
    expect(seen.body.storeAdjusted).toBe(true);
    expect(seen.body.totalMillimes).toBe(1400);
  });

  it('rejects removing every line, foreign lines and malformed lists', async () => {
    const { store, order } = await scenario();
    const all = order.items.map((i: { id: number }) => i.id);
    await act(store, order.id, 'confirm', { removeItemIds: all }).expect(400);
    await act(store, order.id, 'confirm', {
      removeItemIds: [2147483000],
    }).expect(400);
    await act(store, order.id, 'confirm', { removeItemIds: 'x' }).expect(400);
    await act(store, order.id, 'confirm', { removeItemIds: [0] }).expect(400);
    // Anything but a list of ids is refused outright.
    for (const extra of [
      { totalMillimes: 1 },
      { status: 'READY_FOR_PICKUP' },
      { unitPriceMillimes: 1 },
      { quantity: 1 },
      { stockQuantity: 99 },
    ]) {
      await act(store, order.id, 'confirm', extra).expect(400);
    }
    expect((await db.orm.public.Order.first({ id: order.id }))!.status).toBe(
      'PENDING',
    );
    expect((await itemsOf(order.id)).every((i) => i.removedAt === null)).toBe(
      true,
    );
  });

  it('confirming an already CONFIRMED order ignores the removal list', async () => {
    const { store, order, lait } = await scenario();
    await act(store, order.id, 'confirm').expect(200);
    const again = await act(store, order.id, 'confirm', {
      removeItemIds: order.items.map((i: { id: number }) => i.id), // would be invalid
    }).expect(200);
    expect(again.body).toMatchObject({
      changed: false,
      order: { status: 'CONFIRMED', storeAdjusted: false, totalMillimes: 5000 },
    });
    expect(await stockOf(lait)).toBe(8);
    expect(await eventsOf(order.id)).toHaveLength(2);
  });

  it('cancels a PENDING and a CONFIRMED order with a reason the customer can read', async () => {
    const first = await scenario();
    const done = await act(first.store, first.order.id, 'cancel', {
      reason: '  Produit épuisé  ',
    }).expect(200);
    expect(done.body.order.status).toBe('CANCELLED');
    expect(done.body.order.events.at(-1)).toMatchObject({
      actorType: 'OWNER',
      reason: 'Produit épuisé',
    });
    expect(await stockOf(first.lait)).toBe(10);
    const customerView = await request(http())
      .get(`/orders/${first.order.id}`)
      .set(auth(first.customer))
      .expect(200);
    expect(customerView.body.events.at(-1)).toMatchObject({
      toStatus: 'CANCELLED',
      actorType: 'OWNER',
      reason: 'Produit épuisé',
    });

    const second = await scenario();
    await act(second.store, second.order.id, 'confirm').expect(200);
    await act(second.store, second.order.id, 'cancel', {
      reason: 'Panne',
    }).expect(200);
    expect(await stockOf(second.lait)).toBe(10);
  });

  it('requires a non-empty reason to cancel', async () => {
    const { store, order, lait } = await scenario();
    for (const payload of [
      {},
      { reason: '' },
      { reason: '   ' },
      { reason: 5 },
    ]) {
      await act(store, order.id, 'cancel', payload).expect(400);
    }
    expect((await db.orm.public.Order.first({ id: order.id }))!.status).toBe(
      'PENDING',
    );
    expect(await stockOf(lait)).toBe(8);
  });

  it('marks a READY order as no-show and gives the stock back', async () => {
    const { store, order, lait, yaourt } = await scenario();
    await act(store, order.id, 'confirm').expect(200);
    await act(store, order.id, 'ready').expect(200);
    const response = await act(store, order.id, 'no-show').expect(200);
    expect(response.body.order.status).toBe('NO_SHOW');
    expect(await stockOf(lait)).toBe(10);
    expect(await stockOf(yaourt)).toBe(10);
  });

  it.each([
    ['ready', 'PENDING', []],
    ['complete', 'CONFIRMED', ['confirm']],
    ['no-show', 'CONFIRMED', ['confirm']],
    ['confirm', 'READY_FOR_PICKUP', ['confirm', 'ready']],
    ['cancel', 'READY_FOR_PICKUP', ['confirm', 'ready']],
    ['cancel', 'COMPLETED', ['confirm', 'ready', 'complete']],
    ['cancel', 'NO_SHOW', ['confirm', 'ready', 'no-show']],
    ['confirm', 'CANCELLED', ['cancel']],
  ])(
    '%s on a %s order is 409 ORDER_STATE_CHANGED',
    async (action, status, steps) => {
      const { store, order } = await scenario();
      for (const step of steps) {
        await act(
          store,
          order.id,
          step,
          step === 'cancel' ? { reason: 'x' } : {},
        ).expect(200);
      }
      const response = await act(
        store,
        order.id,
        action,
        action === 'cancel' ? { reason: 'late' } : {},
      );
      expect(response.status).toBe(409);
      expect(response.body).toMatchObject({
        code: 'ORDER_STATE_CHANGED',
        currentStatus: status,
      });
    },
  );

  it('repeating a transition is idempotent (200, changed false)', async () => {
    const { store, order } = await scenario();
    await act(store, order.id, 'confirm').expect(200);
    await act(store, order.id, 'ready').expect(200);
    const again = await act(store, order.id, 'ready').expect(200);
    expect(again.body.changed).toBe(false);
  });
});

// ── Security ──────────────────────────────────────────────────────────────

describe('security', () => {
  it('rejects every orders endpoint without a token', async () => {
    const calls = [
      request(http()).post('/orders').send({}),
      request(http()).get('/orders'),
      request(http()).get('/orders/1'),
      request(http()).post('/orders/1/cancel').send({}),
      request(http()).get('/owner/orders'),
      request(http()).get('/owner/orders/1'),
      ...['confirm', 'ready', 'complete', 'cancel', 'no-show'].map((a) =>
        request(http()).post(`/owner/orders/1/${a}`).send({}),
      ),
    ];
    for (const response of await Promise.all(calls)) {
      expect(response.status).toBe(401);
    }
  });

  it('keeps CLIENTs off the owner endpoints and OWNERs off the customer ones', async () => {
    const { order, customer, store } = await scenario();
    const asClient = [
      request(http()).get('/owner/orders'),
      request(http()).get(`/owner/orders/${order.id}`),
      request(http()).post(`/owner/orders/${order.id}/confirm`).send({}),
      request(http())
        .post(`/owner/orders/${order.id}/cancel`)
        .send({ reason: 'x' }),
    ];
    for (const call of asClient) {
      expect((await call.set(auth(customer))).status).toBe(403);
    }
    const asOwner = [
      request(http()).get('/orders'),
      request(http()).get(`/orders/${order.id}`),
      request(http()).post(`/orders/${order.id}/cancel`).send({}),
      request(http()).post('/orders').send({}),
    ];
    for (const call of asOwner) {
      expect((await call.set(auth(store.owner))).status).toBe(403);
    }
    expect((await db.orm.public.Order.first({ id: order.id }))!.status).toBe(
      'PENDING',
    );
  });
});

// ── Error mapping ─────────────────────────────────────────────────────────

describe('business errors over HTTP', () => {
  it('STORE_CLOSED → 409', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    await db.orm.public.Store.where({ id: store.storeId }).update({
      isOpen: false,
    });
    const customer = await register('CLIENT');
    const response = await placeOrder(
      customer,
      body(store.storeId, [{ storeProductId: lait, quantity: 1 }]),
    );
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('STORE_CLOSED');
  });

  it('PRODUCT_UNAVAILABLE → 409 listing the lines, without stock figures', async () => {
    const store = await openStore();
    const soldOut = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 0,
    });
    const customer = await register('CLIENT');
    const response = await placeOrder(
      customer,
      body(store.storeId, [{ storeProductId: soldOut, quantity: 1 }]),
    );
    expect(response.status).toBe(409);
    expect(response.body).toMatchObject({
      code: 'PRODUCT_UNAVAILABLE',
      lines: [{ storeProductId: soldOut, reason: 'OUT_OF_STOCK' }],
    });
    expect(JSON.stringify(response.body)).not.toMatch(/stockQuantity/);
  });

  it('INSUFFICIENT_STOCK → 409 naming the line, never the stock', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 3,
    });
    const customer = await register('CLIENT');
    const response = await placeOrder(
      customer,
      body(store.storeId, [{ storeProductId: lait, quantity: 4 }]),
    );
    expect(response.status).toBe(409);
    expect(response.body).toMatchObject({
      code: 'INSUFFICIENT_STOCK',
      storeProductId: lait,
    });
    expect(JSON.stringify(response.body)).not.toMatch(
      /\b3\b.*stock|stockQuantity/,
    );
    expect(await stockOf(lait)).toBe(3);
  });

  it('INVALID_QUANTITY → 400 listing the lines', async () => {
    const store = await openStore();
    const banane = await store.offer('banane');
    const customer = await register('CLIENT');
    const response = await placeOrder(
      customer,
      body(store.storeId, [{ storeProductId: banane, quantity: 150 }]),
    );
    expect(response.status).toBe(400);
    expect(response.body).toMatchObject({
      code: 'INVALID_QUANTITY',
      lines: [{ storeProductId: banane, errors: expect.any(Array) }],
    });
  });

  it('INVALID_PICKUP_TIME → 400 for too soon and too far', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const customer = await register('CLIENT');
    for (const hours of [0.1, 49]) {
      const response = await placeOrder(
        customer,
        body(store.storeId, [{ storeProductId: lait, quantity: 1 }], {
          requestedPickupAt: hoursFromNow(hours).toISOString(),
        }),
      );
      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_PICKUP_TIME');
    }
  });

  it('404s for an unknown store and for another store’s product', async () => {
    const store = await openStore();
    const rival = await openStore();
    const rivalProduct = await rival.offer('lait-delice-1l');
    const customer = await register('CLIENT');
    await placeOrder(
      customer,
      body(2147483000, [{ storeProductId: rivalProduct, quantity: 1 }]),
    ).expect(404);
    await placeOrder(
      customer,
      body(store.storeId, [{ storeProductId: rivalProduct, quantity: 1 }]),
    ).expect(404);
  });
});

// ── Idempotency ───────────────────────────────────────────────────────────

describe('idempotency over HTTP', () => {
  it('same key + same request → the original order (200), nothing else created', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customer = await register('CLIENT');
    const payload = body(store.storeId, [
      { storeProductId: lait, quantity: 2 },
    ]);
    const first = await placeOrder(customer, payload).expect(201);
    const retry = await placeOrder(customer, payload).expect(200);
    expect(retry.body).toEqual(first.body);
    expect(await stockOf(lait)).toBe(8);
    const list = await request(http()).get('/orders').set(auth(customer));
    expect(list.body.total).toBe(1);
  });

  it('same key + different request → 409 IDEMPOTENCY_KEY_REUSED', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customer = await register('CLIENT');
    const payload = body(store.storeId, [
      { storeProductId: lait, quantity: 2 },
    ]);
    await placeOrder(customer, payload).expect(201);
    const response = await placeOrder(customer, {
      ...payload,
      lines: [{ storeProductId: lait, quantity: 3 }],
    });
    expect(response.status).toBe(409);
    expect(response.body.code).toBe('IDEMPOTENCY_KEY_REUSED');
    expect(await stockOf(lait)).toBe(8);
  });

  it('the same key from another customer is a different order', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const [a, b] = [await register('CLIENT'), await register('CLIENT')];
    const payload = body(store.storeId, [
      { storeProductId: lait, quantity: 1 },
    ]);
    const first = await placeOrder(a, payload).expect(201);
    const second = await placeOrder(b, payload).expect(201);
    expect(second.body.id).not.toBe(first.body.id);
  });

  it('concurrent retries create exactly one order', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customer = await register('CLIENT');
    const payload = body(store.storeId, [
      { storeProductId: lait, quantity: 2 },
    ]);
    await warmPool();
    const responses = await Promise.all(
      Array.from({ length: 5 }, () => placeOrder(customer, payload)),
    );
    for (const response of responses) {
      expect([200, 201]).toContain(response.status);
      expect(response.body.id).toBe(responses[0]!.body.id);
    }
    expect(responses.filter((r) => r.status === 201)).toHaveLength(1);
    expect(await stockOf(lait)).toBe(8);
    const list = await request(http()).get('/orders').set(auth(customer));
    expect(list.body.total).toBe(1);
  });
});
