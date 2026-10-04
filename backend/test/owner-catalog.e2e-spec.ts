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
} from './support.js';

/** The global catalog as owners see it: browsable, searchable, and read-only. */

const tag = `e2ecat${Date.now()}`;
let catalog: Awaited<ReturnType<typeof seedCatalog>>;

beforeAll(async () => {
  await startApp();
  catalog = await seedCatalog(tag);
});

afterAll(async () => {
  await stopApp();
  await removeCatalog(tag);
});

interface Row {
  slug: string;
  [key: string]: unknown;
}
const mine = (rows: Row[]) =>
  rows.filter((row) => row.slug.startsWith(`${tag}-`));

describe('authentication and authorization', () => {
  it('requires a token', async () => {
    await request(http()).get('/owner/catalog/categories').expect(401);
    await request(http()).get('/owner/catalog/products').expect(401);
  });

  it('is for owners only', async () => {
    const client = await register('CLIENT');
    await request(http())
      .get('/owner/catalog/categories')
      .set(auth(client))
      .expect(403);
    await request(http())
      .get('/owner/catalog/products')
      .set(auth(client))
      .expect(403);
  });

  it('lets an owner without a store browse categories but needs a store for products', async () => {
    const owner = await register('OWNER');
    await request(http())
      .get('/owner/catalog/categories')
      .set(auth(owner))
      .expect(200);
    await request(http())
      .get('/owner/catalog/products')
      .set(auth(owner))
      .expect(404);
  });
});

describe('GET /owner/catalog/categories', () => {
  it('lists active categories with their product counts, sorted by name', async () => {
    const { owner } = await registerOwnerWithStore();

    const response = await request(http())
      .get('/owner/catalog/categories')
      .set(auth(owner))
      .expect(200);

    const categories = mine(response.body);
    expect(categories.map((c) => c.name)).toEqual([
      `Fruits ${tag}`,
      `Produits laitiers ${tag}`,
    ]);
    expect(categories[0]).toEqual({
      id: catalog.categoryId('fruits'),
      slug: `${tag}-fruits`,
      name: `Fruits ${tag}`,
      description: null,
      photo: null,
      productCount: 1,
    });
    expect(categories[1].productCount).toBe(2);
  });
});

