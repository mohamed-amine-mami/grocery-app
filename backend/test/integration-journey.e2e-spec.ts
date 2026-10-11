import request from 'supertest';
import { db } from '../src/prisma/db.js';
import {
  archiveCategory,
  archiveProduct,
  removeCatalog,
  seedCatalog,
} from './catalog-helpers.js';
import {
  eventsOf,
  hoursFromNow,
  itemsOf,
  openStore as openStoreFor,
  orderRow,
  setAvailability,
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
 * Final integration verification over HTTP: the same requests the Flutter apps
 * make, checked against the database. Fixture catalog (tagged): banane KG
 * (min 100, step 100, max 10000, tracked here), lait-delice-1l PIECE (tracked),
 * yaourt PIECE max 24 (untracked).
 */

const tag = `e2eint${Date.now()}`;
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

interface Shop {
  store: TestStore;
  banane: number;
  lait: number;
  yaourt: number;
}

/** An open store: bananas 5000 g and milk 10 tracked, yogurt untracked. */
async function shop(): Promise<Shop> {
  const store = await openStore();
  return {
    store,
    banane: await store.offer('banane', {
      trackStock: true,
      stockQuantity: 5000,
      priceMillimes: 1800,
    }),
    lait: await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
      priceMillimes: 1200,
    }),
    yaourt: await store.offer('yaourt', { priceMillimes: 700 }),
  };
}

const orderBody = (
  storeId: number,
  lines: { storeProductId: number; quantity: number }[],
  extra: object = {},
) => ({
  storeId,
  lines,
  requestedPickupAt: hoursFromNow(5).toISOString(),
  idempotencyKey: nextKey(),
  ...extra,
});

const place = (customer: Account, body: object) =>
  request(http()).post('/orders').set(auth(customer)).send(body);

const owner = (s: TestStore, action: string, id: number, body: object = {}) =>
  request(http())
    .post(`/owner/orders/${id}/${action}`)
    .set(auth(s.owner))
    .send(body);

const customerCancel = (customer: Account, id: number) =>
  request(http()).post(`/orders/${id}/cancel`).set(auth(customer)).send({});

const myOrder = (customer: Account, id: number) =>
  request(http()).get(`/orders/${id}`).set(auth(customer));

/** The standard order: 700 g bananas, 2 milks, 3 yogurts (3,240 + ...). */
const standardLines = (s: Shop) => [
  { storeProductId: s.banane, quantity: 700 },
  { storeProductId: s.lait, quantity: 2 },
  { storeProductId: s.yaourt, quantity: 3 },
];
// 700 g × 1,800/kg = 1,260 · 2 × 1,200 = 2,400 · 3 × 700 = 2,100 → 5,760.
const STANDARD_TOTAL = 1260 + 2400 + 2100;

/** Every stock-related key anywhere in a JSON payload. */
const stockLeaks = (payload: unknown) =>
  JSON.stringify(payload).match(
    /stockQuantity|stockDecrementedQuantity|trackStock/g,
  ) ?? [];

// ── 1. The whole journey ──────────────────────────────────────────────────

