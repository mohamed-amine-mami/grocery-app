import type { HttpException } from '@nestjs/common';
import request from 'supertest';
import { OrderErrorCode } from '../src/orders/order-errors.js';
import { isOrderCode } from '../src/orders/order-rules.js';
import type { CreateOrderCommand } from '../src/orders/order.types.js';
import { OrdersService } from '../src/orders/orders.service.js';
import { db } from '../src/prisma/db.js';
import {
  archiveProduct,
  removeCatalog,
  seedCatalog,
} from './catalog-helpers.js';
import {
  eventsOf,
  failure,
  hoursFromNow,
  itemsOf,
  openStore as openStoreFor,
  ordersAt,
  ordersOf,
  setAvailability,
  stockOf,
  warmPool,
} from './order-test-helpers.js';
import { auth, http, register, startApp, stopApp } from './support.js';

/**
 * The order creation service, against the real test database. Only the setup
 * (owners, stores, offerings, price changes) goes through the HTTP API; orders
 * are placed by calling the service directly, since it has no HTTP of its own.
 * Fixture catalog (tagged): banane KG min 100 step 100 max 10000;
 * lait-delice-1l PIECE min 1 step 1; yaourt PIECE min 1 step 1 max 24.
 */

const tag = `e2eord${Date.now()}`;
const service = new OrdersService();
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

// ── Helpers ───────────────────────────────────────────────────────────────

const nextKey = () => `key-${tag}-${(keyCounter += 1)}`;

/** A fresh open store with its own owner, so tests never share stock. */
const openStore = () => openStoreFor((slug) => catalog.productId(slug));

const newCustomer = () => register('CLIENT');

/** Places an order with sensible defaults; override anything. */
const place = (
  customerId: number,
  storeId: number,
  lines: CreateOrderCommand['lines'],
  overrides: Partial<CreateOrderCommand> = {},
) =>
  service.createOrder({
    customerId,
    storeId,
    lines,
    requestedPickupAt: hoursFromNow(4),
    idempotencyKey: nextKey(),
    ...overrides,
  });

// ── 1. Normal creation ────────────────────────────────────────────────────

describe('creating an order', () => {
  it('creates a PENDING order with server-side snapshots and totals', async () => {
    const store = await openStore();
    const banane = await store.offer('banane', { priceMillimes: 1800 });
    const yaourt = await store.offer('yaourt', { priceMillimes: 350 });
    const customer = await newCustomer();
    const pickup = hoursFromNow(5);

    const { order, created } = await place(
      customer.id,
      store.storeId,
      [
        { storeProductId: banane, quantity: 1500 }, // 1,5 kg
        { storeProductId: yaourt, quantity: 4 },
      ],
      { requestedPickupAt: pickup },
    );

    expect(created).toBe(true);
    expect(order).toMatchObject({
      customerId: customer.id,
      storeId: store.storeId,
      status: 'PENDING',
    });
    expect(isOrderCode(order.code)).toBe(true);
    expect(new Date(order.requestedPickupAt).getTime()).toBe(pickup.getTime());
    // 1800 millimes/kg × 1,5 kg = 2700; 350 × 4 = 1400.
    expect(order.totalMillimes).toBe(4100);
    expect(order.items).toHaveLength(2);
    const [bananeItem, yaourtItem] = order.items;
    expect(bananeItem).toMatchObject({
      storeProductId: banane,
      saleUnitSnapshot: 'KG',
      unitPriceMillimes: 1800,
      quantity: 1500,
      lineTotalMillimes: 2700,
      removedAt: null,
    });
    expect(yaourtItem).toMatchObject({
      storeProductId: yaourt,
      saleUnitSnapshot: 'PIECE',
      unitPriceMillimes: 350,
      quantity: 4,
      lineTotalMillimes: 1400,
    });
    // It is really in the database.
    expect(await ordersOf(customer.id)).toHaveLength(1);
    expect(await itemsOf(order.id)).toHaveLength(2);
  });

  it('is not influenced by anything but the lines: totals are computed here', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', { priceMillimes: 2400 });
    const customer = await newCustomer();

    const { order } = await place(customer.id, store.storeId, [
      // Extra fields a client might send are not part of the command.
      { storeProductId: lait, quantity: 3, price: 1, total: 1 } as never,
    ]);

    expect(order.totalMillimes).toBe(7200);
    expect(order.items[0]!.unitPriceMillimes).toBe(2400);
  });
});

