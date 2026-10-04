import {
  OrderTransitionsService,
  type OrderTransitionResult,
} from '../src/orders/order-transitions.service.js';
import { canTransition } from '../src/orders/order-rules.js';
import { OrderStatus } from '../src/orders/order-status.enum.js';
import type { OrderRecord } from '../src/orders/order.types.js';
import { OrdersService } from '../src/orders/orders.service.js';
import { db } from '../src/prisma/db.js';
import {
  archiveCategory,
  archiveProduct,
  removeCatalog,
  seedCatalog,
} from './catalog-helpers.js';
import {
  archiveStoreProduct,
  eventsOf,
  failure,
  hoursFromNow,
  itemsOf,
  openStore as openStoreFor,
  orderRow,
  patchStoreProduct,
  setAvailability,
  stockOf,
  warmPool,
  type TestStore,
} from './order-test-helpers.js';
import { register, startApp, stopApp, type Account } from './support.js';

/**
 * The order transition service against the real test database. Orders are
 * placed with the creation service; owners and customers then act on them
 * through `OrderTransitionsService`, which has no HTTP of its own.
 *
 * Every scenario starts from the same shape: a store whose `lait` and `yaourt`
 * both track a stock of 10, and a customer order of 4 lait + 2 yaourt, so after
 * placing it the stock is 6 and 8.
 */

const tag = `e2etr${Date.now()}`;
const creation = new OrdersService();
const transitions = new OrderTransitionsService();
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

// ── Scenario helpers ──────────────────────────────────────────────────────

interface Scenario {
  store: TestStore;
  owner: Account;
  customer: Account;
  lait: number;
  yaourt: number;
  /** Places a customer order; by default 4 lait + 2 yaourt. */
  place: (
    lines?: { storeProductId: number; quantity: number }[],
  ) => Promise<OrderRecord>;
}

async function scenario(
  options: { laitStock?: number | null; yaourtStock?: number | null } = {},
): Promise<Scenario> {
  const store = await openStoreFor((slug) => catalog.productId(slug));
  const stockFor = (stock: number | null | undefined) =>
    stock === null ? {} : { trackStock: true, stockQuantity: stock ?? 10 };
  const lait = await store.offer('lait-delice-1l', stockFor(options.laitStock));
  const yaourt = await store.offer('yaourt', stockFor(options.yaourtStock));
  const customer = await register('CLIENT');
  const place = async (
    lines = [
      { storeProductId: lait, quantity: 4 },
      { storeProductId: yaourt, quantity: 2 },
    ],
  ) =>
    (
      await creation.createOrder({
        customerId: customer.id,
        storeId: store.storeId,
        lines,
        requestedPickupAt: hoursFromNow(4),
        idempotencyKey: `key-${tag}-${(keyCounter += 1)}`,
      })
    ).order;
  return { store, owner: store.owner, customer, lait, yaourt, place };
}

/** Walks an order to `status` through the real transitions, as its owner. */
async function advance(s: Scenario, order: OrderRecord, status: OrderStatus) {
  const steps: Record<string, () => Promise<unknown>> = {
    CONFIRMED: () => transitions.confirm(order.id, s.owner.id),
    READY_FOR_PICKUP: async () => {
      await transitions.confirm(order.id, s.owner.id);
      await transitions.markReady(order.id, s.owner.id);
    },
  };
  if (status !== OrderStatus.PENDING) await steps[status]!();
}

/** The status changes recorded after the creation event. */
async function transitionEvents(orderId: number) {
  const events = (await eventsOf(orderId)).sort((a, b) => a.id - b.id);
  return events.slice(1).map((e) => ({
    from: e.fromStatus,
    to: e.toStatus,
    actorType: e.actorType,
    actorId: e.actorId,
    reason: e.reason,
  }));
}

/** The events form one valid chain from creation to the order's current status. */
async function expectValidHistory(orderId: number) {
  const events = (await eventsOf(orderId)).sort((a, b) => a.id - b.id);
  expect(events[0]).toMatchObject({ fromStatus: null, toStatus: 'PENDING' });
  for (let i = 1; i < events.length; i += 1) {
    expect(events[i]!.fromStatus).toBe(events[i - 1]!.toStatus);
    expect(
      canTransition(
        events[i]!.fromStatus as OrderStatus,
        events[i]!.toStatus as OrderStatus,
      ),
    ).toBe(true);
  }
  expect((await orderRow(orderId))!.status).toBe(events.at(-1)!.toStatus);
}

/**
 * The invariant behind exactly-once restoration. A product's stock must equal
 * what it started with minus what the order lines that are still outstanding
 * (not removed, order not cancelled or no-show) took. A double restore makes
 * the stock too high; a missed one makes it too low.
 */
async function expectStockConsistent(initial: Record<number, number>) {
  for (const [id, start] of Object.entries(initial)) {
    const storeProductId = Number(id);
    let outstanding = 0;
    for (const item of await db.orm.public.OrderItem.where({
      storeProductId,
    }).all()) {
      const order = (await orderRow(item.orderId))!;
      const gaveBack =
        order.status === 'CANCELLED' || order.status === 'NO_SHOW';
      if (item.removedAt === null && !gaveBack) {
        outstanding += item.stockDecrementedQuantity;
      }
    }
    expect(await stockOf(storeProductId)).toBe(start - outstanding);
  }
}

const codeOf = (result: PromiseSettledResult<unknown>): string => {
  if (result.status === 'fulfilled') return 'fulfilled';
  const reason = result.reason as {
    getResponse?: () => { code?: string };
    message?: string;
  };
  // A non-HTTP error (a database error, say) is reported by message, so a
  // failing assertion shows what actually went wrong.
  return reason.getResponse
    ? (reason.getResponse().code ?? 'no-code')
    : `unexpected: ${reason.message}`;
};

const historicalDecrements = async (orderId: number) =>
  (await itemsOf(orderId))
    .sort((a, b) => a.id - b.id)
    .map((item) => item.stockDecrementedQuantity);