describe('journey: customer → backend → owner → customer → completion', () => {
  it('runs from browsing to a completed order with exact stock and history', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const pickup = hoursFromNow(5);

    // Choose a store, browse its catalogue (no stock in either response).
    const stores = await request(http())
      .get('/stores')
      .set(auth(customer))
      .expect(200);
    expect(
      stores.body.some((x: { id: number }) => x.id === s.store.storeId),
    ).toBe(true);
    const catalogue = await request(http())
      .get(`/stores/${s.store.storeId}/products`)
      .set(auth(customer))
      .expect(200);
    expect(catalogue.body).toHaveLength(3);
    expect(stockLeaks([stores.body, catalogue.body])).toEqual([]);

    // Submit.
    const created = await place(customer, {
      ...orderBody(s.store.storeId, standardLines(s)),
      requestedPickupAt: pickup.toISOString(),
    }).expect(201);
    const order = created.body;
    expect(stockLeaks(order)).toEqual([]);
    expect(order.status).toBe('PENDING');
    expect(order.code).toMatch(/^[A-Z0-9]{6}$/);
    expect(order.totalMillimes).toBe(STANDARD_TOTAL);

    // The backend row: store, customer, status, total, pickup time.
    const row = (await orderRow(order.id))!;
    expect(row.storeId).toBe(s.store.storeId);
    expect(row.customerId).toBe(customer.id);
    expect(row.status).toBe('PENDING');
    expect(row.totalMillimes).toBe(STANDARD_TOTAL);
    expect(Date.parse(row.requestedPickupAt)).toBe(pickup.getTime());

    // Snapshots, quantities, prices, line totals, recorded stock decrements.
    const items = await itemsOf(order.id);
    const byProduct = (id: number) =>
      items.find((i) => i.storeProductId === id)!;
    expect(byProduct(s.banane)).toMatchObject({
      saleUnitSnapshot: 'KG',
      unitPriceMillimes: 1800,
      quantity: 700,
      lineTotalMillimes: 1260,
      stockDecrementedQuantity: 700,
    });
    expect(byProduct(s.lait)).toMatchObject({
      saleUnitSnapshot: 'PIECE',
      unitPriceMillimes: 1200,
      quantity: 2,
      lineTotalMillimes: 2400,
      stockDecrementedQuantity: 2,
    });
    expect(byProduct(s.yaourt)).toMatchObject({
      unitPriceMillimes: 700,
      quantity: 3,
      lineTotalMillimes: 2100,
      stockDecrementedQuantity: 0, // untracked
    });
    expect(byProduct(s.banane).productNameSnapshot).toContain('Banane');

    // The initial event.
    const initial = await eventsOf(order.id);
    expect(initial).toHaveLength(1);
    expect(initial[0]).toMatchObject({
      fromStatus: null,
      toStatus: 'PENDING',
      actorType: 'CLIENT',
      actorId: customer.id,
    });

    // Stock: exactly what was ordered; untracked untouched.
    expect(await stockOf(s.banane)).toBe(4300);
    expect(await stockOf(s.lait)).toBe(8);
    expect(await stockOf(s.yaourt)).toBeNull();

    // The owner sees the pending order, opens it.
    const list = await request(http())
      .get('/owner/orders?status=PENDING')
      .set(auth(s.store.owner))
      .expect(200);
    expect(list.body.items.map((o: { id: number }) => o.id)).toEqual([
      order.id,
    ]);
    const detail = await request(http())
      .get(`/owner/orders/${order.id}`)
      .set(auth(s.store.owner))
      .expect(200);
    expect(detail.body.customer.phoneNumber).toBe(customer.phoneNumber);

    // The customer polls: PENDING.
    expect((await myOrder(customer, order.id).expect(200)).body.status).toBe(
      'PENDING',
    );

    // Owner confirms, removing the milk line.
    const milkItem = order.items.find(
      (i: { storeProductId: number }) => i.storeProductId === s.lait,
    );
    const confirmed = await owner(s.store, 'confirm', order.id, {
      removeItemIds: [milkItem.id],
    }).expect(200);
    expect(confirmed.body.changed).toBe(true);
    expect(confirmed.body.order.status).toBe('CONFIRMED');
    expect(confirmed.body.order.totalMillimes).toBe(1260 + 2100); // milk excluded
    expect(confirmed.body.order.storeAdjusted).toBe(true);
    // The milk came back exactly once; the others are as they were.
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.banane)).toBe(4300);
    const afterConfirm = await itemsOf(order.id);
    expect(
      afterConfirm.find((i) => i.storeProductId === s.lait)!.removedAt,
    ).not.toBeNull();
    expect(
      afterConfirm.find((i) => i.storeProductId === s.banane)!.removedAt,
    ).toBeNull();
    // A repeated confirm (any removal list) restores and removes nothing more.
    const again = await owner(s.store, 'confirm', order.id, {
      removeItemIds: [byProduct(s.banane).id],
    }).expect(200);
    expect(again.body.changed).toBe(false);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.banane)).toBe(4300);

    // The customer sees CONFIRMED, with the server's new total and the reference.
    const seenConfirmed = (await myOrder(customer, order.id).expect(200)).body;
    expect(seenConfirmed.status).toBe('CONFIRMED');
    expect(seenConfirmed.totalMillimes).toBe(3360);
    expect(seenConfirmed.code).toBe(order.code);
    expect(stockLeaks(seenConfirmed)).toEqual([]);

    // Ready, then the customer sees READY_FOR_PICKUP.
    await owner(s.store, 'ready', order.id).expect(200);
    const seenReady = (await myOrder(customer, order.id).expect(200)).body;
    expect(seenReady.status).toBe('READY_FOR_PICKUP');

    // Complete: final status, history, stock stays consumed.
    const completed = await owner(s.store, 'complete', order.id).expect(200);
    expect(completed.body.order.status).toBe('COMPLETED');
    expect(await stockOf(s.banane)).toBe(4300);
    expect(await stockOf(s.lait)).toBe(10);
    const events = await eventsOf(order.id);
    expect(events.map((e) => [e.fromStatus, e.toStatus])).toEqual([
      [null, 'PENDING'],
      ['PENDING', 'CONFIRMED'],
      ['CONFIRMED', 'READY_FOR_PICKUP'],
      ['READY_FOR_PICKUP', 'COMPLETED'],
    ]);
    expect(events.map((e) => e.actorType)).toEqual([
      'CLIENT',
      'OWNER',
      'OWNER',
      'OWNER',
    ]);

    // Reads and a repeated completion change nothing.
    await myOrder(customer, order.id).expect(200);
    const repeat = await owner(s.store, 'complete', order.id).expect(200);
    expect(repeat.body.changed).toBe(false);
    expect(await stockOf(s.banane)).toBe(4300);
    expect(await eventsOf(order.id)).toHaveLength(4);
    expect(
      stockLeaks(await myOrder(customer, order.id).then((r) => r.body)),
    ).toEqual([]);
  });
});