// ── Validation ────────────────────────────────────────────────────────────

describe('validation', () => {
  it('rejects an order with no lines', async () => {
    const store = await openStore();
    const customer = await newCustomer();
    const { status } = await failure(place(customer.id, store.storeId, []));
    expect(status).toBe(400);
  });

  it.each([['   '], [''], ['k'.repeat(101)]])(
    'rejects the idempotency key %j',
    async (key) => {
      const store = await openStore();
      const lait = await store.offer('lait-delice-1l');
      const customer = await newCustomer();
      const { status } = await failure(
        place(
          customer.id,
          store.storeId,
          [{ storeProductId: lait, quantity: 1 }],
          {
            idempotencyKey: key,
          },
        ),
      );
      expect(status).toBe(400);
    },
  );

  it('rejects an unknown customer (404) and an owner as customer (403)', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const lines = [{ storeProductId: lait, quantity: 1 }];

    expect(
      (await failure(place(2_000_000_000, store.storeId, lines))).status,
    ).toBe(404);
    expect(
      (await failure(place(store.owner.id, store.storeId, lines))).status,
    ).toBe(403);
  });

  it('rejects an unknown store', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const customer = await newCustomer();
    const { status } = await failure(
      place(customer.id, 2_000_000_000, [
        { storeProductId: lait, quantity: 1 },
      ]),
    );
    expect(status).toBe(404);
  });

  it('refuses a closed store with STORE_CLOSED and changes nothing', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    await db.orm.public.Store.where({ id: store.storeId }).update({
      isOpen: false,
    });
    const customer = await newCustomer();

    const { status, body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: lait, quantity: 2 },
      ]),
    );

    expect(status).toBe(409);
    expect(body['code']).toBe(OrderErrorCode.STORE_CLOSED);
    expect(await ordersOf(customer.id)).toHaveLength(0);
    expect(await stockOf(lait)).toBe(10);
  });

  it("treats another store's product as not found, naming it", async () => {
    const mine = await openStore();
    const other = await openStore();
    const otherLait = await other.offer('lait-delice-1l');
    const myLait = await mine.offer('lait-delice-1l');
    const customer = await newCustomer();

    const { status, body } = await failure(
      place(customer.id, mine.storeId, [
        { storeProductId: myLait, quantity: 1 },
        { storeProductId: otherLait, quantity: 1 },
      ]),
    );

    expect(status).toBe(404);
    expect(body['storeProductIds']).toEqual([otherLait]);
    expect(await ordersOf(customer.id)).toHaveLength(0);
  });

  it('refuses an archived store product (ARCHIVED), naming it', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    await request(http())
      .delete(`/owner/store-products/${lait}`)
      .set(auth(store.owner))
      .expect(204);
    const customer = await newCustomer();

    const { status, body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: lait, quantity: 1 },
      ]),
    );

    expect(status).toBe(409);
    expect(body['code']).toBe(OrderErrorCode.PRODUCT_UNAVAILABLE);
    expect(body['lines']).toEqual([
      { storeProductId: lait, reason: 'ARCHIVED' },
    ]);
  });

  it('refuses an owner-disabled product (OWNER_DISABLED)', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    await setAvailability(store, lait, false);
    const customer = await newCustomer();

    const { body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: lait, quantity: 1 },
      ]),
    );

    expect(body['code']).toBe(OrderErrorCode.PRODUCT_UNAVAILABLE);
    expect(body['lines']).toEqual([
      { storeProductId: lait, reason: 'OWNER_DISABLED' },
    ]);
  });

  it('refuses a product the catalog archived (CATALOG_ARCHIVED)', async () => {
    const store = await openStore();
    const yaourt = await store.offer('yaourt');
    const customer = await newCustomer();
    await archiveProduct(catalog.productId('yaourt'));
    try {
      const { body } = await failure(
        place(customer.id, store.storeId, [
          { storeProductId: yaourt, quantity: 1 },
        ]),
      );
      expect(body['lines']).toEqual([
        { storeProductId: yaourt, reason: 'CATALOG_ARCHIVED' },
      ]);
    } finally {
      await db.orm.public.Product.where({
        id: catalog.productId('yaourt'),
      }).update({ archivedAt: null });
    }
  });

  it('refuses out-of-stock and below-minimum stock as unavailable, via the canonical rule', async () => {
    const store = await openStore();
    const empty = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 0,
    });
    const low = await store.offer('banane', {
      trackStock: true,
      stockQuantity: 50, // below the 100 g minimum
    });
    const customer = await newCustomer();

    const { body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: empty, quantity: 1 },
        { storeProductId: low, quantity: 100 },
      ]),
    );

    expect(body['code']).toBe(OrderErrorCode.PRODUCT_UNAVAILABLE);
    expect(body['lines']).toEqual([
      { storeProductId: empty, reason: 'OUT_OF_STOCK' },
      { storeProductId: low, reason: 'STOCK_BELOW_MINIMUM' },
    ]);
  });

  it('reports every unavailable line at once', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const yaourt = await store.offer('yaourt');
    await setAvailability(store, lait, false);
    await request(http())
      .delete(`/owner/store-products/${yaourt}`)
      .set(auth(store.owner))
      .expect(204);
    const customer = await newCustomer();

    const { body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: lait, quantity: 1 },
        { storeProductId: yaourt, quantity: 1 },
      ]),
    );

    expect(body['lines']).toEqual([
      { storeProductId: lait, reason: 'OWNER_DISABLED' },
      { storeProductId: yaourt, reason: 'ARCHIVED' },
    ]);
  });

  it('rejects quantities that break min / step / max, naming each line', async () => {
    const store = await openStore();
    const banane = await store.offer('banane'); // min 100 step 100 max 10000
    const yaourt = await store.offer('yaourt'); // max 24
    const customer = await newCustomer();

    const { status, body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: banane, quantity: 150 }, // off the step
        { storeProductId: yaourt, quantity: 25 }, // above the max
      ]),
    );

    expect(status).toBe(400);
    expect(body['code']).toBe(OrderErrorCode.INVALID_QUANTITY);
    expect(body['lines']).toEqual([
      {
        storeProductId: banane,
        errors: ['quantity must be a multiple of 100 grams'],
      },
      {
        storeProductId: yaourt,
        errors: ['quantity must be at most 24 pieces'],
      },
    ]);
    expect(await ordersOf(customer.id)).toHaveLength(0);
  });

  it.each([[0], [-3], [1.5], [50]])(
    'rejects the quantity %s (below minimum or not an integer)',
    async (quantity) => {
      const store = await openStore();
      const banane = await store.offer('banane');
      const customer = await newCustomer();
      const { body } = await failure(
        place(customer.id, store.storeId, [
          { storeProductId: banane, quantity },
        ]),
      );
      expect(body['code']).toBe(OrderErrorCode.INVALID_QUANTITY);
    },
  );

  it.each([
    ['too soon', 10 / 60],
    ['too far', 49],
  ])('rejects a pickup time that is %s', async (_label, hours) => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const customer = await newCustomer();
    const { status, body } = await failure(
      place(
        customer.id,
        store.storeId,
        [{ storeProductId: lait, quantity: 1 }],
        {
          requestedPickupAt: hoursFromNow(hours),
        },
      ),
    );
    expect(status).toBe(400);
    expect(body['code']).toBe(OrderErrorCode.INVALID_PICKUP_TIME);
  });

  it('rejects duplicate lines for the same store product', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customer = await newCustomer();

    const { status, body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: lait, quantity: 1 },
        { storeProductId: lait, quantity: 2 },
      ]),
    );

    expect(status).toBe(400);
    expect(body['storeProductIds']).toEqual([lait]);
    expect(await stockOf(lait)).toBe(10);
    expect(await ordersOf(customer.id)).toHaveLength(0);
  });

  it('rejects an order whose total rounds to zero', async () => {
    const store = await openStore();
    const banane = await store.offer('banane', { priceMillimes: 1 });
    const customer = await newCustomer();
    const { status } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: banane, quantity: 100 }, // 1 millime/kg × 100 g = 0
      ]),
    );
    expect(status).toBe(400);
  });

  it('checks things in the documented order (a closed store wins over a bad line)', async () => {
    const store = await openStore();
    const banane = await store.offer('banane');
    await db.orm.public.Store.where({ id: store.storeId }).update({
      isOpen: false,
    });
    const customer = await newCustomer();
    const { body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: banane, quantity: 150 },
      ]),
    );
    expect(body['code']).toBe(OrderErrorCode.STORE_CLOSED);
  });
});

