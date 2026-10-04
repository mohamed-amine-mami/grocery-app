import request from 'supertest';
import { db } from '../src/prisma/db.js';
import {
  archiveCategory,
  archiveProduct,
  removeCatalog,
  seedCatalog,
} from './catalog-helpers.js';
import {
  auth,
  http,
  register,
  registerOwnerWithStore,
  startApp,
  stopApp,
  type Account,
} from './support.js';

/**
 * A store's offerings of global catalog products, through the real HTTP API.
 * The fixture catalog (tagged, seeded by the importer):
 *   banane          KG    min 100 step 100 max 10000
 *   lait-delice-1l  PIECE min 1   step 1   no max
 *   yaourt          PIECE min 1   step 1   max 24
 */

const tag = `e2esp${Date.now()}`;
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

/** Adds `slug` to the owner's store, returning the raw response. */
const add = (owner: Account, slug: string, body: object = {}) =>
  request(http())
    .post(API)
    .set(auth(owner))
    .send({ productId: catalog.productId(slug), priceMillimes: 4500, ...body });

/** Adds `slug` and expects success; every test uses a store that never had it. */
async function added(owner: Account, slug: string, body: object = {}) {
  const response = await add(owner, slug, body).expect(201);
  return response.body;
}

/** A fresh owner+store, so tests never share offerings. */
const freshOwner = async () => (await registerOwnerWithStore()).owner;

const get = (owner: Account, id: number) =>
  request(http()).get(`${API}/${id}`).set(auth(owner));
const patch = (owner: Account, id: number, body: object) =>
  request(http()).patch(`${API}/${id}`).set(auth(owner)).send(body);

describe('authentication and authorization', () => {
  it('requires a token', async () => {
    await request(http()).get(API).expect(401);
    await request(http()).post(API).send({}).expect(401);
  });

  it('is for owners only', async () => {
    const client = await register('CLIENT');
    await request(http()).get(API).set(auth(client)).expect(403);
    await request(http()).post(API).set(auth(client)).send({}).expect(403);
  });

  it('is a 404 for an owner who has no store yet', async () => {
    const owner = await register('OWNER');
    await request(http()).get(API).set(auth(owner)).expect(404);
    await add(owner, 'banane').expect(404);
  });
});