// ── Lifecycle ─────────────────────────────────────────────────────────────

describe('lifecycle', () => {
  it('lets the customer cancel a PENDING order', async () => {
    const s = await scenario();
    const order = await s.place();

    const result = await transitions.cancelByCustomer(
      order.id,
      s.customer.id,
      'Changed my mind',
    );

    expect(result.changed).toBe(true);
    expect(result.order.status).toBe('CANCELLED');
    expect(await transitionEvents(order.id)).toEqual([
      {
        from: 'PENDING',
        to: 'CANCELLED',
        actorType: 'CLIENT',
        actorId: s.customer.id,
        reason: 'Changed my mind',
      },
    ]);
  });

  it('lets the customer cancel a CONFIRMED order, with no reason', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.CONFIRMED);

    const result = await transitions.cancelByCustomer(order.id, s.customer.id);

    expect(result.order.status).toBe('CANCELLED');
    expect((await transitionEvents(order.id)).at(-1)).toEqual({
      from: 'CONFIRMED',
      to: 'CANCELLED',
      actorType: 'CLIENT',
      actorId: s.customer.id,
      reason: null,
    });
  });

  it('lets the owner confirm a PENDING order', async () => {
    const s = await scenario();
    const order = await s.place();

    const result = await transitions.confirm(order.id, s.owner.id);

    expect(result.changed).toBe(true);
    expect(result.order.status).toBe('CONFIRMED');
    expect(await transitionEvents(order.id)).toEqual([
      {
        from: 'PENDING',
        to: 'CONFIRMED',
        actorType: 'OWNER',
        actorId: s.owner.id,
        reason: null,
      },
    ]);
  });

  it('lets the owner make a CONFIRMED order READY_FOR_PICKUP', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.CONFIRMED);

    const result = await transitions.markReady(order.id, s.owner.id);

    expect(result.order.status).toBe('READY_FOR_PICKUP');
    expect((await transitionEvents(order.id)).at(-1)).toMatchObject({
      from: 'CONFIRMED',
      to: 'READY_FOR_PICKUP',
      actorType: 'OWNER',
    });
  });

  it('lets the owner complete a READY_FOR_PICKUP order', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);

    const result = await transitions.complete(order.id, s.owner.id);

    expect(result.order.status).toBe('COMPLETED');
    expect((await transitionEvents(order.id)).at(-1)).toMatchObject({
      from: 'READY_FOR_PICKUP',
      to: 'COMPLETED',
      actorType: 'OWNER',
      actorId: s.owner.id,
    });
    await expectValidHistory(order.id);
  });

  it('lets the owner cancel a PENDING order, with a reason', async () => {
    const s = await scenario();
    const order = await s.place();

    const result = await transitions.cancelByOwner(
      order.id,
      s.owner.id,
      '  Out of fresh milk  ',
    );

    expect(result.order.status).toBe('CANCELLED');
    expect(await transitionEvents(order.id)).toEqual([
      {
        from: 'PENDING',
        to: 'CANCELLED',
        actorType: 'OWNER',
        actorId: s.owner.id,
        reason: 'Out of fresh milk',
      },
    ]);
  });

  it('lets the owner cancel a CONFIRMED order', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.CONFIRMED);

    const result = await transitions.cancelByOwner(
      order.id,
      s.owner.id,
      'Shop closing early',
    );

    expect(result.order.status).toBe('CANCELLED');
    expect((await transitionEvents(order.id)).at(-1)).toMatchObject({
      from: 'CONFIRMED',
      to: 'CANCELLED',
      actorType: 'OWNER',
      reason: 'Shop closing early',
    });
  });

  it('lets the owner mark a READY_FOR_PICKUP order NO_SHOW', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);

    const result = await transitions.markNoShow(order.id, s.owner.id);

    expect(result.order.status).toBe('NO_SHOW');
    expect((await transitionEvents(order.id)).at(-1)).toMatchObject({
      from: 'READY_FOR_PICKUP',
      to: 'NO_SHOW',
      actorType: 'OWNER',
    });
    await expectValidHistory(order.id);
  });

  it('walks the whole happy path with one event per step', async () => {
    const s = await scenario();
    const order = await s.place();

    await transitions.confirm(order.id, s.owner.id);
    await transitions.markReady(order.id, s.owner.id);
    await transitions.complete(order.id, s.owner.id);

    expect((await transitionEvents(order.id)).map((e) => e.to)).toEqual([
      'CONFIRMED',
      'READY_FOR_PICKUP',
      'COMPLETED',
    ]);
    await expectValidHistory(order.id);
  });
});

