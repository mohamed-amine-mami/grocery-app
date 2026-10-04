import request from 'supertest';
import { db } from '../src/prisma/db.js';
import { removeCatalog, seedCatalog } from './catalog-helpers.js';
import {
  auth,
  http,
  registerOwnerWithStore,
  startApp,
  stopApp,
  type Account,
} from './support.js';

/**
 * The architecture's guarantees, asserted across the whole API rather than one
 * endpoint at a time: the global Product has no stock or store data, stock is
 * the store product's and store-specific, zero stock makes a product
 * unorderable by itself, untracked products stay manual, and no owner route
 * can change the global catalog.
 */

const tag = `e2einv${Date.now()}`;
let catalog: Awaited<ReturnType<typeof seedCatalog>>;

beforeAll(async () => {
  await startApp();
  catalog = await seedCatalog(tag);
});

afterAll(async () => {
  await stopApp();
  await removeCatalog(tag);
});

const API = '/owner/store-products';
const freshOwner = async () => (await registerOwnerWithStore()).owner;
const add = (owner: Account, slug: string, body: object = {}) =>
  request(http())
    .post(API)
    .set(auth(owner))
    .send({ productId: catalog.productId(slug), priceMillimes: 4500, ...body });
const added = async (owner: Account, slug: string, body: object = {}) =>
  (await add(owner, slug, body).expect(201)).body;
const get = async (owner: Account, id: number) =>
  (await request(http()).get(`${API}/${id}`).set(auth(owner)).expect(200)).body;

const globalRows = async () => ({
  categories: (await db.orm.public.Category.all()).sort((a, b) => a.id - b.id),
  products: (await db.orm.public.Product.all()).sort((a, b) => a.id - b.id),
});

const STORE_AND_STOCK_FIELDS = [
  'storeId',
  'priceMillimes',
  'saleUnit',
  'minQuantity',
  'quantityStep',
  'maxQuantity',
  'trackStock',
  'stockQuantity',
  'isAvailable',
  'isOrderable',
];

describe('the global Product has no stock and no store data', () => {
  it('in the database', async () => {
    const row = await db.orm.public.Product.first({
      id: catalog.productId('banane'),
    });
    for (const field of STORE_AND_STOCK_FIELDS) {
      expect(row).not.toHaveProperty(field);
    }
  });

  it('in the catalog API', async () => {
    const owner = await freshOwner();
    await added(owner, 'banane', { trackStock: true, stockQuantity: 20_000 });

    const response = await request(http())
      .get('/owner/catalog/products')
      .set(auth(owner))
      .expect(200);

    const banana = response.body.find(
      (p: { slug: string }) => p.slug === `${tag}-banane`,
    );
    // Even for a product this store tracks, the catalog entry shows no stock.
    for (const field of STORE_AND_STOCK_FIELDS) {
      expect(banana).not.toHaveProperty(field);
    }
  });

  it('inside the store product (only identity and defaults)', async () => {
    const owner = await freshOwner();
    const body = await added(owner, 'banane', {
      trackStock: true,
      stockQuantity: 20_000,
    });
    for (const field of STORE_AND_STOCK_FIELDS) {
      expect(body.product).not.toHaveProperty(field);
    }
    expect(body).toMatchObject({ trackStock: true, stockQuantity: 20_000 });
  });
});

describe('stock belongs to the store product and is store-specific', () => {
  it('keeps each store’s stock independent for the same catalog product', async () => {
    const a = await freshOwner();
    const b = await freshOwner();
    const c = await freshOwner();
    const forA = await added(a, 'banane', {
      trackStock: true,
      stockQuantity: 20_000,
    });
    const forB = await added(b, 'banane', {
      trackStock: true,
      stockQuantity: 500,
    });
    const forC = await added(c, 'banane'); // does not track stock at all

    // An order drains A's stock completely (simulated behind the API).
    await db.orm.public.StoreProduct.where({ id: forA.id }).update({
      stockQuantity: 0,
    });

    expect(await get(a, forA.id)).toMatchObject({
      stockQuantity: 0,
      isOrderable: false,
      unavailabilityReason: 'OUT_OF_STOCK',
    });
    expect(await get(b, forB.id)).toMatchObject({
      stockQuantity: 500,
      isOrderable: true,
    });
    expect(await get(c, forC.id)).toMatchObject({
      trackStock: false,
      stockQuantity: null,
      isOrderable: true,
    });

    // B's owner restocks: A's zero is untouched.
    await request(http())
      .patch(`${API}/${forB.id}`)
      .set(auth(b))
      .send({ stockQuantity: 9000, expectedStockQuantity: 500 })
      .expect(200);
    expect((await get(a, forA.id)).stockQuantity).toBe(0);
    expect((await get(b, forB.id)).stockQuantity).toBe(9000);
  });

  it('never lets one store read or change another store’s stock', async () => {
    const a = await freshOwner();
    const b = await freshOwner();
    const forA = await added(a, 'banane', {
      trackStock: true,
      stockQuantity: 20_000,
    });

    await request(http()).get(`${API}/${forA.id}`).set(auth(b)).expect(404);
    await request(http())
      .patch(`${API}/${forA.id}`)
      .set(auth(b))
      .send({ stockQuantity: 1, expectedStockQuantity: 20_000 })
      .expect(404);
    expect((await get(a, forA.id)).stockQuantity).toBe(20_000);
  });
});