describe('POST /owner/store-products', () => {
  it('adds a catalog product with the catalog defaults', async () => {
    const owner = await freshOwner();

    const body = await added(owner, 'banane');

    expect(body).toMatchObject({
      productId: catalog.productId('banane'),
      saleUnit: 'KG',
      priceMillimes: 4500,
      minQuantity: 100,
      quantityStep: 100,
      maxQuantity: 10_000,
      trackStock: false,
      stockQuantity: null,
      isAvailable: true,
      isOrderable: true,
      unavailabilityReason: null,
      archivedAt: null,
    });
  });

  it('returns the store data with the catalog product and category', async () => {
    const owner = await freshOwner();
    await db.orm.public.Product.where({
      id: catalog.productId('banane'),
    }).update({
      description: 'Jaune et sucrée',
      photo: 'https://cdn.example.com/banane.jpg',
    });

    const body = await added(owner, 'banane');

    expect(body.product).toEqual({
      id: catalog.productId('banane'),
      slug: `${tag}-banane`,
      name: `Banane ${tag}`,
      description: 'Jaune et sucrée',
      photo: 'https://cdn.example.com/banane.jpg',
      defaultSaleUnit: 'KG',
      allowedSaleUnits: ['KG', 'PIECE'],
      defaultMinQuantity: 100,
      defaultQuantityStep: 100,
      defaultMaxQuantity: 10_000,
      isActive: true,
    });
    expect(body.category).toEqual({
      id: catalog.categoryId('fruits'),
      slug: `${tag}-fruits`,
      name: `Fruits ${tag}`,
      isActive: true,
    });
  });

  it('lets the owner override the quantity rules', async () => {
    const owner = await freshOwner();

    const body = await added(owner, 'banane', {
      minQuantity: 250,
      quantityStep: 250,
      maxQuantity: null,
    });

    expect(body).toMatchObject({
      minQuantity: 250,
      quantityStep: 250,
      maxQuantity: null,
    });
  });

  it('lets the owner start switched off', async () => {
    const owner = await freshOwner();

    const body = await added(owner, 'yaourt', { isAvailable: false });

    expect(body).toMatchObject({
      isAvailable: false,
      isOrderable: false,
      unavailabilityReason: 'OWNER_DISABLED',
    });
  });

  it('lets two stores sell the same product at different prices and rules', async () => {
    const a = await freshOwner();
    const b = await freshOwner();

    const forA = await added(a, 'banane', {
      priceMillimes: 4500,
      minQuantity: 100,
      quantityStep: 100,
    });
    const forB = await added(b, 'banane', {
      priceMillimes: 5000,
      minQuantity: 250,
      quantityStep: 250,
    });

    expect(forA).toMatchObject({ priceMillimes: 4500, quantityStep: 100 });
    expect(forB).toMatchObject({ priceMillimes: 5000, quantityStep: 250 });
    expect(forA.id).not.toBe(forB.id);
  });

  describe('duplicates', () => {
    it('rejects a product the store already sells with 409', async () => {
      const owner = await freshOwner();
      await added(owner, 'banane');

      const response = await add(owner, 'banane').expect(409);

      expect(response.body.message).toContain('already sells');
    });

    it('rejects an archived one with 409 and points to restore', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');
      await request(http())
        .delete(`${API}/${created.id}`)
        .set(auth(owner))
        .expect(204);

      const response = await add(owner, 'banane').expect(409);

      expect(response.body.message).toContain('restore');
      expect(response.body.message).toContain(String(created.id));
    });
  });

  describe('the unit rule: the product’s default unit or PIECE', () => {
    it('allows PIECE for a weighed product, with that unit’s own defaults', async () => {
      const owner = await freshOwner();

      const body = await added(owner, 'banane', { saleUnit: 'PIECE' });

      expect(body).toMatchObject({
        saleUnit: 'PIECE',
        minQuantity: 1,
        quantityStep: 1,
        maxQuantity: null,
      });
    });

    it('rejects an unrelated unit', async () => {
      const owner = await freshOwner();
      const response = await add(owner, 'banane', { saleUnit: 'L' }).expect(
        400,
      );
      expect(response.body.message).toEqual([
        'saleUnit must be one of KG, PIECE for this product',
      ]);
    });

    it.each(['KG', 'L'])(
      'keeps a piece-counted product in pieces (%s rejected)',
      async (unit) => {
        const owner = await freshOwner();
        await add(owner, 'lait-delice-1l', { saleUnit: unit }).expect(400);
      },
    );

    it('rejects an unknown unit', async () => {
      const owner = await freshOwner();
      await add(owner, 'banane', { saleUnit: 'DOZEN' }).expect(400);
    });
  });

  describe('price and quantity rules', () => {
    it.each([
      ['a zero price', { priceMillimes: 0 }],
      ['a negative price', { priceMillimes: -5 }],
      ['a fractional price', { priceMillimes: 4.5 }],
      ['a price above the ceiling', { priceMillimes: 10_000_001 }],
      ['no price at all', { priceMillimes: undefined }],
      ['a minimum off the step', { minQuantity: 150, quantityStep: 100 }],
      ['a zero step', { quantityStep: 0, minQuantity: 100 }],
      ['a maximum below the minimum', { minQuantity: 500, maxQuantity: 100 }],
      ['a maximum off the step', { maxQuantity: 1050 }],
      [
        'a weight step the unit does not allow',
        { quantityStep: 15, minQuantity: 15, maxQuantity: null },
      ],
      ['a fractional quantity', { quantityStep: 100.5 }],
    ])('rejects %s', async (_label, body) => {
      const owner = await freshOwner();
      await add(owner, 'banane', body).expect(400);
    });
  });

  describe('the catalog product', () => {
    it('is a 404 when it does not exist', async () => {
      const owner = await freshOwner();
      await request(http())
        .post(API)
        .set(auth(owner))
        .send({ productId: 2_147_000_000, priceMillimes: 4500 })
        .expect(404);
    });

    it('is a 409 when the catalog archived it', async () => {
      const localTag = `${tag}arch`;
      const local = await seedCatalog(localTag);
      const owner = await freshOwner();
      await archiveProduct(local.productId('yaourt'));

      await request(http())
        .post(API)
        .set(auth(owner))
        .send({ productId: local.productId('yaourt'), priceMillimes: 500 })
        .expect(409);
      await removeCatalog(localTag);
    });

    it('is a 409 when its category is archived', async () => {
      const localTag = `${tag}carch`;
      const local = await seedCatalog(localTag);
      const owner = await freshOwner();
      await archiveCategory(local.categoryId('fruits'));

      await request(http())
        .post(API)
        .set(auth(owner))
        .send({ productId: local.productId('banane'), priceMillimes: 500 })
        .expect(409);
      await removeCatalog(localTag);
    });
  });

  describe('global fields are rejected', () => {
    it.each([
      ['name', 'Hacked'],
      ['description', 'Hacked'],
      ['photo', 'https://cdn.example.com/x.jpg'],
      ['categoryId', 1],
      ['slug', 'hacked'],
      ['defaultSaleUnit', 'L'],
      ['storeId', 1],
    ])('%s', async (field, value) => {
      const owner = await freshOwner();
      const response = await add(owner, 'banane', { [field]: value }).expect(
        400,
      );
      expect(JSON.stringify(response.body.message)).toContain(
        `property ${field} should not exist`,
      );
    });
  });

  describe('stock at creation', () => {
    it('tracks stock when asked', async () => {
      const owner = await freshOwner();

      const body = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });

      expect(body).toMatchObject({
        trackStock: true,
        stockQuantity: 20_000,
        isOrderable: true,
      });
    });

    it('counts pieces for a piece product', async () => {
      const owner = await freshOwner();
      const body = await added(owner, 'yaourt', {
        trackStock: true,
        stockQuantity: 12,
      });
      expect(body.stockQuantity).toBe(12);
    });

    it('does not track stock by default', async () => {
      const owner = await freshOwner();
      const body = await added(owner, 'yaourt');
      expect(body).toMatchObject({ trackStock: false, stockQuantity: null });
    });

    it('accepts an empty shelf, which is simply not orderable', async () => {
      const owner = await freshOwner();

      const body = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 0,
      });

      expect(body).toMatchObject({
        stockQuantity: 0,
        isAvailable: true,
        isOrderable: false,
        unavailabilityReason: 'OUT_OF_STOCK',
      });
    });

    it.each([
      ['tracking without a quantity', { trackStock: true }],
      ['a quantity without tracking', { stockQuantity: 500 }],
      [
        'a quantity with tracking explicitly off',
        { trackStock: false, stockQuantity: 500 },
      ],
      ['negative stock', { trackStock: true, stockQuantity: -1 }],
      ['fractional stock', { trackStock: true, stockQuantity: 10.5 }],
      [
        'weighed stock off the granularity',
        { trackStock: true, stockQuantity: 15 },
      ],
      [
        'stock above the ceiling',
        { trackStock: true, stockQuantity: 10_000_010 },
      ],
      [
        'a null quantity while tracking',
        { trackStock: true, stockQuantity: null },
      ],
    ])('rejects %s', async (_label, body) => {
      const owner = await freshOwner();
      await add(owner, 'banane', body).expect(400);
    });
  });
});