describe('moves the lifecycle does not allow', () => {
  it('cannot cancel a READY_FOR_PICKUP order, as customer or owner', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);

    for (const attempt of [
      () => transitions.cancelByCustomer(order.id, s.customer.id),
      () => transitions.cancelByOwner(order.id, s.owner.id, 'too late'),
    ]) {
      const { status, body } = await failure(attempt());
      expect(status).toBe(409);
      expect(body).toMatchObject({
        code: 'ORDER_STATE_CHANGED',
        currentStatus: 'READY_FOR_PICKUP',
        requestedStatus: 'CANCELLED',
      });
    }
    expect((await orderRow(order.id))!.status).toBe('READY_FOR_PICKUP');
    expect(await transitionEvents(order.id)).toHaveLength(2); // confirm, ready
  });

  it('skips nothing: ready or complete a PENDING order is refused', async () => {
    const s = await scenario();
    const order = await s.place();

    for (const attempt of [
      () => transitions.markReady(order.id, s.owner.id),
      () => transitions.complete(order.id, s.owner.id),
      () => transitions.markNoShow(order.id, s.owner.id),
    ]) {
      expect((await failure(attempt())).body['code']).toBe(
        'ORDER_STATE_CHANGED',
      );
    }
    expect((await orderRow(order.id))!.status).toBe('PENDING');
    expect(await transitionEvents(order.id)).toEqual([]);
  });

  describe.each([
    ['COMPLETED', OrderStatus.READY_FOR_PICKUP],
    ['NO_SHOW', OrderStatus.READY_FOR_PICKUP],
    ['CANCELLED', OrderStatus.PENDING],
  ])('a %s order', (terminal, startFrom) => {
    const finish = async (s: Scenario, order: OrderRecord) => {
      await advance(s, order, startFrom);
      if (terminal === 'COMPLETED')
        await transitions.complete(order.id, s.owner.id);
      else if (terminal === 'NO_SHOW')
        await transitions.markNoShow(order.id, s.owner.id);
      else await transitions.cancelByOwner(order.id, s.owner.id, 'done');
    };

    it('accepts no other change, and changes nothing', async () => {
      const s = await scenario();
      const order = await s.place();
      await finish(s, order);
      const stockAfter = await stockOf(s.lait);
      const eventsBefore = (await eventsOf(order.id)).length;

      // Every move except staying where it is must be refused.
      const others = {
        CONFIRMED: () => transitions.confirm(order.id, s.owner.id),
        READY_FOR_PICKUP: () => transitions.markReady(order.id, s.owner.id),
        COMPLETED: () => transitions.complete(order.id, s.owner.id),
        NO_SHOW: () => transitions.markNoShow(order.id, s.owner.id),
        CANCELLED: () =>
          transitions.cancelByOwner(order.id, s.owner.id, 'again'),
      };
      for (const [target, attempt] of Object.entries(others)) {
        if (target === terminal) continue;
        const { status, body } = await failure(attempt());
        expect(status).toBe(409);
        expect(body['code']).toBe('ORDER_STATE_CHANGED');
      }
      // Staying where it is is an idempotent success with no side effect.
      const same = await others[terminal as keyof typeof others]();
      expect(same.changed).toBe(false);
      expect(same.order.status).toBe(terminal);

      expect((await orderRow(order.id))!.status).toBe(terminal);
      expect((await eventsOf(order.id)).length).toBe(eventsBefore);
      expect(await stockOf(s.lait)).toBe(stockAfter);
    });
  });

  it('answers a request for the status the order already has with the current order', async () => {
    const s = await scenario();
    const order = await s.place();
    await transitions.confirm(order.id, s.owner.id);

    const again = await transitions.confirm(order.id, s.owner.id);

    expect(again.changed).toBe(false);
    expect(again.order.status).toBe('CONFIRMED');
    expect(await transitionEvents(order.id)).toHaveLength(1);
  });

  it('is idempotent for complete and for no-show', async () => {
    const s = await scenario();
    const done = await s.place();
    const missed = await s.place();
    await advance(s, done, OrderStatus.READY_FOR_PICKUP);
    await advance(s, missed, OrderStatus.READY_FOR_PICKUP);
    await transitions.complete(done.id, s.owner.id);
    await transitions.markNoShow(missed.id, s.owner.id);

    expect((await transitions.complete(done.id, s.owner.id)).changed).toBe(
      false,
    );
    expect((await transitions.markNoShow(missed.id, s.owner.id)).changed).toBe(
      false,
    );
    expect(await transitionEvents(done.id)).toHaveLength(3);
    expect(await transitionEvents(missed.id)).toHaveLength(3);
  });
});

describe('who may act', () => {
  it("hides another customer's order (404), changing nothing", async () => {
    const s = await scenario();
    const order = await s.place();
    const stranger = await register('CLIENT');

    const { status } = await failure(
      transitions.cancelByCustomer(order.id, stranger.id),
    );

    expect(status).toBe(404);
    expect((await orderRow(order.id))!.status).toBe('PENDING');
    expect(await stockOf(s.lait)).toBe(6);
  });

  it("hides another store's order from an owner (404)", async () => {
    const s = await scenario();
    const other = await scenario();
    const order = await s.place();

    for (const attempt of [
      () => transitions.confirm(order.id, other.owner.id),
      () => transitions.cancelByOwner(order.id, other.owner.id, 'x'),
    ]) {
      expect((await failure(attempt())).status).toBe(404);
    }
    // Neither a customer's id nor the customer standing in as owner works.
    expect(
      (await failure(transitions.confirm(order.id, s.customer.id))).status,
    ).toBe(404);
    expect((await orderRow(order.id))!.status).toBe('PENDING');
  });

  it('reports an unknown order as 404', async () => {
    const s = await scenario();
    expect(
      (await failure(transitions.confirm(2_000_000_000, s.owner.id))).status,
    ).toBe(404);
  });

  it('requires a reason when the owner cancels, and bounds its length', async () => {
    const s = await scenario();
    const order = await s.place();

    for (const reason of ['', '   ', 'x'.repeat(501)]) {
      expect(
        (await failure(transitions.cancelByOwner(order.id, s.owner.id, reason)))
          .status,
      ).toBe(400);
    }
    expect((await orderRow(order.id))!.status).toBe('PENDING');
    expect(await stockOf(s.lait)).toBe(6);
  });

  it('treats a blank customer reason as no reason', async () => {
    const s = await scenario();
    const order = await s.place();
    await transitions.cancelByCustomer(order.id, s.customer.id, '   ');
    expect((await transitionEvents(order.id))[0]!.reason).toBeNull();
  });
});

// ── Confirmation adjustment ───────────────────────────────────────────────