// ── Stock ─────────────────────────────────────────────────────────────────

describe('stock', () => {
  it('decrements tracked stock exactly, and records it on the item', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const banane = await store.offer('banane', {
      trackStock: true,
      stockQuantity: 5000,
    });
    const customer = await newCustomer();

    const { order } = await place(customer.id, store.storeId, [
      { storeProductId: lait, quantity: 4 },
      { storeProductId: banane, quantity: 1500 },
    ]);

    expect(await stockOf(lait)).toBe(6);
    expect(await stockOf(banane)).toBe(3500);
    expect(
      order.items.map((i) => [i.storeProductId, i.stockDecrementedQuantity]),
    ).toEqual([
      [lait, 4],
      [banane, 1500],
    ]);
  });

  it('can take the last of the stock', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 3,
    });
    const customer = await newCustomer();

    await place(customer.id, store.storeId, [
      { storeProductId: lait, quantity: 3 },
    ]);

    expect(await stockOf(lait)).toBe(0);
  });

  it('leaves untracked stock alone and records zero', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l'); // not tracked
    const customer = await newCustomer();

    const { order } = await place(customer.id, store.storeId, [
      { storeProductId: lait, quantity: 5 },
    ]);

    expect(await stockOf(lait)).toBeNull();
    expect(order.items[0]!.stockDecrementedQuantity).toBe(0);
  });

  it('mixes tracked and untracked lines', async () => {
    const store = await openStore();
    const tracked = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const untracked = await store.offer('yaourt');
    const customer = await newCustomer();

    const { order } = await place(customer.id, store.storeId, [
      { storeProductId: tracked, quantity: 2 },
      { storeProductId: untracked, quantity: 2 },
    ]);

    expect(await stockOf(tracked)).toBe(8);
    expect(await stockOf(untracked)).toBeNull();
    expect(order.items.map((i) => i.stockDecrementedQuantity)).toEqual([2, 0]);
  });

  it('fails with INSUFFICIENT_STOCK naming the line, never revealing the stock', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 3,
    });
    const customer = await newCustomer();

    const { status, body } = await failure(
      place(customer.id, store.storeId, [
        { storeProductId: lait, quantity: 5 },
      ]),
    );

    expect(status).toBe(409);
    expect(body['code']).toBe(OrderErrorCode.INSUFFICIENT_STOCK);
    expect(body['storeProductId']).toBe(lait);
    const text = JSON.stringify(body);
    expect(text).not.toMatch(/stock(Quantity)?"\s*:\s*\d/i);
    expect(Object.keys(body)).not.toContain('currentStockQuantity');
    expect(Object.keys(body)).not.toContain('stockQuantity');
    expect(await stockOf(lait)).toBe(3);
  });

  it('rolls everything back when a later line fails', async () => {
    const store = await openStore();
    // Created in this order, so the first has the lower id and is decremented first.
    const first = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const second = await store.offer('yaourt', {
      trackStock: true,
      stockQuantity: 1,
    });
    const customer = await newCustomer();
    const key = nextKey();

    const { body } = await failure(
      place(
        customer.id,
        store.storeId,
        [
          { storeProductId: first, quantity: 4 },
          { storeProductId: second, quantity: 5 },
        ],
        { idempotencyKey: key },
      ),
    );

    expect(body['code']).toBe(OrderErrorCode.INSUFFICIENT_STOCK);
    expect(body['storeProductId']).toBe(second);
    // The first line's decrement and the order row itself are gone.
    expect(await stockOf(first)).toBe(10);
    expect(await stockOf(second)).toBe(1);
    expect(await ordersOf(customer.id)).toHaveLength(0);
    expect(await ordersAt(store.storeId)).toHaveLength(0);

    // The key was not consumed: the same key can order successfully afterwards.
    const { order, created } = await place(
      customer.id,
      store.storeId,
      [{ storeProductId: first, quantity: 4 }],
      { idempotencyKey: key },
    );
    expect(created).toBe(true);
    expect(order.items).toHaveLength(1);
    expect(await stockOf(first)).toBe(6);
  });

  it('lets only one of two customers take the last unit', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 1,
    });
    const [a, b] = [await newCustomer(), await newCustomer()];

    await warmPool();
    const results = await Promise.allSettled([
      place(a.id, store.storeId, [{ storeProductId: lait, quantity: 1 }]),
      place(b.id, store.storeId, [{ storeProductId: lait, quantity: 1 }]),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    // The loser is told there is no stock: either the decrement found none, or
    // it read the product after the winner had already emptied it.
    const reason = (rejected[0] as PromiseRejectedResult)
      .reason as HttpException;
    expect([
      OrderErrorCode.INSUFFICIENT_STOCK,
      OrderErrorCode.PRODUCT_UNAVAILABLE,
    ]).toContain((reason.getResponse() as { code: string }).code);
    expect(await stockOf(lait)).toBe(0);
    expect(await ordersAt(store.storeId)).toHaveLength(1);
  });

  it('never oversells under many competing customers', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 3,
    });
    const customers = await Promise.all(
      Array.from({ length: 10 }, () => newCustomer()),
    );

    await warmPool();
    const results = await Promise.allSettled(
      customers.map((c) =>
        place(c.id, store.storeId, [{ storeProductId: lait, quantity: 1 }]),
      ),
    );

    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(3);
    expect(await stockOf(lait)).toBe(0);
    const orders = await ordersAt(store.storeId);
    expect(orders).toHaveLength(3);
    const decremented = (await Promise.all(orders.map((o) => itemsOf(o.id))))
      .flat()
      .reduce((sum, item) => sum + item.stockDecrementedQuantity, 0);
    expect(decremented).toBe(3);
  });

  it('handles concurrent multi-line orders without deadlock or oversell', async () => {
    const store = await openStore();
    const first = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const second = await store.offer('yaourt', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customers = await Promise.all(
      Array.from({ length: 8 }, () => newCustomer()),
    );

    // Each wants 2 of each; half list the lines in the opposite order, which
    // would deadlock without a stable decrement order.
    await warmPool();
    const results = await Promise.allSettled(
      customers.map((c, index) => {
        const lines = [
          { storeProductId: first, quantity: 2 },
          { storeProductId: second, quantity: 2 },
        ];
        return place(
          c.id,
          store.storeId,
          index % 2 === 0 ? lines : [...lines].reverse(),
        );
      }),
    );

    // 10 / 2 = exactly 5 orders fit; everything settles, no deadlock errors.
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    expect(fulfilled).toHaveLength(5);
    for (const result of results) {
      if (result.status === 'rejected') {
        const code = (
          (result.reason as HttpException).getResponse() as {
            code?: string;
          }
        ).code;
        expect([
          OrderErrorCode.INSUFFICIENT_STOCK,
          OrderErrorCode.PRODUCT_UNAVAILABLE,
        ]).toContain(code);
      }
    }
    expect(await stockOf(first)).toBe(0);
    expect(await stockOf(second)).toBe(0);
    expect(await ordersAt(store.storeId)).toHaveLength(5);
  });
});