describe('listing and fetching', () => {
  it('lists active store products sorted by product name, with catalog info', async () => {
    const owner = await freshOwner();
    await added(owner, 'yaourt');
    await added(owner, 'banane');

    const response = await request(http())
      .get(API)
      .set(auth(owner))
      .expect(200);

    expect(
      response.body.map((sp: { product: { slug: string } }) => sp.product.slug),
    ).toEqual([`${tag}-banane`, `${tag}-yaourt`]);
    expect(response.body[0].category.name).toBe(`Fruits ${tag}`);
  });

  it('filters by category and by status', async () => {
    const owner = await freshOwner();
    await added(owner, 'banane');
    const yogurt = await added(owner, 'yaourt');
    await request(http())
      .delete(`${API}/${yogurt.id}`)
      .set(auth(owner))
      .expect(204);

    const slugs = async (query: string) =>
      (
        await request(http()).get(`${API}${query}`).set(auth(owner)).expect(200)
      ).body.map((sp: { product: { slug: string } }) => sp.product.slug);

    expect(await slugs('')).toEqual([`${tag}-banane`]);
    expect(await slugs('?status=archived')).toEqual([`${tag}-yaourt`]);
    expect(await slugs('?status=all')).toEqual([
      `${tag}-banane`,
      `${tag}-yaourt`,
    ]);
    expect(
      await slugs(`?status=all&categoryId=${catalog.categoryId('laitiers')}`),
    ).toEqual([`${tag}-yaourt`]);
    await request(http())
      .get(`${API}?status=bogus`)
      .set(auth(owner))
      .expect(400);
  });

  it('fetches one, archived or not', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);

    const response = await get(owner, created.id).expect(200);

    expect(response.body.archivedAt).not.toBeNull();
  });

  describe('store isolation', () => {
    it('never shows another store’s products, and treats their ids as missing', async () => {
      const a = await freshOwner();
      const b = await freshOwner();
      const created = await added(a, 'banane');

      const list = await request(http()).get(API).set(auth(b)).expect(200);
      expect(list.body).toEqual([]);

      await get(b, created.id).expect(404);
      await patch(b, created.id, { priceMillimes: 1 }).expect(404);
      await request(http())
        .patch(`${API}/${created.id}/availability`)
        .set(auth(b))
        .send({ isAvailable: false })
        .expect(404);
      await request(http())
        .delete(`${API}/${created.id}`)
        .set(auth(b))
        .expect(404);
      await request(http())
        .post(`${API}/${created.id}/restore`)
        .set(auth(b))
        .expect(404);

      // …and none of those attempts changed anything.
      const unchanged = await get(a, created.id).expect(200);
      expect(unchanged.body).toEqual(created);
    });
  });
});