describe('removing lines at confirmation', () => {
  it('removes a line: marked, out of the total, stock given back, others untouched', async () => {
    const s = await scenario();
    // lait 4 × 4500 = 18000; yaourt 2 × 4500 = 9000.
    const order = await s.place();
    expect(order.totalMillimes).toBe(27_000);
    const [laitItem, yaourtItem] = order.items;
    expect(await stockOf(s.lait)).toBe(6);

    const result = await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [laitItem!.id],
    });

    expect(result.changed).toBe(true);
    expect(result.order.status).toBe('CONFIRMED');
    const [removed, kept] = result.order.items;
    expect(removed!.id).toBe(laitItem!.id);
    expect(removed!.removedAt).not.toBeNull(); // kept in the order, marked
    expect(kept!.id).toBe(yaourtItem!.id);
    expect(kept!.removedAt).toBeNull(); // still active
    expect(result.order.items).toHaveLength(2); // never physically deleted
    // The total comes from the remaining line only.
    expect(result.order.totalMillimes).toBe(9_000);
    expect((await orderRow(order.id))!.totalMillimes).toBe(9_000);
    // The removed line's stock is back (6 + 4); the kept line still holds its 2.
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(8);
    // One transition, one event.
    expect(await transitionEvents(order.id)).toHaveLength(1);
    await expectStockConsistent({ [s.lait]: 10, [s.yaourt]: 10 });
  });

  it('gives back the historical quantity, not a recomputed one', async () => {
    const s = await scenario();
    const order = await s.place();
    const laitItem = order.items[0]!;
    // Change everything the quantity could be recomputed from.
    await patchStoreProduct(s.store, s.lait, {
      minQuantity: 2,
      quantityStep: 2,
      priceMillimes: 99_000,
    });
    await patchStoreProduct(s.store, s.lait, {
      stockQuantity: 50,
      expectedStockQuantity: 6,
    });

    await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [laitItem.id],
    });

    expect(await stockOf(s.lait)).toBe(54); // 50 + the 4 this order took
  });

  it('can remove several lines, and recomputes from what is left', async () => {
    const s = await scenario();
    const third = await s.store.offer('banane', {
      trackStock: true,
      stockQuantity: 5000,
      priceMillimes: 1800,
    });
    const order = await s.place([
      { storeProductId: s.lait, quantity: 1 },
      { storeProductId: s.yaourt, quantity: 1 },
      { storeProductId: third, quantity: 1000 },
    ]);
    // 4500 + 4500 + 1800 = 10800.
    expect(order.totalMillimes).toBe(10_800);

    const result = await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [order.items[0]!.id, order.items[2]!.id],
    });

    expect(result.order.totalMillimes).toBe(4_500);
    expect(result.order.items.map((i) => i.removedAt !== null)).toEqual([
      true,
      false,
      true,
    ]);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(third)).toBe(5000);
    expect(await stockOf(s.yaourt)).toBe(9);
  });

  it('confirms without removals and still rebuilds the total from the lines', async () => {
    const s = await scenario();
    const order = await s.place();
    // Corrupt the stored total: confirmation must not trust it.
    await db.orm.public.Order.where({ id: order.id }).update({
      totalMillimes: 1,
    });

    const result = await transitions.confirm(order.id, s.owner.id);

    expect(result.order.totalMillimes).toBe(27_000);
  });

  it('refuses to remove every line, changing nothing', async () => {
    const s = await scenario();
    const order = await s.place();

    const { status } = await failure(
      transitions.confirm(order.id, s.owner.id, {
        removeItemIds: order.items.map((i) => i.id),
      }),
    );

    expect(status).toBe(400);
    const after = (await orderRow(order.id))!;
    expect(after.status).toBe('PENDING');
    expect(after.totalMillimes).toBe(27_000);
    expect((await itemsOf(order.id)).every((i) => i.removedAt === null)).toBe(
      true,
    );
    expect(await stockOf(s.lait)).toBe(6); // nothing given back
    expect(await stockOf(s.yaourt)).toBe(8);
    expect(await transitionEvents(order.id)).toEqual([]);

    // The owner can still cancel it instead.
    const cancelled = await transitions.cancelByOwner(
      order.id,
      s.owner.id,
      'Nothing available',
    );
    expect(cancelled.order.status).toBe('CANCELLED');
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(10);
  });

  it('refuses a removal that is already done, and gives nothing back twice', async () => {
    const s = await scenario();
    const order = await s.place();
    const laitItem = order.items[0]!;
    // The line is marked removed behind the service's back, as if an earlier
    // adjustment had already taken it out and restored its stock.
    await db.orm.public.OrderItem.where({ id: laitItem.id }).update({
      removedAt: new Date().toISOString(),
    });
    const stockBefore = await stockOf(s.lait);

    const { status, body } = await failure(
      transitions.confirm(order.id, s.owner.id, {
        removeItemIds: [laitItem.id],
      }),
    );

    expect(status).toBe(400);
    expect(body['itemIds']).toEqual([laitItem.id]);
    expect(await stockOf(s.lait)).toBe(stockBefore);
    expect((await orderRow(order.id))!.status).toBe('PENDING');
  });

  it('refuses lines that are not part of the order', async () => {
    const s = await scenario();
    const order = await s.place();
    const other = await s.place();

    const { status, body } = await failure(
      transitions.confirm(order.id, s.owner.id, {
        removeItemIds: [other.items[0]!.id, 2_000_000_000],
      }),
    );

    expect(status).toBe(400);
    expect(body['itemIds']).toEqual([other.items[0]!.id, 2_000_000_000]);
    expect((await orderRow(order.id))!.status).toBe('PENDING');
    expect((await itemsOf(other.id)).every((i) => i.removedAt === null)).toBe(
      true,
    );
  });

  it('removes a repeated id once', async () => {
    const s = await scenario();
    const order = await s.place();
    const laitItem = order.items[0]!;

    await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [laitItem.id, laitItem.id, laitItem.id],
    });

    expect(await stockOf(s.lait)).toBe(10); // given back once, not three times
  });

  it('removes nothing once the order is no longer PENDING', async () => {
    const s = await scenario();
    const order = await s.place();
    await transitions.confirm(order.id, s.owner.id);

    const again = await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [order.items[0]!.id],
    });

    expect(again.changed).toBe(false);
    expect(again.order.items.every((i) => i.removedAt === null)).toBe(true);
    expect(await stockOf(s.lait)).toBe(6);
  });
});

// ── Stock restoration ─────────────────────────────────────────────────────