describe('zero stock makes a tracked product unorderable by itself', () => {
  it('without the owner touching the switch, through every path that can reach zero', async () => {
    const owner = await freshOwner();
    const viaOwner = await added(owner, 'banane', {
      trackStock: true,
      stockQuantity: 500,
    });
    const viaCreate = await added(owner, 'yaourt', {
      trackStock: true,
      stockQuantity: 0,
    });

    await request(http())
      .patch(`${API}/${viaOwner.id}`)
      .set(auth(owner))
      .send({ stockQuantity: 0, expectedStockQuantity: 500 })
      .expect(200);

    for (const id of [viaOwner.id, viaCreate.id]) {
      expect(await get(owner, id)).toMatchObject({
        stockQuantity: 0,
        isAvailable: true,
        isOrderable: false,
        unavailabilityReason: 'OUT_OF_STOCK',
      });
    }
  });
});

describe('products that do not track stock stay manually available or unavailable', () => {
  it('follows the owner’s switch alone, and never grows a stock quantity', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'yaourt');
    expect(created).toMatchObject({
      trackStock: false,
      stockQuantity: null,
      isOrderable: true,
    });

    for (const [isAvailable, orderable, reason] of [
      [false, false, 'OWNER_DISABLED'],
      [true, true, null],
      [false, false, 'OWNER_DISABLED'],
    ] as const) {
      const response = await request(http())
        .patch(`${API}/${created.id}/availability`)
        .set(auth(owner))
        .send({ isAvailable })
        .expect(200);
      expect(response.body).toMatchObject({
        isAvailable,
        isOrderable: orderable,
        unavailabilityReason: reason,
        trackStock: false,
        stockQuantity: null,
      });
    }
  });

  it('cannot be given a stock quantity without turning tracking on', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'yaourt');
    await request(http())
      .patch(`${API}/${created.id}`)
      .set(auth(owner))
      .send({ stockQuantity: 0, expectedStockQuantity: null })
      .expect(400);
    expect(await get(owner, created.id)).toMatchObject({
      trackStock: false,
      stockQuantity: null,
      isOrderable: true,
    });
  });
});

describe('no owner API can modify the global catalog', () => {
  it('leaves every Category and Product row identical after a barrage of owner writes', async () => {
    const owner = await freshOwner();
    const other = await freshOwner();
    const banana = catalog.productId('banane');
    const before = await globalRows();

    const globalFields = {
      name: 'Hacked',
      description: 'Hacked',
      photo: 'https://cdn.example.com/hacked.jpg',
      slug: 'hacked',
      categoryId: catalog.categoryId('laitiers'),
      defaultSaleUnit: 'L',
      defaultMinQuantity: 1,
      archivedAt: '2026-01-01T00:00:00Z',
      stockQuantity: 5, // a store-product field, but never a catalog one
    };

    // Every global field, on create and on edit: all rejected.
    for (const [field, value] of Object.entries(globalFields)) {
      if (field !== 'stockQuantity') {
        await request(http())
          .post(API)
          .set(auth(owner))
          .send({ productId: banana, priceMillimes: 4500, [field]: value })
          .expect(400);
      }
    }
    const created = await added(owner, 'banane');
    for (const [field, value] of Object.entries(globalFields)) {
      if (field !== 'stockQuantity') {
        await request(http())
          .patch(`${API}/${created.id}`)
          .set(auth(owner))
          .send({ [field]: value })
          .expect(400);
      }
    }

    // Legitimate store writes of every kind.
    await request(http())
      .patch(`${API}/${created.id}`)
      .set(auth(owner))
      .send({ priceMillimes: 9999, minQuantity: 200, quantityStep: 100 })
      .expect(200);
    await request(http())
      .patch(`${API}/${created.id}/availability`)
      .set(auth(owner))
      .send({ isAvailable: false })
      .expect(200);
    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);
    await request(http())
      .post(`${API}/${created.id}/restore`)
      .set(auth(owner))
      .expect(200);
    await added(other, 'yaourt');

    // Writes aimed at the catalog and at the removed per-store routes: none exist.
    for (const method of ['post', 'put', 'patch', 'delete'] as const) {
      for (const path of [
        '/owner/catalog/categories',
        `/owner/catalog/categories/${catalog.categoryId('fruits')}`,
        '/owner/catalog/products',
        `/owner/catalog/products/${banana}`,
        '/owner/categories',
        `/owner/categories/${catalog.categoryId('fruits')}`,
        '/owner/products',
        `/owner/products/${banana}`,
      ]) {
        const response = await (
          request(http()) as unknown as Record<
            string,
            (p: string) => request.Test
          >
        )[method]!(path)
          .set(auth(owner))
          .send(globalFields);
        expect({ method, path, status: response.status }).toEqual({
          method,
          path,
          status: 404,
        });
      }
    }

    expect(await globalRows()).toEqual(before);
  });
});