describe('PATCH /owner/store-products/:id', () => {
  it('changes the price', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');

    const response = await patch(owner, created.id, {
      priceMillimes: 4700,
    }).expect(200);

    expect(response.body.priceMillimes).toBe(4700);
    expect((await get(owner, created.id)).body.priceMillimes).toBe(4700);
  });

  it('changes the quantity rules and can clear the maximum', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');

    const response = await patch(owner, created.id, {
      minQuantity: 250,
      quantityStep: 250,
      maxQuantity: null,
    }).expect(200);

    expect(response.body).toMatchObject({
      minQuantity: 250,
      quantityStep: 250,
      maxQuantity: null,
    });
  });

  it.each([
    ['a minimum off the step', { minQuantity: 150 }],
    ['a maximum below the minimum', { maxQuantity: 50 }],
    ['a zero price', { priceMillimes: 0 }],
    ['a price above the ceiling', { priceMillimes: 10_000_001 }],
  ])('rejects %s', async (_label, body) => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    await patch(owner, created.id, body).expect(400);
  });

  it.each(['priceMillimes', 'saleUnit', 'minQuantity', 'quantityStep'])(
    'refuses null for %s',
    async (field) => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');
      await patch(owner, created.id, { [field]: null }).expect(400);
    },
  );

  it('answers 200 with the unchanged product for an empty body', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    const response = await patch(owner, created.id, {}).expect(200);
    expect(response.body).toEqual(created);
  });

  it.each([
    ['name', 'Hacked'],
    ['description', 'Hacked'],
    ['photo', 'https://cdn.example.com/x.jpg'],
    ['categoryId', 1],
    ['slug', 'hacked'],
    ['productId', 1],
    ['storeId', 1],
    ['isAvailable', false],
    ['archivedAt', null],
  ])('rejects %s', async (field, value) => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    const response = await patch(owner, created.id, { [field]: value }).expect(
      400,
    );
    expect(JSON.stringify(response.body.message)).toContain(
      `property ${field} should not exist`,
    );
    // The catalog and the offering are exactly as they were.
    expect((await get(owner, created.id)).body).toEqual(created);
  });

  it('refuses to modify an archived store product', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);
    await patch(owner, created.id, { priceMillimes: 1 }).expect(409);
  });

  describe('changing the unit', () => {
    it('requires restating price and rules for the new unit', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');

      const response = await patch(owner, created.id, {
        saleUnit: 'PIECE',
      }).expect(400);

      expect(response.body.message).toBe(
        'Changing saleUnit requires sending priceMillimes, minQuantity, quantityStep, maxQuantity for the new unit',
      );
    });

    it('works when everything is restated', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');

      const response = await patch(owner, created.id, {
        saleUnit: 'PIECE',
        priceMillimes: 700,
        minQuantity: 1,
        quantityStep: 1,
        maxQuantity: 12,
      }).expect(200);

      expect(response.body).toMatchObject({
        saleUnit: 'PIECE',
        priceMillimes: 700,
        minQuantity: 1,
        quantityStep: 1,
        maxQuantity: 12,
      });
    });

    it('rejects an unrelated unit', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');
      await patch(owner, created.id, {
        saleUnit: 'L',
        priceMillimes: 700,
        minQuantity: 100,
        quantityStep: 100,
        maxQuantity: 1000,
      }).expect(400);
    });

    it('also needs the stock restated while it is tracked', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });
      const restated = {
        saleUnit: 'PIECE',
        priceMillimes: 700,
        minQuantity: 1,
        quantityStep: 1,
        maxQuantity: 12,
      };

      const response = await patch(owner, created.id, restated).expect(400);
      expect(response.body.message).toContain('stockQuantity');

      const ok = await patch(owner, created.id, {
        ...restated,
        stockQuantity: 30,
        expectedStockQuantity: 20_000,
      }).expect(200);
      expect(ok.body).toMatchObject({ saleUnit: 'PIECE', stockQuantity: 30 });
    });
  });
});