// ── 2. Cancellation ───────────────────────────────────────────────────────

describe('cancellation', () => {
  it.each([
    ['PENDING', [] as string[]],
    ['CONFIRMED', ['confirm']],
  ])(
    '%s → CANCELLED restores tracked stock exactly once',
    async (_from, steps) => {
      const s = await shop();
      const customer = await register('CLIENT');
      const order = (
        await place(
          customer,
          orderBody(s.store.storeId, standardLines(s)),
        ).expect(201)
      ).body;
      for (const step of steps)
        await owner(s.store, step, order.id).expect(200);
      const historical = (await itemsOf(order.id)).map((i) => [
        i.id,
        i.stockDecrementedQuantity,
      ]);
      expect(await stockOf(s.banane)).toBe(4300);

      const cancelled = await customerCancel(customer, order.id).expect(200);
      expect(cancelled.body.changed).toBe(true);
      expect(cancelled.body.order.status).toBe('CANCELLED');
      expect(await stockOf(s.banane)).toBe(5000);
      expect(await stockOf(s.lait)).toBe(10);
      expect(await stockOf(s.yaourt)).toBeNull(); // untracked: untouched
      const events = await eventsOf(order.id);
      expect(events.at(-1)).toMatchObject({
        fromStatus: _from,
        toStatus: 'CANCELLED',
        actorType: 'CLIENT',
      });
      expect(events).toHaveLength(steps.length + 2);

      // Repeating changes nothing; the historical quantities are unchanged.
      const repeat = await customerCancel(customer, order.id).expect(200);
      expect(repeat.body.changed).toBe(false);
      expect(
        await owner(s.store, 'cancel', order.id, { reason: 'x' }).expect(200),
      ).toBeTruthy();
      expect(await stockOf(s.banane)).toBe(5000);
      expect(await stockOf(s.lait)).toBe(10);
      expect(await eventsOf(order.id)).toHaveLength(steps.length + 2);
      expect(
        (await itemsOf(order.id)).map((i) => [
          i.id,
          i.stockDecrementedQuantity,
        ]),
      ).toEqual(historical);
    },
  );

  it('an owner cancellation carries a reason the customer reads, and restores once', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const order = (
      await place(
        customer,
        orderBody(s.store.storeId, standardLines(s)),
      ).expect(201)
    ).body;
    await owner(s.store, 'confirm', order.id).expect(200);
    await owner(s.store, 'cancel', order.id, {
      reason: 'Produit épuisé',
    }).expect(200);
    expect(await stockOf(s.lait)).toBe(10);
    const seen = (await myOrder(customer, order.id).expect(200)).body;
    expect(seen.events.at(-1)).toMatchObject({
      actorType: 'OWNER',
      reason: 'Produit épuisé',
    });
    await owner(s.store, 'cancel', order.id, { reason: 'encore' }).expect(200);
    expect(await stockOf(s.lait)).toBe(10);
  });

  it('is refused from READY_FOR_PICKUP, COMPLETED and NO_SHOW; a second cancel of a CANCELLED order is the idempotent no-op', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const start = async (steps: string[]) => {
      const order = (
        await place(
          customer,
          orderBody(s.store.storeId, [{ storeProductId: s.lait, quantity: 1 }]),
        ).expect(201)
      ).body;
      for (const step of steps)
        await owner(s.store, step, order.id).expect(200);
      return order.id as number;
    };
    const cases: [string, string[]][] = [
      ['READY_FOR_PICKUP', ['confirm', 'ready']],
      ['COMPLETED', ['confirm', 'ready', 'complete']],
      ['NO_SHOW', ['confirm', 'ready', 'no-show']],
    ];
    for (const [status, steps] of cases) {
      const id = await start(steps);
      const stock = await stockOf(s.lait);
      const byCustomer = await customerCancel(customer, id);
      const byOwner = await owner(s.store, 'cancel', id, { reason: 'x' });
      for (const response of [byCustomer, byOwner]) {
        expect(response.status).toBe(409);
        expect(response.body).toMatchObject({
          code: 'ORDER_STATE_CHANGED',
          currentStatus: status,
        });
      }
      expect((await orderRow(id))!.status).toBe(status);
      expect(await stockOf(s.lait)).toBe(stock); // nothing moved
    }
    const id = await start([]);
    await customerCancel(customer, id).expect(200);
    const stock = await stockOf(s.lait);
    const second = await customerCancel(customer, id).expect(200);
    expect(second.body.changed).toBe(false);
    expect(await stockOf(s.lait)).toBe(stock);
    // And no other move leaves CANCELLED.
    const revived = await owner(s.store, 'confirm', id);
    expect(revived.status).toBe(409);
  });
});