describe('stock restoration', () => {
  it('a cancellation gives tracked stock back, exactly once', async () => {
    const s = await scenario();
    const order = await s.place();
    expect(await stockOf(s.lait)).toBe(6);
    expect(await stockOf(s.yaourt)).toBe(8);

    await transitions.cancelByCustomer(order.id, s.customer.id);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(10);

    // Asking again, as either party, changes nothing.
    await transitions.cancelByCustomer(order.id, s.customer.id);
    await transitions.cancelByOwner(order.id, s.owner.id, 'again');
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(10);
    expect(await transitionEvents(order.id)).toHaveLength(1);
  });

  it('a NO_SHOW gives tracked stock back, exactly once', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);
    expect(await stockOf(s.lait)).toBe(6);

    await transitions.markNoShow(order.id, s.owner.id);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(10);

    await transitions.markNoShow(order.id, s.owner.id);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await transitionEvents(order.id)).toHaveLength(3);
  });

  it('an untracked line gives back nothing', async () => {
    const s = await scenario({ laitStock: null });
    const order = await s.place();
    expect(order.items[0]!.stockDecrementedQuantity).toBe(0);
    expect(await stockOf(s.lait)).toBeNull();

    await transitions.cancelByCustomer(order.id, s.customer.id);

    expect(await stockOf(s.lait)).toBeNull(); // still untracked, untouched
    expect(await stockOf(s.yaourt)).toBe(10); // the tracked line did come back
  });

  it('a line whose historical quantity is 0 gives back nothing', async () => {
    const s = await scenario();
    const order = await s.place();
    // Pretend this line never took stock (it was untracked when ordered).
    await db.orm.public.OrderItem.where({ id: order.items[0]!.id }).update({
      stockDecrementedQuantity: 0,
    });

    await transitions.cancelByOwner(order.id, s.owner.id, 'x');

    expect(await stockOf(s.lait)).toBe(6); // not given back
    expect(await stockOf(s.yaourt)).toBe(10);
  });

  it('COMPLETED gives nothing back, now or after any later change', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);
    await transitions.complete(order.id, s.owner.id);
    expect(await stockOf(s.lait)).toBe(6);
    expect(await stockOf(s.yaourt)).toBe(8);

    // Later attempts to cancel or no-show are refused and restore nothing.
    await failure(transitions.cancelByOwner(order.id, s.owner.id, 'late'));
    await failure(transitions.markNoShow(order.id, s.owner.id));

    expect(await stockOf(s.lait)).toBe(6);
    expect(await stockOf(s.yaourt)).toBe(8);
  });

  it('a cancellation after a removal gives back only the lines still active', async () => {
    const s = await scenario();
    const order = await s.place();
    const [laitItem] = order.items;
    await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [laitItem!.id],
    });
    expect(await stockOf(s.lait)).toBe(10); // given back at removal
    expect(await stockOf(s.yaourt)).toBe(8);

    await transitions.cancelByCustomer(order.id, s.customer.id);

    expect(await stockOf(s.lait)).toBe(10); // NOT 14: the removed line is not given back again
    expect(await stockOf(s.yaourt)).toBe(10);
    await expectStockConsistent({ [s.lait]: 10, [s.yaourt]: 10 });
  });

  it('a no-show after a removal gives back only the lines still active', async () => {
    const s = await scenario();
    const order = await s.place();
    await transitions.confirm(order.id, s.owner.id, {
      removeItemIds: [order.items[1]!.id], // yaourt
    });
    await transitions.markReady(order.id, s.owner.id);

    await transitions.markNoShow(order.id, s.owner.id);

    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(10); // 8 + 2 once, at the removal
  });

  it('never alters the historical record', async () => {
    const s = await scenario({ laitStock: 30, yaourtStock: 30 });
    const cancelled = await s.place();
    const noShow = await s.place();
    const adjusted = await s.place();
    const before = await Promise.all(
      [cancelled, noShow, adjusted].map((o) => historicalDecrements(o.id)),
    );
    expect(before).toEqual([
      [4, 2],
      [4, 2],
      [4, 2],
    ]);

    await transitions.cancelByCustomer(cancelled.id, s.customer.id);
    await advance(s, noShow, OrderStatus.READY_FOR_PICKUP);
    await transitions.markNoShow(noShow.id, s.owner.id);
    await transitions.confirm(adjusted.id, s.owner.id, {
      removeItemIds: [adjusted.items[0]!.id],
    });
    await transitions.cancelByOwner(adjusted.id, s.owner.id, 'x');

    const after = await Promise.all(
      [cancelled, noShow, adjusted].map((o) => historicalDecrements(o.id)),
    );
    expect(after).toEqual(before); // still 4 and 2: never zeroed, never rewritten
  });
});

// ── Catalog changes after the order ───────────────────────────────────────

/**
 * Changes made to the store product (or the catalog) after the order exists.
 * None of them may stop the order from moving on, and giving stock back must
 * still use only the historical quantity: the order took 4 lait (10 → 6).
 */
interface CatalogChange {
  name: string;
  setup?: { laitStock?: number | null };
  apply: (s: Scenario) => Promise<(() => Promise<void>) | void>;
  /** lait stock after the change alone. */
  afterChange: number | null;
  /** lait stock after the change and then a cancellation or no-show. */
  afterRestore: number | null;
}