describe('stock', () => {
  const stockOf = async (owner: Account, id: number) =>
    (await get(owner, id).expect(200)).body;

  it('turns tracking on for a product that had none', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');

    const response = await patch(owner, created.id, {
      trackStock: true,
      stockQuantity: 20_000,
      expectedStockQuantity: null,
    }).expect(200);

    expect(response.body).toMatchObject({
      trackStock: true,
      stockQuantity: 20_000,
      isOrderable: true,
    });
  });

  it('updates the quantity', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane', {
      trackStock: true,
      stockQuantity: 20_000,
    });

    const response = await patch(owner, created.id, {
      stockQuantity: 7500,
      expectedStockQuantity: 20_000,
    }).expect(200);

    expect(response.body.stockQuantity).toBe(7500);
    expect((await stockOf(owner, created.id)).stockQuantity).toBe(7500);
  });

  it('turns tracking off, which clears the quantity', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane', {
      trackStock: true,
      stockQuantity: 7500,
    });

    const response = await patch(owner, created.id, {
      trackStock: false,
      expectedStockQuantity: 7500,
    }).expect(200);

    expect(response.body).toMatchObject({
      trackStock: false,
      stockQuantity: null,
      isOrderable: true,
    });
  });

  describe('invalid quantities', () => {
    it.each([
      ['negative', { stockQuantity: -1 }],
      ['fractional', { stockQuantity: 10.5 }],
      ['off the granularity', { stockQuantity: 15 }],
      ['above the ceiling', { stockQuantity: 10_000_010 }],
      ['null while tracked', { stockQuantity: null }],
      [
        'a quantity while turning tracking off',
        { trackStock: false, stockQuantity: 500 },
      ],
    ])('rejects %s', async (_label, body) => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });

      await patch(owner, created.id, {
        ...body,
        expectedStockQuantity: 20_000,
      }).expect(400);

      expect((await stockOf(owner, created.id)).stockQuantity).toBe(20_000);
    });

    it('rejects tracking without a quantity on an untracked product', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');
      await patch(owner, created.id, {
        trackStock: true,
        expectedStockQuantity: null,
      }).expect(400);
    });
  });

  describe('expectedStockQuantity', () => {
    it('is required whenever stock is touched', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });

      for (const body of [
        { stockQuantity: 100 },
        { trackStock: false },
        { trackStock: true, stockQuantity: 100 },
      ]) {
        const response = await patch(owner, created.id, body).expect(400);
        expect(response.body.message).toContain('expectedStockQuantity');
      }
      expect((await stockOf(owner, created.id)).stockQuantity).toBe(20_000);
    });

    it('is refused when stock is not touched', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');
      await patch(owner, created.id, {
        priceMillimes: 4700,
        expectedStockQuantity: null,
      }).expect(400);
    });

    it('is not needed for price and rule edits', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });
      await patch(owner, created.id, { priceMillimes: 4700 }).expect(200);
    });

    it('answers 409 STOCK_CHANGED with the current stock, and applies nothing', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });
      // An order (or another device) takes 2.5 kg after the owner loaded the screen.
      await db.orm.public.StoreProduct.where({ id: created.id }).update({
        stockQuantity: 17_500,
      });

      const response = await patch(owner, created.id, {
        priceMillimes: 9999, // must not be applied either
        stockQuantity: 25_000,
        expectedStockQuantity: 20_000,
      }).expect(409);

      expect(response.body).toEqual({
        statusCode: 409,
        error: 'Conflict',
        code: 'STOCK_CHANGED',
        message: 'Stock changed since it was loaded',
        currentStockQuantity: 17_500,
      });
      const after = await stockOf(owner, created.id);
      expect(after.stockQuantity).toBe(17_500);
      expect(after.priceMillimes).toBe(created.priceMillimes);
    });

    it('answers 409 when tracking was switched on meanwhile', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane');
      await db.orm.public.StoreProduct.where({ id: created.id }).update({
        trackStock: true,
        stockQuantity: 5000,
      });

      const response = await patch(owner, created.id, {
        trackStock: true,
        stockQuantity: 20_000,
        expectedStockQuantity: null,
      }).expect(409);

      expect(response.body.currentStockQuantity).toBe(5000);
    });

    it('lets only one of two simultaneous counts win', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 20_000,
      });

      const results = await Promise.all(
        [1000, 2000].map((stockQuantity) =>
          patch(owner, created.id, {
            stockQuantity,
            expectedStockQuantity: 20_000,
          }),
        ),
      );

      expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
        200, 409,
      ]);
      const winner = results.find((r) => r.status === 200)!;
      expect((await stockOf(owner, created.id)).stockQuantity).toBe(
        winner.body.stockQuantity,
      );
    });
  });

  describe('automatic customer availability', () => {
    it('stops being orderable when stock reaches zero, without touching the switch, and comes back on restock', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 500,
      });
      expect(created.isOrderable).toBe(true);

      const empty = await patch(owner, created.id, {
        stockQuantity: 0,
        expectedStockQuantity: 500,
      }).expect(200);
      expect(empty.body).toMatchObject({
        stockQuantity: 0,
        isAvailable: true, // the owner never switched it off
        isOrderable: false,
        unavailabilityReason: 'OUT_OF_STOCK',
      });

      const restocked = await patch(owner, created.id, {
        stockQuantity: 3000,
        expectedStockQuantity: 0,
      }).expect(200);
      expect(restocked.body).toMatchObject({
        isAvailable: true,
        isOrderable: true,
        unavailabilityReason: null,
      });
    });

    it('is also reflected when an order drains the stock behind the API', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 500,
      });
      await db.orm.public.StoreProduct.where({ id: created.id }).update({
        stockQuantity: 0,
      });

      const body = await stockOf(owner, created.id);

      expect(body).toMatchObject({
        isOrderable: false,
        unavailabilityReason: 'OUT_OF_STOCK',
      });
      const list = await request(http()).get(API).set(auth(owner)).expect(200);
      expect(list.body[0].isOrderable).toBe(false);
    });

    it('treats stock below the minimum order as unorderable', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 50,
      });
      expect(created).toMatchObject({
        isOrderable: false,
        unavailabilityReason: 'STOCK_BELOW_MINIMUM',
      });

      const enough = await patch(owner, created.id, {
        stockQuantity: 100,
        expectedStockQuantity: 50,
      }).expect(200);
      expect(enough.body.isOrderable).toBe(true);
    });

    it.each([
      ['stock 500, min 100', { trackStock: true, stockQuantity: 500 }, true],
      ['stock 50, min 100', { trackStock: true, stockQuantity: 50 }, false],
      ['stock 0', { trackStock: true, stockQuantity: 0 }, false],
      ['untracked', {}, true],
    ])('%s → orderable: %s', async (_label, body, expected) => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', body);
      expect(created.isOrderable).toBe(expected);
    });

    it('keeps the owner’s switch independent of stock', async () => {
      const owner = await freshOwner();
      const created = await added(owner, 'banane', {
        trackStock: true,
        stockQuantity: 5000,
      });

      const off = await request(http())
        .patch(`${API}/${created.id}/availability`)
        .set(auth(owner))
        .send({ isAvailable: false })
        .expect(200);
      expect(off.body).toMatchObject({
        isOrderable: false,
        unavailabilityReason: 'OWNER_DISABLED',
        stockQuantity: 5000,
      });

      const on = await request(http())
        .patch(`${API}/${created.id}/availability`)
        .set(auth(owner))
        .send({ isAvailable: true })
        .expect(200);
      expect(on.body).toMatchObject({ isOrderable: true, stockQuantity: 5000 });
    });
  });
});