// ── 3. No-show ────────────────────────────────────────────────────────────

describe('no-show', () => {
  it('READY_FOR_PICKUP → NO_SHOW restores tracked stock exactly once', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const order = (
      await place(
        customer,
        orderBody(s.store.storeId, standardLines(s)),
      ).expect(201)
    ).body;
    for (const step of ['confirm', 'ready'])
      await owner(s.store, step, order.id).expect(200);
    expect(await stockOf(s.banane)).toBe(4300);

    const noShow = await owner(s.store, 'no-show', order.id).expect(200);
    expect(noShow.body.order.status).toBe('NO_SHOW');
    expect(await stockOf(s.banane)).toBe(5000);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBeNull();
    const events = await eventsOf(order.id);
    expect(events.at(-1)).toMatchObject({
      fromStatus: 'READY_FOR_PICKUP',
      toStatus: 'NO_SHOW',
      actorType: 'OWNER',
    });
    expect(events).toHaveLength(4);

    // Repeating, and reading, restores nothing more.
    const repeat = await owner(s.store, 'no-show', order.id).expect(200);
    expect(repeat.body.changed).toBe(false);
    await myOrder(customer, order.id).expect(200);
    await request(http())
      .get(`/owner/orders/${order.id}`)
      .set(auth(s.store.owner))
      .expect(200);
    await request(http()).get('/orders').set(auth(customer)).expect(200);
    expect(await stockOf(s.banane)).toBe(5000);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await eventsOf(order.id)).toHaveLength(4);
    // The customer sees it as not collected (NO_SHOW), without stock.
    const seen = (await myOrder(customer, order.id).expect(200)).body;
    expect(seen.status).toBe('NO_SHOW');
    expect(stockLeaks(seen)).toEqual([]);
  });
});

// ── 4. Concurrency over HTTP ──────────────────────────────────────────────