const changes: CatalogChange[] = [
  {
    name: 'tracked → untracked',
    apply: async (s) => {
      await patchStoreProduct(s.store, s.lait, {
        trackStock: false,
        expectedStockQuantity: 6,
      });
    },
    afterChange: null,
    afterRestore: null, // no counter left to credit; the transition still works
  },
  {
    name: 'untracked → tracked',
    setup: { laitStock: null },
    apply: async (s) => {
      await patchStoreProduct(s.store, s.lait, {
        trackStock: true,
        stockQuantity: 5,
        expectedStockQuantity: null,
      });
    },
    afterChange: 5,
    afterRestore: 5, // the order took nothing, so nothing comes back
  },
  {
    name: 'stock quantity changed',
    apply: async (s) => {
      await patchStoreProduct(s.store, s.lait, {
        stockQuantity: 100,
        expectedStockQuantity: 6,
      });
    },
    afterChange: 100,
    afterRestore: 104,
  },
  {
    name: 'store product made unavailable',
    apply: async (s) => {
      await setAvailability(s.store, s.lait, false);
    },
    afterChange: 6,
    afterRestore: 10,
  },
  {
    name: 'store product archived',
    apply: async (s) => {
      await archiveStoreProduct(s.store, s.lait);
    },
    afterChange: 6,
    afterRestore: 10,
  },
  {
    name: 'catalog product archived',
    apply: async () => {
      const id = catalog.productId('lait-delice-1l');
      await archiveProduct(id);
      return async () => {
        await db.orm.public.Product.where({ id }).update({ archivedAt: null });
      };
    },
    afterChange: 6,
    afterRestore: 10,
  },
  {
    name: 'catalog category archived',
    apply: async () => {
      const id = catalog.categoryId('laitiers');
      await archiveCategory(id);
      return async () => {
        await db.orm.public.Category.where({ id }).update({ archivedAt: null });
      };
    },
    afterChange: 6,
    afterRestore: 10,
  },
  {
    name: 'quantity rules changed',
    apply: async (s) => {
      await patchStoreProduct(s.store, s.lait, {
        minQuantity: 2,
        quantityStep: 2,
        maxQuantity: 20,
      });
    },
    afterChange: 6,
    afterRestore: 10,
  },
  {
    name: 'price changed',
    apply: async (s) => {
      await patchStoreProduct(s.store, s.lait, { priceMillimes: 12_345 });
    },
    afterChange: 6,
    afterRestore: 10,
  },
];

describe('catalog changes after the order was placed', () => {
  describe.each(changes)('$name', (change) => {
    const run = async (
      finish: (
        s: Scenario,
        order: OrderRecord,
      ) => Promise<OrderTransitionResult>,
      readyFirst: boolean,
    ) => {
      const s = await scenario(change.setup);
      const order = await s.place();
      expect(order.items[0]!.stockDecrementedQuantity).toBe(
        change.setup?.laitStock === null ? 0 : 4,
      );
      if (readyFirst) await advance(s, order, OrderStatus.READY_FOR_PICKUP);
      const cleanup = await change.apply(s);
      try {
        expect(await stockOf(s.lait)).toBe(change.afterChange);
        const result = await finish(s, order);
        return { s, order, result };
      } finally {
        await cleanup?.();
      }
    };

    it('a customer can still cancel, and the historical stock comes back', async () => {
      const { s, order, result } = await run(
        (s, o) => transitions.cancelByCustomer(o.id, s.customer.id),
        false,
      );
      expect(result.order.status).toBe('CANCELLED');
      expect(await stockOf(s.lait)).toBe(change.afterRestore);
      expect(await stockOf(s.yaourt)).toBe(10); // untouched by the change
      expect((await historicalDecrements(order.id))[0]).toBe(
        change.setup?.laitStock === null ? 0 : 4,
      );
    });

    it('the owner can still confirm and cancel', async () => {
      const s = await scenario(change.setup);
      const order = await s.place();
      const cleanup = await change.apply(s);
      try {
        expect(
          (await transitions.confirm(order.id, s.owner.id)).order.status,
        ).toBe('CONFIRMED');
        const cancelled = await transitions.cancelByOwner(
          order.id,
          s.owner.id,
          'x',
        );
        expect(cancelled.order.status).toBe('CANCELLED');
        expect(await stockOf(s.lait)).toBe(change.afterRestore);
      } finally {
        await cleanup?.();
      }
    });

    it('a no-show still gives the historical stock back', async () => {
      const { s, result } = await run(
        (s, o) => transitions.markNoShow(o.id, s.owner.id),
        true,
      );
      expect(result.order.status).toBe('NO_SHOW');
      expect(await stockOf(s.lait)).toBe(change.afterRestore);
    });

    it('the order can still be completed, and completing gives nothing back', async () => {
      const { s, result } = await run(
        (s, o) => transitions.complete(o.id, s.owner.id),
        true,
      );
      expect(result.order.status).toBe('COMPLETED');
      expect(await stockOf(s.lait)).toBe(change.afterChange);
      expect(await stockOf(s.yaourt)).toBe(8);
    });

    it('a line can still be removed at confirmation, giving back its historical quantity', async () => {
      const s = await scenario(change.setup);
      const order = await s.place();
      const cleanup = await change.apply(s);
      try {
        await transitions.confirm(order.id, s.owner.id, {
          removeItemIds: [order.items[0]!.id],
        });
        expect(await stockOf(s.lait)).toBe(change.afterRestore);
      } finally {
        await cleanup?.();
      }
    });
  });
});

// ── Concurrency ───────────────────────────────────────────────────────────

