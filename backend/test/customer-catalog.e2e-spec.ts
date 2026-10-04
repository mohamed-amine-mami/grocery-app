import request from 'supertest';
import { db } from '../src/prisma/db.js';
import {
  archiveCategory,
  archiveProduct,
  removeCatalog,
  seedCatalog,
} from './catalog-helpers.js';
import {
  archiveStoreProduct,
  hoursFromNow,
  openStore as openStoreFor,
  patchStoreProduct,
  setAvailability,
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
 * The customer's read-only store and catalogue API, against the real database.
 * Fixture catalog (tagged): banane KG (min 100, step 100, max 10000) in
 * Fruits; lait-delice-1l and yaourt (max 24) PIECE in Produits laitiers.
 */

const tag = `e2ecat${Date.now()}`;
let catalog: Awaited<ReturnType<typeof seedCatalog>>;
let customer: Account;

beforeAll(async () => {
  await startApp();
  catalog = await seedCatalog(tag);
  customer = await register('CLIENT');
});
afterAll(async () => {
  await stopApp();
  await removeCatalog(tag);
});

const openStore = () => openStoreFor((slug) => catalog.productId(slug));
const browse = (storeId: number | string, as: Account = customer) =>
  request(http()).get(`/stores/${storeId}/products`).set(auth(as));
const byName = (items: { name: string }[], fragment: string) =>
  items.find((item) => item.name.includes(fragment));

// ── GET /stores ───────────────────────────────────────────────────────────

describe('GET /stores', () => {
  it('lets a CLIENT list stores, closed ones included, with customer-safe fields only', async () => {
    const open = await openStore();
    const closed = await openStore();
    await db.orm.public.Store.where({ id: closed.storeId }).update({
      isOpen: false,
    });

    const response = await request(http()).get('/stores').set(auth(customer));
    expect(response.status).toBe(200);
    const mine = (id: number) =>
      response.body.find((store: { id: number }) => store.id === id);
    expect(mine(open.storeId)).toMatchObject({
      name: 'Menzah Market',
      address: expect.any(String),
      isOpen: true,
    });
    expect(mine(closed.storeId)).toMatchObject({ isOpen: false });

    // Exactly the approved fields, nothing of the owner.
    expect(Object.keys(mine(open.storeId)).sort()).toEqual(
      [
        'address',
        'description',
        'id',
        'isOpen',
        'latitude',
        'longitude',
        'name',
        'photo',
      ].sort(),
    );
    const text = JSON.stringify(response.body);
    expect(text).not.toMatch(
      /ownerId|ownerEmail|phoneNumber|email|password|createdAt|updatedAt/i,
    );
    expect(text).not.toContain(open.owner.phoneNumber);
  });

  it('follows the API policy: a token is required, and OWNERs are refused', async () => {
    const { owner } = await openStore();
    await request(http()).get('/stores').expect(401);
    await request(http())
      .get('/stores')
      .set('Authorization', 'Bearer nope')
      .expect(401);
    await request(http()).get('/stores').set(auth(owner)).expect(403);
  });
});

// ── GET /stores/:id/products ──────────────────────────────────────────────

describe('GET /stores/:id/products', () => {
  it('returns the store’s own offerings with its price, unit, rules and category', async () => {
    const store = await openStore();
    const banane = await store.offer('banane', { priceMillimes: 1800 });
    const yaourt = await store.offer('yaourt', {
      priceMillimes: 700,
      minQuantity: 2,
      maxQuantity: 12,
    });

    const response = await browse(store.storeId).expect(200);
    expect(response.body).toHaveLength(2);

    const bananaItem = byName(response.body, 'Banane');
    expect(bananaItem).toEqual({
      id: banane,
      name: `Banane ${tag}`,
      description: null,
      photo: null,
      category: {
        id: catalog.categoryId('fruits'),
        name: `Fruits ${tag}`,
      },
      saleUnit: 'KG',
      priceMillimes: 1800,
      minQuantity: 100,
      quantityStep: 100,
      maxQuantity: 10000,
      isOrderable: true,
      unavailabilityReason: null,
    });
    expect(byName(response.body, 'Yaourt')).toMatchObject({
      id: yaourt,
      description: 'Pot individuel',
      category: { id: catalog.categoryId('laitiers') },
      saleUnit: 'PIECE',
      priceMillimes: 700,
      minQuantity: 2,
      quantityStep: 1,
      maxQuantity: 12,
    });
    // By category name, then product name.
    expect(response.body.map((item: { name: string }) => item.name)).toEqual([
      `Banane ${tag}`,
      `Yaourt nature ${tag}`,
    ]);
  });

  it('shows the store’s own unit and rules when it sells by another unit', async () => {
    const store = await openStore();
    await store.offer('banane', {
      saleUnit: 'PIECE',
      priceMillimes: 300,
    });
    const response = await browse(store.storeId).expect(200);
    expect(response.body[0]).toMatchObject({
      saleUnit: 'PIECE',
      priceMillimes: 300,
      minQuantity: 1,
      quantityStep: 1,
    });
  });

  it('isolates stores: only their own products, prices and rules', async () => {
    const a = await openStore();
    const b = await openStore();
    const aLait = await a.offer('lait-delice-1l', { priceMillimes: 1800 });
    const bLait = await b.offer('lait-delice-1l', {
      priceMillimes: 2400,
      minQuantity: 3,
      trackStock: true,
      stockQuantity: 0,
    });
    await b.offer('yaourt');

    const fromA = (await browse(a.storeId).expect(200)).body;
    expect(fromA).toHaveLength(1); // not B's yogurt, nor catalog products nobody offers
    expect(fromA[0]).toMatchObject({
      id: aLait,
      priceMillimes: 1800,
      minQuantity: 1,
      isOrderable: true,
    });
    const fromB = (await browse(b.storeId).expect(200)).body;
    expect(fromB).toHaveLength(2);
    expect(
      fromB.find((item: { id: number }) => item.id === bLait),
    ).toMatchObject({
      priceMillimes: 2400,
      minQuantity: 3,
      isOrderable: false,
    });
    expect(fromB.some((item: { id: number }) => item.id === aLait)).toBe(false);
  });

  it('lists nothing for an empty store, 404 for an unknown one, 400 for a bad id', async () => {
    const empty = await openStore();
    expect((await browse(empty.storeId).expect(200)).body).toEqual([]);
    await browse(2147483000).expect(404);
    await browse('abc').expect(400);
  });

  it('still lists a closed store’s catalogue', async () => {
    const store = await openStore();
    await store.offer('lait-delice-1l');
    await db.orm.public.Store.where({ id: store.storeId }).update({
      isOpen: false,
    });
    expect((await browse(store.storeId).expect(200)).body).toHaveLength(1);
  });

  it('requires a token and a CLIENT', async () => {
    const store = await openStore();
    await request(http()).get(`/stores/${store.storeId}/products`).expect(401);
    await browse(store.storeId, store.owner).expect(403);
  });
});

describe('what is listed, and whether it is orderable', () => {
  it('hides what the store removed (archived store product)', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    await store.offer('yaourt');
    await archiveStoreProduct(store, lait);
    const items = (await browse(store.storeId).expect(200)).body;
    expect(items.map((item: { name: string }) => item.name)).toEqual([
      `Yaourt nature ${tag}`,
    ]);
  });

  it('hides a product archived in the catalog, and restores it with the product', async () => {
    const store = await openStore();
    await store.offer('lait-delice-1l');
    const yaourt = await store.offer('yaourt');
    await archiveProduct(catalog.productId('yaourt'));
    try {
      const items = (await browse(store.storeId).expect(200)).body;
      expect(items.some((item: { id: number }) => item.id === yaourt)).toBe(
        false,
      );
      expect(items).toHaveLength(1);
    } finally {
      await db.orm.public.Product.where({
        id: catalog.productId('yaourt'),
      }).update({ archivedAt: null });
    }
    expect((await browse(store.storeId).expect(200)).body).toHaveLength(2);
  });

  it('hides products of a category archived in the catalog', async () => {
    const store = await openStore();
    await store.offer('banane');
    const lait = await store.offer('lait-delice-1l');
    await archiveCategory(catalog.categoryId('laitiers'));
    try {
      const items = (await browse(store.storeId).expect(200)).body;
      expect(items.some((item: { id: number }) => item.id === lait)).toBe(
        false,
      );
      expect(items).toHaveLength(1);
    } finally {
      await db.orm.public.Category.where({
        id: catalog.categoryId('laitiers'),
      }).update({ archivedAt: null });
    }
  });

  it('lists an owner-disabled product as not orderable', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l');
    await setAvailability(store, lait, false);
    const [item] = (await browse(store.storeId).expect(200)).body;
    expect(item).toMatchObject({
      id: lait,
      isOrderable: false,
      unavailabilityReason: 'OWNER_DISABLED',
    });
    await setAvailability(store, lait, true);
    expect((await browse(store.storeId)).body[0].isOrderable).toBe(true);
  });

  it('tracked stock: out of stock and below the minimum are not orderable, enough is', async () => {
    const store = await openStore();
    const empty = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 0,
    });
    const low = await store.offer('banane', {
      trackStock: true,
      stockQuantity: 50, // below the 100 g minimum
    });
    const enough = await store.offer('yaourt', {
      trackStock: true,
      stockQuantity: 2,
    });
    const items = (await browse(store.storeId).expect(200)).body;
    const find = (id: number) =>
      items.find((item: { id: number }) => item.id === id);
    expect(find(empty)).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'OUT_OF_STOCK',
    });
    expect(find(low)).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'STOCK_BELOW_MINIMUM',
    });
    expect(find(enough)).toMatchObject({
      isOrderable: true,
      unavailabilityReason: null,
    });
  });

  it('untracked stock stays orderable whatever the stock figure was', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 0,
    });
    expect((await browse(store.storeId)).body[0].isOrderable).toBe(false);
    await patchStoreProduct(store, lait, {
      trackStock: false,
      expectedStockQuantity: 0,
    });
    expect((await browse(store.storeId)).body[0]).toMatchObject({
      isOrderable: true,
      unavailabilityReason: null,
    });
  });

  it('follows stock as orders take it, with the order service as the authority', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 3,
    });
    const buyer = await register('CLIENT');
    const place = (quantity: number) =>
      request(http())
        .post('/orders')
        .set(auth(buyer))
        .send({
          storeId: store.storeId,
          lines: [{ storeProductId: lait, quantity }],
          requestedPickupAt: hoursFromNow(4).toISOString(),
          idempotencyKey: `k-${tag}-${quantity}-${Math.random()}`,
        });
    expect((await browse(store.storeId)).body[0].isOrderable).toBe(true);
    await place(3).expect(201);
    expect((await browse(store.storeId)).body[0]).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'OUT_OF_STOCK',
    });
    // Browsing said nothing binding: checkout revalidates.
    const refused = await place(1);
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe('PRODUCT_UNAVAILABLE');
  });

  it('a stale catalogue cannot buy what checkout refuses (price and flags are not trusted)', async () => {
    const store = await openStore();
    const lait = await store.offer('lait-delice-1l', { priceMillimes: 1800 });
    const seen = (await browse(store.storeId)).body[0];
    expect(seen.isOrderable).toBe(true);
    await setAvailability(store, lait, false);
    const buyer = await register('CLIENT');
    const response = await request(http())
      .post('/orders')
      .set(auth(buyer))
      .send({
        storeId: store.storeId,
        lines: [{ storeProductId: lait, quantity: 1, priceMillimes: 1 }],
        requestedPickupAt: hoursFromNow(4).toISOString(),
        idempotencyKey: `k-${tag}-stale`,
      });
    expect(response.status).toBe(400); // client-sent price is rejected outright
    const ok = await request(http())
      .post('/orders')
      .set(auth(buyer))
      .send({
        storeId: store.storeId,
        lines: [{ storeProductId: lait, quantity: 1 }],
        requestedPickupAt: hoursFromNow(4).toISOString(),
        idempotencyKey: `k-${tag}-stale2`,
      });
    expect(ok.status).toBe(409);
    expect(ok.body.code).toBe('PRODUCT_UNAVAILABLE');
  });
});