describe('concurrency', () => {
  it('two customers racing for the last unit: exactly one wins, stock never negative, no partial order', async () => {
    for (let round = 0; round < 3; round += 1) {
      const store = await openStore();
      const lait = await store.offer('lait-delice-1l', {
        trackStock: true,
        stockQuantity: 1,
      });
      const [a, b] = [await register('CLIENT'), await register('CLIENT')];
      await warmPool();
      const [ra, rb] = await Promise.all([
        place(
          a,
          orderBody(store.storeId, [{ storeProductId: lait, quantity: 1 }]),
        ),
        place(
          b,
          orderBody(store.storeId, [{ storeProductId: lait, quantity: 1 }]),
        ),
      ]);
      const statuses = [ra.status, rb.status].sort((x, y) => x - y);
      expect(statuses).toEqual([201, 409]);
      const loser = ra.status === 409 ? ra : rb;
      expect(['INSUFFICIENT_STOCK', 'PRODUCT_UNAVAILABLE']).toContain(
        loser.body.code,
      );
      expect(JSON.stringify(loser.body)).not.toMatch(/stockQuantity/);
      expect(await stockOf(lait)).toBe(0);
      const orders = await db.orm.public.Order.where({
        storeId: store.storeId,
      }).all();
      expect(orders).toHaveLength(1);
      expect(await eventsOf(orders[0]!.id)).toHaveLength(1);
      expect(await itemsOf(orders[0]!.id)).toHaveLength(1);
    }
  });

  it('the same request sent at once with one key creates one order, one event, one decrement', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const body = orderBody(s.store.storeId, standardLines(s));
    await warmPool();
    const responses = await Promise.all(
      Array.from({ length: 6 }, () => place(customer, body)),
    );
    for (const r of responses) {
      expect([200, 201]).toContain(r.status);
      expect(r.body.id).toBe(responses[0]!.body.id);
      expect(r.body.totalMillimes).toBe(STANDARD_TOTAL);
    }
    expect(responses.filter((r) => r.status === 201)).toHaveLength(1);
    const orders = await db.orm.public.Order.where({
      customerId: customer.id,
    }).all();
    expect(orders).toHaveLength(1);
    expect(await eventsOf(orders[0]!.id)).toHaveLength(1);
    expect(await stockOf(s.banane)).toBe(4300);
    expect(await stockOf(s.lait)).toBe(8);

    // The same key for a different request is refused, and changes nothing.
    const different = await place(customer, {
      ...body,
      lines: [{ storeProductId: s.lait, quantity: 1 }],
    });
    expect(different.status).toBe(409);
    expect(different.body.code).toBe('IDEMPOTENCY_KEY_REUSED');
    expect(await stockOf(s.lait)).toBe(8);
    expect(
      await db.orm.public.Order.where({ customerId: customer.id }).all(),
    ).toHaveLength(1);
  });

  it.each([
    ['confirm', [] as string[], 'CONFIRMED'],
    ['ready', ['confirm'], 'READY_FOR_PICKUP'],
    ['complete', ['confirm', 'ready'], 'COMPLETED'],
    ['cancel', [] as string[], 'CANCELLED'],
    ['no-show', ['confirm', 'ready'], 'NO_SHOW'],
  ])(
    'duplicate %s requests: one transition, one event, side effects once',
    async (action, steps, target) => {
      const s = await shop();
      const customer = await register('CLIENT');
      const order = (
        await place(
          customer,
          orderBody(s.store.storeId, standardLines(s)),
        ).expect(201)
      ).body;
      for (const step of steps)
        await owner(s.store, step, order.id).expect(200);
      const eventsBefore = (await eventsOf(order.id)).length;
      const body = action === 'cancel' ? { reason: 'Panne' } : {};
      await warmPool();

      const responses = await Promise.all(
        Array.from({ length: 5 }, () => owner(s.store, action, order.id, body)),
      );

      for (const r of responses) {
        expect([200, 409]).toContain(r.status); // winner/idempotent, or state-changed
        if (r.status === 409) expect(r.body.code).toBe('ORDER_STATE_CHANGED');
      }
      expect(
        responses.filter((r) => r.status === 200 && r.body.changed),
      ).toHaveLength(1);
      expect((await orderRow(order.id))!.status).toBe(target);
      expect(await eventsOf(order.id)).toHaveLength(eventsBefore + 1);
      const restored = target === 'CANCELLED' || target === 'NO_SHOW';
      expect(await stockOf(s.banane)).toBe(restored ? 5000 : 4300);
      expect(await stockOf(s.lait)).toBe(restored ? 10 : 8);
    },
  );

  it('owner confirming vs customer cancelling leaves exactly one valid state, stock exact', async () => {
    for (let round = 0; round < 6; round += 1) {
      const s = await shop();
      const customer = await register('CLIENT');
      const order = (
        await place(
          customer,
          orderBody(s.store.storeId, standardLines(s)),
        ).expect(201)
      ).body;
      await warmPool();
      const [confirm, cancel] = await Promise.all([
        owner(s.store, 'confirm', order.id),
        customerCancel(customer, order.id),
      ]);
      expect([200, 409]).toContain(confirm.status);
      expect([200, 409]).toContain(cancel.status);

      const status = (await orderRow(order.id))!.status;
      expect(['CONFIRMED', 'CANCELLED']).toContain(status);
      const events = await eventsOf(order.id);
      // A valid chain: created, then confirmed and/or cancelled, in order.
      const chain = events.map((e) => e.toStatus);
      expect([
        ['PENDING', 'CONFIRMED'],
        ['PENDING', 'CANCELLED'],
        ['PENDING', 'CONFIRMED', 'CANCELLED'],
      ]).toContainEqual(chain);
      expect(chain.at(-1)).toBe(status);
      // Stock: consumed unless cancelled, and never restored twice.
      expect(await stockOf(s.banane)).toBe(
        status === 'CANCELLED' ? 5000 : 4300,
      );
      expect(await stockOf(s.lait)).toBe(status === 'CANCELLED' ? 10 : 8);
    }
  });
});