// ── Idempotency ───────────────────────────────────────────────────────────

describe('idempotency', () => {
  it('returns the existing order when the same customer retries', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customer = await newCustomer();
    const command = {
      customerId: customer.id,
      storeId: store.storeId,
      lines: [{ storeProductId: lait, quantity: 3 }],
      requestedPickupAt: hoursFromNow(4),
      idempotencyKey: nextKey(),
    };

    const first = await service.createOrder(command);
    const retry = await service.createOrder(command);

    expect(first.created).toBe(true);
    expect(retry.created).toBe(false);
    expect(retry.order).toEqual(first.order);
    expect(await ordersOf(customer.id)).toHaveLength(1);
    expect(await stockOf(lait)).toBe(7); // decremented once
    expect(await eventsOf(first.order.id)).toHaveLength(1);
  });

  it('still answers a retry after the store closed or the stock ran out', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 2,
    });
    const customer = await newCustomer();
    const command = {
      customerId: customer.id,
      storeId: store.storeId,
      lines: [{ storeProductId: lait, quantity: 2 }],
      requestedPickupAt: hoursFromNow(4),
      idempotencyKey: nextKey(),
    };
    const first = await service.createOrder(command);
    await db.orm.public.Store.where({ id: store.storeId }).update({
      isOpen: false,
    });

    const retry = await service.createOrder(command);

    expect(retry.created).toBe(false);
    expect(retry.order.id).toBe(first.order.id);
  });

  it('creates exactly one order for simultaneous retries', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const customer = await newCustomer();
    const command = {
      customerId: customer.id,
      storeId: store.storeId,
      lines: [{ storeProductId: lait, quantity: 3 }],
      requestedPickupAt: hoursFromNow(4),
      idempotencyKey: nextKey(),
    };

    await warmPool();
    const results = await Promise.all(
      Array.from({ length: 6 }, () => service.createOrder(command)),
    );

    expect(results.filter((r) => r.created)).toHaveLength(1);
    expect(new Set(results.map((r) => r.order.id)).size).toBe(1);
    expect(await ordersOf(customer.id)).toHaveLength(1);
    expect(await stockOf(lait)).toBe(7); // taken once, not six times
    expect(await eventsOf(results[0]!.order.id)).toHaveLength(1);
  });

  it('rejects the same key for a different request (409 IDEMPOTENCY_KEY_REUSED)', async () => {
    const store = await openStore();
    const other = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 10,
    });
    const otherLait = await other.offer('lait-delice-1l');
    const yaourt = await store.offer('yaourt');
    const customer = await newCustomer();
    const pickup = hoursFromNow(4);
    const key = nextKey();
    const base = {
      customerId: customer.id,
      storeId: store.storeId,
      lines: [{ storeProductId: lait, quantity: 2 }],
      requestedPickupAt: pickup,
      idempotencyKey: key,
    };
    await service.createOrder(base);

    const variants: Partial<CreateOrderCommand>[] = [
      { lines: [{ storeProductId: lait, quantity: 3 }] }, // another quantity
      {
        lines: [
          { storeProductId: lait, quantity: 2 },
          { storeProductId: yaourt, quantity: 1 },
        ],
      }, // another line
      { requestedPickupAt: hoursFromNow(6) }, // another pickup time
      {
        storeId: other.storeId,
        lines: [{ storeProductId: otherLait, quantity: 2 }],
      }, // another store
    ];
    for (const variant of variants) {
      const { status, body } = await failure(
        service.createOrder({ ...base, ...variant }),
      );
      expect(status).toBe(409);
      expect(body['code']).toBe(OrderErrorCode.IDEMPOTENCY_KEY_REUSED);
    }
    expect(await ordersOf(customer.id)).toHaveLength(1);
    expect(await stockOf(lait)).toBe(8);
  });

  it('treats the same lines in a different order as the same request', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const yaourt = await store.offer('yaourt');
    const customer = await newCustomer();
    const base = {
      customerId: customer.id,
      storeId: store.storeId,
      requestedPickupAt: hoursFromNow(4),
      idempotencyKey: nextKey(),
    };
    const lines = [
      { storeProductId: lait, quantity: 2 },
      { storeProductId: yaourt, quantity: 1 },
    ];
    const first = await service.createOrder({ ...base, lines });
    const retry = await service.createOrder({
      ...base,
      lines: [...lines].reverse(),
    });
    expect(retry.created).toBe(false);
    expect(retry.order.id).toBe(first.order.id);
  });

  it('scopes keys to the customer: two customers may use the same key', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const [a, b] = [await newCustomer(), await newCustomer()];
    const key = nextKey();

    const first = await place(
      a.id,
      store.storeId,
      [{ storeProductId: lait, quantity: 1 }],
      { idempotencyKey: key },
    );
    const second = await place(
      b.id,
      store.storeId,
      [{ storeProductId: lait, quantity: 1 }],
      { idempotencyKey: key },
    );

    expect(first.created).toBe(true);
    expect(second.created).toBe(true);
    expect(first.order.id).not.toBe(second.order.id);
  });
});