describe('PATCH /owner/store-products/:id/availability', () => {
  it('switches a product off and on', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');

    const off = await request(http())
      .patch(`${API}/${created.id}/availability`)
      .set(auth(owner))
      .send({ isAvailable: false })
      .expect(200);
    expect(off.body).toMatchObject({ isAvailable: false, isOrderable: false });

    const on = await request(http())
      .patch(`${API}/${created.id}/availability`)
      .set(auth(owner))
      .send({ isAvailable: true })
      .expect(200);
    expect(on.body).toMatchObject({ isAvailable: true, isOrderable: true });
  });

  it('rejects a non-boolean and an archived product', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    await request(http())
      .patch(`${API}/${created.id}/availability`)
      .set(auth(owner))
      .send({ isAvailable: 'yes' })
      .expect(400);

    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);
    await request(http())
      .patch(`${API}/${created.id}/availability`)
      .set(auth(owner))
      .send({ isAvailable: false })
      .expect(409);
  });
});

describe('archive and restore', () => {
  it('DELETE archives instead of deleting, and is idempotent', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');

    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);
    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);

    const row = await db.orm.public.StoreProduct.first({ id: created.id });
    expect(row).not.toBeNull();
    expect(row?.archivedAt).not.toBeNull();
    const body = (await get(owner, created.id).expect(200)).body;
    expect(body).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'ARCHIVED',
    });
    const list = await request(http()).get(API).set(auth(owner)).expect(200);
    expect(list.body).toEqual([]);
  });

  it('restores an archived product exactly as it was left', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane', {
      priceMillimes: 4700,
      trackStock: true,
      stockQuantity: 3000,
      minQuantity: 250,
      quantityStep: 250,
    });
    await request(http())
      .delete(`${API}/${created.id}`)
      .set(auth(owner))
      .expect(204);

    const response = await request(http())
      .post(`${API}/${created.id}/restore`)
      .set(auth(owner))
      .expect(200);

    expect(response.body).toMatchObject({
      id: created.id,
      archivedAt: null,
      priceMillimes: 4700,
      trackStock: true,
      stockQuantity: 3000,
      minQuantity: 250,
      quantityStep: 250,
      isOrderable: true,
    });
    const list = await request(http()).get(API).set(auth(owner)).expect(200);
    expect(list.body).toHaveLength(1);
  });

  it('restore is idempotent and a 404 for a missing product', async () => {
    const owner = await freshOwner();
    const created = await added(owner, 'banane');
    await request(http())
      .post(`${API}/${created.id}/restore`)
      .set(auth(owner))
      .expect(200);
    await request(http())
      .post(`${API}/2147000000/restore`)
      .set(auth(owner))
      .expect(404);
  });
});