// ── 5. Security and isolation ─────────────────────────────────────────────

describe('security and isolation', () => {
  it('customers and owners cannot see or touch what is not theirs', async () => {
    const a = await shop();
    const b = await shop();
    const alice = await register('CLIENT');
    const bob = await register('CLIENT');
    const orderA = (
      await place(alice, orderBody(a.store.storeId, standardLines(a))).expect(
        201,
      )
    ).body;
    const orderB = (
      await place(bob, orderBody(b.store.storeId, standardLines(b))).expect(201)
    ).body;

    // Customer A vs customer B's order.
    const list = await request(http())
      .get('/orders')
      .set(auth(alice))
      .expect(200);
    expect(list.body.items.map((o: { id: number }) => o.id)).toEqual([
      orderA.id,
    ]);
    await myOrder(alice, orderB.id).expect(404);
    await customerCancel(alice, orderB.id).expect(404);
    expect((await orderRow(orderB.id))!.status).toBe('PENDING');

    // Owner A vs store B's orders.
    const ownerList = await request(http())
      .get('/owner/orders')
      .set(auth(a.store.owner))
      .expect(200);
    expect(ownerList.body.items.map((o: { id: number }) => o.id)).toEqual([
      orderA.id,
    ]);
    await request(http())
      .get(`/owner/orders/${orderB.id}`)
      .set(auth(a.store.owner))
      .expect(404);
    for (const action of ['confirm', 'ready', 'complete', 'no-show']) {
      await owner(a.store, action, orderB.id).expect(404);
    }
    await owner(a.store, 'cancel', orderB.id, { reason: 'x' }).expect(404);
    expect((await orderRow(orderB.id))!.status).toBe('PENDING');
    expect(await stockOf(b.banane)).toBe(4300);
    expect(await eventsOf(orderB.id)).toHaveLength(1);
  });

  it('a product of store B cannot be ordered at store A: rejected, nothing mutated', async () => {
    const a = await shop();
    const b = await shop();
    const customer = await register('CLIENT');
    const response = await place(
      customer,
      orderBody(a.store.storeId, [
        { storeProductId: a.lait, quantity: 1 },
        { storeProductId: b.lait, quantity: 1 },
      ]),
    );
    expect(response.status).toBe(404);
    expect(await stockOf(a.lait)).toBe(10);
    expect(await stockOf(b.lait)).toBe(10);
    expect(
      await db.orm.public.Order.where({ customerId: customer.id }).all(),
    ).toHaveLength(0);
  });

  it('roles: owners cannot use customer order endpoints, customers cannot manage orders', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const order = (
      await place(
        customer,
        orderBody(s.store.storeId, standardLines(s)),
      ).expect(201)
    ).body;
    const ownerToken = auth(s.store.owner);
    await request(http())
      .post('/orders')
      .set(ownerToken)
      .send(orderBody(s.store.storeId, standardLines(s)))
      .expect(403);
    await request(http()).get('/orders').set(ownerToken).expect(403);
    await request(http())
      .get(`/orders/${order.id}`)
      .set(ownerToken)
      .expect(403);
    await request(http())
      .post(`/orders/${order.id}/cancel`)
      .set(ownerToken)
      .send({})
      .expect(403);
    await request(http()).get('/stores').set(ownerToken).expect(403);
    await request(http()).get('/owner/orders').set(auth(customer)).expect(403);
    for (const action of ['confirm', 'ready', 'complete', 'no-show']) {
      await request(http())
        .post(`/owner/orders/${order.id}/${action}`)
        .set(auth(customer))
        .send({})
        .expect(403);
    }
    await request(http()).get('/orders').expect(401);
    expect((await orderRow(order.id))!.status).toBe('PENDING');
  });
});