describe('what a customer never sees', () => {
  it('never returns stock, stock accounting or owner data, tracked or not', async () => {
    const store = await openStore();
    const tracked = await store.offer('lait-delice-1l', {
      trackStock: true,
      stockQuantity: 4242,
    });
    await store.offer('yaourt');
    await store.offer('banane', { trackStock: true, stockQuantity: 50 });
    // Even with an order that has decremented stock.
    const buyer = await register('CLIENT');
    await request(http())
      .post('/orders')
      .set(auth(buyer))
      .send({
        storeId: store.storeId,
        lines: [{ storeProductId: tracked, quantity: 2 }],
        requestedPickupAt: hoursFromNow(4).toISOString(),
        idempotencyKey: `k-${tag}-leak`,
      })
      .expect(201);

    const catalogResponse = await browse(store.storeId).expect(200);
    const storesResponse = await request(http())
      .get('/stores')
      .set(auth(customer))
      .expect(200);
    for (const payload of [catalogResponse.body, storesResponse.body]) {
      const text = JSON.stringify(payload);
      expect(text).not.toMatch(
        /stockQuantity|stockDecrementedQuantity|trackStock|"stock\w*"\s*:|ownerId|email|phoneNumber/i,
      );
    }
    expect(JSON.stringify(catalogResponse.body)).not.toContain('4242');
    expect(JSON.stringify(catalogResponse.body)).not.toContain('4240');
    for (const item of catalogResponse.body) {
      expect(Object.keys(item).sort()).toEqual(
        [
          'category',
          'description',
          'id',
          'isOrderable',
          'maxQuantity',
          'minQuantity',
          'name',
          'photo',
          'priceMillimes',
          'quantityStep',
          'saleUnit',
          'unavailabilityReason',
        ].sort(),
      );
    }
  });

  it('keeps stock out of the published Swagger schemas and error bodies', async () => {
    const { DocumentBuilder, SwaggerModule } = await import('@nestjs/swagger');
    const { Test } = await import('@nestjs/testing');
    const { AppModule } = await import('../src/app.module.js');
    const { setupApp } = await import('../src/app.setup.js');
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    const app = moduleFixture.createNestApplication();
    setupApp(app);
    await app.init();
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder().build(),
    );
    await app.close();
    const schemas = document.components!.schemas as Record<string, object>;
    for (const name of [
      'CustomerStoreEntity',
      'CustomerCategoryEntity',
      'CustomerCatalogItemEntity',
      'CustomerOrderEntity',
      'CustomerOrderItemEntity',
      'OrderItemEntity',
      'OrderEventEntity',
      'OrderStoreEntity',
      'CustomerOrderPageEntity',
      'CustomerOrderTransitionEntity',
    ]) {
      if (!schemas[name]) continue;
      expect(JSON.stringify(schemas[name])).not.toMatch(
        /stockQuantity|stockDecrementedQuantity|ownerId|trackStock/,
      );
    }
    expect(schemas['CustomerCatalogItemEntity']).toBeDefined();
    expect(schemas['CustomerStoreEntity']).toBeDefined();

    const notFound = await browse(2147483000).expect(404);
    expect(JSON.stringify(notFound.body)).not.toMatch(/stock/i);
  });
});