describe('the catalog changing under a store product', () => {
  it('makes it unorderable — never deletes it — when the product is archived in the catalog', async () => {
    const localTag = `${tag}cp`;
    const local = await seedCatalog(localTag);
    const owner = await freshOwner();
    const created = (
      await request(http())
        .post(API)
        .set(auth(owner))
        .send({
          productId: local.productId('banane'),
          priceMillimes: 4500,
          trackStock: true,
          stockQuantity: 5000,
        })
        .expect(201)
    ).body;

    await archiveProduct(local.productId('banane'));

    const body = (await get(owner, created.id).expect(200)).body;
    expect(body).toMatchObject({
      priceMillimes: 4500,
      stockQuantity: 5000,
      isAvailable: true,
      isOrderable: false,
      unavailabilityReason: 'CATALOG_ARCHIVED',
    });
    expect(body.product.isActive).toBe(false);
    const list = await request(http()).get(API).set(auth(owner)).expect(200);
    expect(list.body).toHaveLength(1); // still in the owner's domain
    await stopOwnerOffering(created.id);
    await removeCatalog(localTag);
  });

  it('makes it unorderable when its category is archived in the catalog', async () => {
    const localTag = `${tag}cc`;
    const local = await seedCatalog(localTag);
    const owner = await freshOwner();
    const created = (
      await request(http())
        .post(API)
        .set(auth(owner))
        .send({ productId: local.productId('yaourt'), priceMillimes: 500 })
        .expect(201)
    ).body;

    await archiveCategory(local.categoryId('laitiers'));

    const body = (await get(owner, created.id).expect(200)).body;
    expect(body).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'CATALOG_ARCHIVED',
    });
    expect(body.category.isActive).toBe(false);
    await stopOwnerOffering(created.id);
    await removeCatalog(localTag);
  });
});

/** Local catalogs are removed mid-suite, so their offerings must go first. */
async function stopOwnerOffering(id: number) {
  await db.orm.public.StoreProduct.select('id').where({ id }).delete();
}