describe('concurrency', () => {
  const initial = (s: Scenario) => ({ [s.lait]: 10, [s.yaourt]: 10 });

  it('two cancellations restore once and write one event', async () => {
    const s = await scenario();
    const order = await s.place();
    await warmPool();

    const results = await Promise.allSettled([
      transitions.cancelByCustomer(order.id, s.customer.id),
      transitions.cancelByOwner(order.id, s.owner.id, 'x'),
      transitions.cancelByCustomer(order.id, s.customer.id),
      transitions.cancelByOwner(order.id, s.owner.id, 'y'),
      transitions.cancelByCustomer(order.id, s.customer.id),
    ]);

    const fulfilled = results.filter(
      (r): r is PromiseFulfilledResult<OrderTransitionResult> =>
        r.status === 'fulfilled',
    );
    expect(fulfilled).toHaveLength(5); // all see CANCELLED
    expect(fulfilled.filter((r) => r.value.changed)).toHaveLength(1);
    expect(await transitionEvents(order.id)).toHaveLength(1);
    expect(await stockOf(s.lait)).toBe(10);
    expect(await stockOf(s.yaourt)).toBe(10);
    await expectValidHistory(order.id);
  });

  it('two no-shows restore once and write one event', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);
    await warmPool();

    const results = await Promise.allSettled(
      Array.from({ length: 4 }, () =>
        transitions.markNoShow(order.id, s.owner.id),
      ),
    );

    expect(results.every((r) => r.status === 'fulfilled')).toBe(true);
    expect(
      results.filter((r) => r.status === 'fulfilled' && r.value.changed),
    ).toHaveLength(1);
    expect(await transitionEvents(order.id)).toHaveLength(3);
    expect(await stockOf(s.lait)).toBe(10);
    await expectStockConsistent(initial(s));
  });

  it('two completions write one event and restore nothing', async () => {
    const s = await scenario();
    const order = await s.place();
    await advance(s, order, OrderStatus.READY_FOR_PICKUP);
    await warmPool();

    const results = await Promise.allSettled(
      Array.from({ length: 4 }, () =>
        transitions.complete(order.id, s.owner.id),
      ),
    );

    expect(
      results.filter((r) => r.status === 'fulfilled' && r.value.changed),
    ).toHaveLength(1);
    expect(await transitionEvents(order.id)).toHaveLength(3);
    expect(await stockOf(s.lait)).toBe(6);
  });

  it('two owners confirming: one transition, one event', async () => {
    const s = await scenario();
    const order = await s.place();
    await warmPool();

    const results = await Promise.allSettled(
      Array.from({ length: 5 }, () =>
        transitions.confirm(order.id, s.owner.id),
      ),
    );

    expect(results.every((r) => r.status === 'fulfilled')).toBe(true);
    expect(
      results.filter((r) => r.status === 'fulfilled' && r.value.changed),
    ).toHaveLength(1);
    expect(await transitionEvents(order.id)).toHaveLength(1);
    await expectValidHistory(order.id);
  });

  it('two owners removing the same line restore it once', async () => {
    const s = await scenario();
    const order = await s.place();
    const removeItemIds = [order.items[0]!.id];
    await warmPool();

    const results = await Promise.allSettled(
      Array.from({ length: 5 }, () =>
        transitions.confirm(order.id, s.owner.id, { removeItemIds }),
      ),
    );

    expect(results.every((r) => r.status === 'fulfilled')).toBe(true);
    expect(
      results.filter((r) => r.status === 'fulfilled' && r.value.changed),
    ).toHaveLength(1);
    expect(await stockOf(s.lait)).toBe(10); // 6 + 4 once, never 6 + 20
    expect(await stockOf(s.yaourt)).toBe(8);
    expect((await orderRow(order.id))!.totalMillimes).toBe(9_000);
    await expectStockConsistent(initial(s));
  });

  it('concurrent removals of different lines: one confirmation wins, its removals only', async () => {
    const s = await scenario();
    const order = await s.place();
    const [laitItem, yaourtItem] = order.items;
    await warmPool();

    const results = await Promise.allSettled([
      transitions.confirm(order.id, s.owner.id, {
        removeItemIds: [laitItem!.id],
      }),
      transitions.confirm(order.id, s.owner.id, {
        removeItemIds: [yaourtItem!.id],
      }),
    ]);

    expect(results.every((r) => r.status === 'fulfilled')).toBe(true);
    expect(
      results.filter((r) => r.status === 'fulfilled' && r.value.changed),
    ).toHaveLength(1);
    const items = await itemsOf(order.id);
    const removed = items.filter((i) => i.removedAt !== null);
    expect(removed).toHaveLength(1); // only the winner's removal
    // Total and stock agree with whichever line was removed.
    const keptTotal = items
      .filter((i) => i.removedAt === null)
      .reduce((sum, i) => sum + i.lineTotalMillimes, 0);
    expect((await orderRow(order.id))!.totalMillimes).toBe(keptTotal);
    await expectStockConsistent(initial(s));
  });

  it('cancel vs confirm: never both silently, history stays valid, stock exact', async () => {
    for (let round = 0; round < 6; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await warmPool();

      const results = await Promise.allSettled([
        transitions.cancelByCustomer(order.id, s.customer.id),
        transitions.confirm(order.id, s.owner.id),
      ]);

      // A loser is told the order moved; nobody gets a different error.
      for (const result of results) {
        expect(['fulfilled', 'ORDER_STATE_CHANGED']).toContain(codeOf(result));
      }
      expect(results.some((r) => r.status === 'fulfilled')).toBe(true);
      const wins = results.filter(
        (r) => r.status === 'fulfilled' && r.value.changed,
      ).length;
      expect(await transitionEvents(order.id)).toHaveLength(wins);
      await expectValidHistory(order.id);
      await expectStockConsistent(initial(s));
    }
  }, 60_000);

  it('confirm vs cancel from the other side behaves the same', async () => {
    for (let round = 0; round < 4; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await warmPool();

      const results = await Promise.allSettled([
        transitions.confirm(order.id, s.owner.id),
        transitions.cancelByOwner(order.id, s.owner.id, 'x'),
      ]);

      expect(results.some((r) => r.status === 'fulfilled')).toBe(true);
      await expectValidHistory(order.id);
      await expectStockConsistent(initial(s));
    }
  }, 60_000);

  it('ready vs cancel on a CONFIRMED order: exactly one wins', async () => {
    for (let round = 0; round < 4; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await advance(s, order, OrderStatus.CONFIRMED);
      await warmPool();

      const results = await Promise.allSettled([
        transitions.markReady(order.id, s.owner.id),
        transitions.cancelByCustomer(order.id, s.customer.id),
      ]);

      // READY and CANCELLED exclude each other from CONFIRMED.
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(
        results.filter((r) => r.status === 'rejected').map(codeOf),
      ).toEqual(['ORDER_STATE_CHANGED']);
      expect(await transitionEvents(order.id)).toHaveLength(2); // confirm + the winner
      await expectValidHistory(order.id);
      await expectStockConsistent(initial(s));
    }
  }, 60_000);

  it('ready vs complete: complete only after ready, never both from CONFIRMED', async () => {
    for (let round = 0; round < 4; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await advance(s, order, OrderStatus.CONFIRMED);
      await warmPool();

      const results = await Promise.allSettled([
        transitions.markReady(order.id, s.owner.id),
        transitions.complete(order.id, s.owner.id),
      ]);

      expect(codeOf(results[0]!)).toBe('fulfilled'); // ready always works
      expect(['fulfilled', 'ORDER_STATE_CHANGED']).toContain(
        codeOf(results[1]!),
      );
      await expectValidHistory(order.id);
      await expectStockConsistent(initial(s));
    }
  }, 60_000);

  it('complete vs no-show on a READY order: exactly one wins, stock matches the winner', async () => {
    for (let round = 0; round < 4; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await advance(s, order, OrderStatus.READY_FOR_PICKUP);
      await warmPool();

      const results = await Promise.allSettled([
        transitions.complete(order.id, s.owner.id),
        transitions.markNoShow(order.id, s.owner.id),
      ]);

      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(
        results.filter((r) => r.status === 'rejected').map(codeOf),
      ).toEqual(['ORDER_STATE_CHANGED']);
      const finalStatus = (await orderRow(order.id))!.status;
      // The stock comes back only if no-show won.
      expect(await stockOf(s.lait)).toBe(finalStatus === 'NO_SHOW' ? 10 : 6);
      expect(await transitionEvents(order.id)).toHaveLength(3);
      await expectValidHistory(order.id);
      await expectStockConsistent(initial(s));
    }
  }, 60_000);

  it('ready vs no-show on a CONFIRMED order: history stays valid', async () => {
    for (let round = 0; round < 4; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await advance(s, order, OrderStatus.CONFIRMED);
      await warmPool();

      const results = await Promise.allSettled([
        transitions.markReady(order.id, s.owner.id),
        transitions.markNoShow(order.id, s.owner.id),
      ]);

      expect(codeOf(results[0]!)).toBe('fulfilled');
      expect(['fulfilled', 'ORDER_STATE_CHANGED']).toContain(
        codeOf(results[1]!),
      );
      await expectValidHistory(order.id);
      await expectStockConsistent(initial(s));
    }
  }, 60_000);

  it('confirmation with a removal vs cancellation never restores a line twice', async () => {
    for (let round = 0; round < 6; round += 1) {
      const s = await scenario();
      const order = await s.place();
      await warmPool();

      const results = await Promise.allSettled([
        transitions.confirm(order.id, s.owner.id, {
          removeItemIds: [order.items[0]!.id],
        }),
        transitions.cancelByCustomer(order.id, s.customer.id),
      ]);

      for (const result of results) {
        expect(['fulfilled', 'ORDER_STATE_CHANGED']).toContain(codeOf(result));
      }
      await expectValidHistory(order.id);
      // Whatever the interleaving: confirm-then-cancel, cancel-then-(refused)
      // confirm, or only the confirmation, no line was given back twice.
      await expectStockConsistent(initial(s));
      const status = (await orderRow(order.id))!.status;
      const items = await itemsOf(order.id);
      if (status === 'CANCELLED') {
        expect(await stockOf(s.lait)).toBe(10);
        expect(await stockOf(s.yaourt)).toBe(10);
      } else {
        expect(items.filter((i) => i.removedAt !== null)).toHaveLength(1);
      }
    }
  }, 60_000);

  it('concurrent multi-line operations over shared products never double-restore', async () => {
    const s = await scenario({ laitStock: 40, yaourtStock: 40 });
    const customers = await Promise.all(
      Array.from({ length: 4 }, () => register('CLIENT')),
    );
    const orders: OrderRecord[] = [];
    for (const customer of customers) {
      for (let i = 0; i < 2; i += 1) {
        const { order } = await creation.createOrder({
          customerId: customer.id,
          storeId: s.store.storeId,
          lines: [
            { storeProductId: s.lait, quantity: 2 },
            { storeProductId: s.yaourt, quantity: 3 },
          ],
          requestedPickupAt: hoursFromNow(4),
          idempotencyKey: `key-${tag}-${(keyCounter += 1)}`,
        });
        orders.push(order);
      }
    }
    expect(await stockOf(s.lait)).toBe(40 - 16);
    await warmPool();

    // A mix on every order, all at once: some cancel (twice), some confirm
    // with a removal and are then cancelled, some are confirmed and left.
    const operations: Promise<unknown>[] = [];
    orders.forEach((order, index) => {
      const customer = customers[Math.floor(index / 2)]!;
      switch (index % 4) {
        case 0:
          operations.push(
            transitions.cancelByCustomer(order.id, customer.id),
            transitions.cancelByOwner(order.id, s.owner.id, 'dup'),
          );
          break;
        case 1:
          operations.push(
            transitions.confirm(order.id, s.owner.id, {
              removeItemIds: [order.items[0]!.id],
            }),
            transitions.cancelByCustomer(order.id, customer.id),
          );
          break;
        case 2:
          operations.push(
            transitions.confirm(order.id, s.owner.id, {
              removeItemIds: [order.items[1]!.id],
            }),
            transitions.confirm(order.id, s.owner.id, {
              removeItemIds: [order.items[1]!.id],
            }),
          );
          break;
        default:
          operations.push(transitions.confirm(order.id, s.owner.id));
      }
    });
    const results = await Promise.allSettled(operations);

    for (const result of results) {
      expect(['fulfilled', 'ORDER_STATE_CHANGED']).toContain(codeOf(result));
    }
    for (const order of orders) await expectValidHistory(order.id);
    await expectStockConsistent({ [s.lait]: 40, [s.yaourt]: 40 });
  }, 60_000);
});