// ── 6. Historical integrity ───────────────────────────────────────────────

describe('historical integrity', () => {
  it('later catalog changes never rewrite an existing order, and restoration uses the historical quantity', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const order = (
      await place(
        customer,
        orderBody(s.store.storeId, standardLines(s)),
      ).expect(201)
    ).body;
    const before = (await myOrder(customer, order.id).expect(200)).body;
    const snapshot = (body: { items: object[]; totalMillimes: number }) => ({
      items: body.items,
      total: body.totalMillimes,
    });

    // Rename the global product, change price, rules, availability; archive
    // the global product and category; switch stock tracking and the count.
    await db.orm.public.Product.where({
      id: catalog.productId('banane'),
    }).update({ name: 'Renamed globally' });
    await request(http())
      .patch(`/owner/store-products/${s.banane}`)
      .set(auth(s.store.owner))
      .send({ priceMillimes: 9999, minQuantity: 500, quantityStep: 500 })
      .expect(200);
    await setAvailability(s.store, s.lait, false);
    await request(http())
      .patch(`/owner/store-products/${s.lait}`)
      .set(auth(s.store.owner))
      .send({
        trackStock: true,
        stockQuantity: 100,
        expectedStockQuantity: await stockOf(s.lait),
      })
      .expect(200);
    await archiveProduct(catalog.productId('lait-delice-1l'));
    await archiveCategory(catalog.categoryId('laitiers'));
    try {
      const after = (await myOrder(customer, order.id).expect(200)).body;
      expect(snapshot(after)).toEqual(snapshot(before));
      expect(after.items[0].productName).not.toContain('Renamed');
      const ownerView = (
        await request(http())
          .get(`/owner/orders/${order.id}`)
          .set(auth(s.store.owner))
          .expect(200)
      ).body;
      expect(snapshot(ownerView)).toEqual(snapshot(before));

      // The order can still be cancelled; the historical amounts come back,
      // not anything derived from the changed configuration.
      const milkStock = (await stockOf(s.lait))!; // 100 now
      await customerCancel(customer, order.id).expect(200);
      expect(await stockOf(s.lait)).toBe(milkStock + 2);
      expect(await stockOf(s.banane)).toBe(5000);
    } finally {
      await db.orm.public.Product.where({
        id: catalog.productId('banane'),
      }).update({ name: `Banane ${tag}` });
      await db.orm.public.Product.where({
        id: catalog.productId('lait-delice-1l'),
      }).update({ archivedAt: null });
      await db.orm.public.Category.where({
        id: catalog.categoryId('laitiers'),
      }).update({ archivedAt: null });
    }
  });
});

// ── 7. Stale catalogue never bypasses checkout ────────────────────────────