describe('GET /owner/catalog/products', () => {
  it('returns what the picker needs', async () => {
    const { owner } = await registerOwnerWithStore();
    await db.orm.public.Product.where({
      id: catalog.productId('banane'),
    }).update({
      description: 'Jaune et sucrée',
      photo: 'https://cdn.example.com/banane.jpg',
    });

    const response = await request(http())
      .get('/owner/catalog/products')
      .set(auth(owner))
      .expect(200);

    const products = mine(response.body);
    expect(products.map((p) => p.slug)).toEqual([
      `${tag}-banane`,
      `${tag}-lait-delice-1l`,
      `${tag}-yaourt`,
    ]);
    expect(products[0]).toEqual({
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
      category: {
        id: catalog.categoryId('fruits'),
        slug: `${tag}-fruits`,
        name: `Fruits ${tag}`,
      },
      inMyStore: false,
      storeProductId: null,
      storeProductArchived: false,
    });
    expect(products[1].allowedSaleUnits).toEqual(['PIECE']);
  });

  it('filters by category', async () => {
    const { owner } = await registerOwnerWithStore();

    const response = await request(http())
      .get(
        `/owner/catalog/products?categoryId=${catalog.categoryId('laitiers')}`,
      )
      .set(auth(owner))
      .expect(200);

    expect(response.body.map((p: { slug: string }) => p.slug)).toEqual([
      `${tag}-lait-delice-1l`,
      `${tag}-yaourt`,
    ]);
  });

  it('rejects a malformed filter', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .get('/owner/catalog/products?categoryId=abc')
      .set(auth(owner))
      .expect(400);
  });

  describe('inMyStore', () => {
    const add = (owner: Parameters<typeof auth>[0], slug: string) =>
      request(http())
        .post('/owner/store-products')
        .set(auth(owner))
        .send({ productId: catalog.productId(slug), priceMillimes: 4500 })
        .expect(201);
    const flagsOf = async (owner: Parameters<typeof auth>[0], slug: string) => {
      const response = await request(http())
        .get('/owner/catalog/products')
        .set(auth(owner))
        .expect(200);
      const row = response.body.find(
        (p: { slug: string }) => p.slug === `${tag}-${slug}`,
      );
      return {
        inMyStore: row.inMyStore,
        storeProductId: row.storeProductId,
        storeProductArchived: row.storeProductArchived,
      };
    };

    it('follows the store product through add, archive and restore — per store', async () => {
      const a = await registerOwnerWithStore();
      const b = await registerOwnerWithStore();
      expect(await flagsOf(a.owner, 'yaourt')).toEqual({
        inMyStore: false,
        storeProductId: null,
        storeProductArchived: false,
      });

      const created = await add(a.owner, 'yaourt');
      expect(await flagsOf(a.owner, 'yaourt')).toEqual({
        inMyStore: true,
        storeProductId: created.body.id,
        storeProductArchived: false,
      });
      // Another store is not affected.
      expect(await flagsOf(b.owner, 'yaourt')).toEqual({
        inMyStore: false,
        storeProductId: null,
        storeProductArchived: false,
      });

      await request(http())
        .delete(`/owner/store-products/${created.body.id}`)
        .set(auth(a.owner))
        .expect(204);
      expect(await flagsOf(a.owner, 'yaourt')).toEqual({
        inMyStore: false,
        storeProductId: created.body.id,
        storeProductArchived: true,
      });

      await request(http())
        .post(`/owner/store-products/${created.body.id}/restore`)
        .set(auth(a.owner))
        .expect(200);
      expect(await flagsOf(a.owner, 'yaourt')).toMatchObject({
        inMyStore: true,
        storeProductArchived: false,
      });
    });
  });

  it('hides archived products and products of archived categories', async () => {
    const localTag = `${tag}hide`;
    const local = await seedCatalog(localTag);
    const { owner } = await registerOwnerWithStore();
    await archiveProduct(local.productId('yaourt'));
    await archiveCategory(local.categoryId('fruits'));

    const response = await request(http())
      .get('/owner/catalog/products')
      .set(auth(owner))
      .expect(200);
    const slugs = response.body.map((p: { slug: string }) => p.slug);

    expect(slugs).toContain(`${localTag}-lait-delice-1l`);
    expect(slugs).not.toContain(`${localTag}-yaourt`); // archived product
    expect(slugs).not.toContain(`${localTag}-banane`); // its category is archived

    const categories = await request(http())
      .get('/owner/catalog/categories')
      .set(auth(owner))
      .expect(200);
    expect(categories.body.map((c: { slug: string }) => c.slug)).not.toContain(
      `${localTag}-fruits`,
    );
    await removeCatalog(localTag);
  });
});

describe('the global catalog is read-only through the API', () => {
  const writes: [string, string][] = [
    ['post', '/owner/catalog/categories'],
    ['post', '/owner/catalog/products'],
    ['put', '/owner/catalog/products/1'],
    ['patch', '/owner/catalog/products/1'],
    ['patch', '/owner/catalog/categories/1'],
    ['delete', '/owner/catalog/products/1'],
    ['delete', '/owner/catalog/categories/1'],
  ];

  it.each(writes)('%s %s does not exist', async (method, path) => {
    const { owner } = await registerOwnerWithStore();
    const send = (
      request(http()) as unknown as Record<string, (p: string) => request.Test>
    )[method]!(path);

    const response = await send
      .set(auth(owner))
      .send({ name: 'Hacked', slug: 'hacked' });

    expect(response.status).toBe(404);
  });

  it('leaves the catalog untouched after those attempts', async () => {
    const before = await db.orm.public.Product.where({
      id: catalog.productId('banane'),
    }).first();
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .patch(`/owner/catalog/products/${catalog.productId('banane')}`)
      .set(auth(owner))
      .send({ name: 'Hacked' });
    const after = await db.orm.public.Product.where({
      id: catalog.productId('banane'),
    }).first();
    expect(after).toEqual(before);
  });

  it('no longer exposes the per-store category CRUD', async () => {
    const { owner } = await registerOwnerWithStore();
    for (const [method, path] of [
      ['get', '/owner/categories'],
      ['post', '/owner/categories'],
      ['patch', '/owner/categories/1'],
      ['delete', '/owner/categories/1'],
      ['get', '/owner/products'],
    ] as const) {
      const response = await (
        request(http()) as unknown as Record<
          string,
          (p: string) => request.Test
        >
      )[method]!(path)
        .set(auth(owner))
        .send({});
      expect({ method, path, status: response.status }).toEqual({
        method,
        path,
        status: 404,
      });
    }
  });
});