// ── Snapshots and history ─────────────────────────────────────────────────

describe('history', () => {
  it('keeps the price the order was placed at', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', { priceMillimes: 4500 });
    const customer = await newCustomer();
    const pickup = hoursFromNow(4);
    const key = nextKey();
    const command = {
      customerId: customer.id,
      storeId: store.storeId,
      lines: [{ storeProductId: lait, quantity: 2 }],
      requestedPickupAt: pickup,
      idempotencyKey: key,
    };
    const { order } = await service.createOrder(command);
    expect(order.totalMillimes).toBe(9000);

    await request(http())
      .patch(`/owner/store-products/${lait}`)
      .set(auth(store.owner))
      .send({ priceMillimes: 5000 })
      .expect(200);

    const stored = await itemsOf(order.id);
    expect(stored[0]).toMatchObject({
      unitPriceMillimes: 4500,
      lineTotalMillimes: 9000,
    });
    expect((await ordersOf(customer.id))[0]!.totalMillimes).toBe(9000);
    // A retry still returns the original price; a new order gets the new one.
    expect((await service.createOrder(command)).order.totalMillimes).toBe(9000);
    const next = await place(customer.id, store.storeId, [
      { storeProductId: lait, quantity: 2 },
    ]);
    expect(next.order.totalMillimes).toBe(10_000);
  });

  it('keeps the product name and unit the order was placed with', async () => {
    const store = await openStore();
    const yaourt = await store.offer('yaourt');
    const customer = await newCustomer();
    const { order } = await place(customer.id, store.storeId, [
      { storeProductId: yaourt, quantity: 2 },
    ]);
    const originalName = order.items[0]!.productNameSnapshot;
    expect(originalName).toBe(`Yaourt nature ${tag}`);

    const productId = catalog.productId('yaourt');
    await db.orm.public.Product.where({ id: productId }).update({
      name: `Yaourt renommé ${tag}`,
    });
    try {
      expect((await itemsOf(order.id))[0]!.productNameSnapshot).toBe(
        originalName,
      );
      const next = await place(customer.id, store.storeId, [
        { storeProductId: yaourt, quantity: 1 },
      ]);
      expect(next.order.items[0]!.productNameSnapshot).toBe(
        `Yaourt renommé ${tag}`,
      );
    } finally {
      await db.orm.public.Product.where({ id: productId }).update({
        name: `Yaourt nature ${tag}`,
      });
    }
  });

  it('records the creation event: no previous status, PENDING, by the client', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    const customer = await newCustomer();

    const { order } = await place(customer.id, store.storeId, [
      { storeProductId: lait, quantity: 1 },
    ]);

    const events = await eventsOf(order.id);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({
      orderId: order.id,
      fromStatus: null,
      toStatus: 'PENDING',
      actorType: 'CLIENT',
      actorId: customer.id,
      reason: null,
    });
  });
});