describe('checkout refuses stale or invalid data without a partial order', () => {
  const nothingChanged = async (s: Shop, customer: Account) => {
    expect(
      await db.orm.public.Order.where({ customerId: customer.id }).all(),
    ).toHaveLength(0);
    expect(await stockOf(s.banane)).toBe(5000);
    expect(await stockOf(s.lait)).toBe(10);
  };

  it.each([
    ['archived product', 409, 'PRODUCT_UNAVAILABLE'],
    ['archived category', 409, 'PRODUCT_UNAVAILABLE'],
    ['unavailable store product', 409, 'PRODUCT_UNAVAILABLE'],
    ['insufficient stock', 409, 'INSUFFICIENT_STOCK'],
    ['quantity below the minimum', 400, 'INVALID_QUANTITY'],
    ['quantity above the maximum', 400, 'INVALID_QUANTITY'],
    ['invalid quantity step', 400, 'INVALID_QUANTITY'],
    ['closed store', 409, 'STORE_CLOSED'],
  ])('%s', async (kind, status, code) => {
    const s = await shop();
    const customer = await register('CLIENT');
    // The customer browsed first: the catalogue offered all of it.
    const seen = await request(http())
      .get(`/stores/${s.store.storeId}/products`)
      .set(auth(customer))
      .expect(200);
    expect(
      seen.body.every((p: { isOrderable: boolean }) => p.isOrderable),
    ).toBe(true);

    let lines = [
      { storeProductId: s.banane, quantity: 500 },
      { storeProductId: s.lait, quantity: 1 },
    ];
    const restore: (() => Promise<unknown>)[] = [];
    if (kind === 'archived product') {
      await archiveProduct(catalog.productId('lait-delice-1l'));
      restore.push(() =>
        db.orm.public.Product.where({
          id: catalog.productId('lait-delice-1l'),
        }).update({ archivedAt: null }),
      );
    } else if (kind === 'archived category') {
      await archiveCategory(catalog.categoryId('laitiers'));
      restore.push(() =>
        db.orm.public.Category.where({
          id: catalog.categoryId('laitiers'),
        }).update({ archivedAt: null }),
      );
    } else if (kind === 'unavailable store product') {
      await setAvailability(s.store, s.lait, false);
    } else if (kind === 'insufficient stock') {
      lines = [
        { storeProductId: s.banane, quantity: 500 },
        { storeProductId: s.lait, quantity: 11 },
      ];
    } else if (kind === 'quantity below the minimum') {
      lines[0]!.quantity = 50;
    } else if (kind === 'quantity above the maximum') {
      lines[0]!.quantity = 10100;
    } else if (kind === 'invalid quantity step') {
      lines[0]!.quantity = 550;
    } else {
      await db.orm.public.Store.where({ id: s.store.storeId }).update({
        isOpen: false,
      });
    }
    try {
      const response = await place(customer, orderBody(s.store.storeId, lines));
      expect(response.status).toBe(status);
      expect(response.body.code).toBe(code);
      expect(stockLeaks(response.body)).toEqual([]);
      expect(JSON.stringify(response.body)).not.toMatch(/\b5000\b/);
      await nothingChanged(s, customer);
    } finally {
      for (const undo of restore) await undo();
    }
  });

  it('never exposes stock or owner information to a customer', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const order = (
      await place(
        customer,
        orderBody(s.store.storeId, standardLines(s)),
      ).expect(201)
    ).body;
    const payloads = [
      (await request(http()).get('/stores').set(auth(customer))).body,
      (
        await request(http())
          .get(`/stores/${s.store.storeId}/products`)
          .set(auth(customer))
      ).body,
      order,
      (await request(http()).get('/orders').set(auth(customer))).body,
      (await myOrder(customer, order.id)).body,
      (await customerCancel(customer, order.id)).body,
    ];
    for (const payload of payloads) {
      expect(stockLeaks(payload)).toEqual([]);
      const text = JSON.stringify(payload);
      expect(text).not.toContain(s.store.owner.phoneNumber);
      expect(text).not.toMatch(/ownerId|"email"|password/);
    }
  });
});

// ── 8. Pickup time ────────────────────────────────────────────────────────

describe('pickup time', () => {
  it('accepts 30 minutes to 48 hours ahead and refuses outside, with a stable code', async () => {
    const s = await shop();
    const customer = await register('CLIENT');
    const at = (minutes: number) =>
      new Date(Date.now() + minutes * 60_000).toISOString();
    const line = [{ storeProductId: s.yaourt, quantity: 1 }];
    const attempt = (minutes: number) =>
      place(
        customer,
        orderBody(s.store.storeId, line, { requestedPickupAt: at(minutes) }),
      );

    for (const minutes of [31, 120, 24 * 60, 48 * 60 - 1]) {
      expect((await attempt(minutes)).status).toBe(201);
    }
    for (const minutes of [-5, 5, 29, 48 * 60 + 5, 72 * 60]) {
      const response = await attempt(minutes);
      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_PICKUP_TIME');
    }
    expect(
      await db.orm.public.Order.where({ customerId: customer.id }).all(),
    ).toHaveLength(4);
  });
});
