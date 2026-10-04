import { db } from '../src/prisma/db.js';
import { registerOwnerWithStore, startApp, stopApp } from './support.js';

/**
 * The global catalog foundation, tested at the database level (there are no
 * catalog routes yet): what the schema guarantees regardless of any service.
 * Global rows are shared, so every row this suite creates gets a unique slug
 * and is removed in `afterAll`.
 */

const tag = `e2e${Date.now()}`;
let counter = 0;
const slug = (label: string) => `${tag}-${label}-${(counter += 1)}`;

const categoryIds: number[] = [];
const productIds: number[] = [];
const offeringIds: number[] = [];

const makeCategory = async (overrides: Record<string, unknown> = {}) => {
  const label = slug('cat');
  const category = await db.orm.public.Category.create({
    slug: label,
    name: `Catégorie ${label}`,
    description: null,
    photo: null,
    archivedAt: null,
    ...overrides,
  });
  categoryIds.push(category.id);
  return category;
};

const makeProduct = async (
  categoryId: number,
  overrides: Record<string, unknown> = {},
) => {
  const label = slug('prod');
  const product = await db.orm.public.Product.create({
    slug: label,
    categoryId,
    name: `Produit ${label}`,
    description: null,
    photo: null,
    defaultSaleUnit: 'KG',
    defaultMinQuantity: 100,
    defaultQuantityStep: 100,
    defaultMaxQuantity: 10_000,
    archivedAt: null,
    ...overrides,
  });
  productIds.push(product.id);
  return product;
};

const offeringFields = {
  saleUnit: 'KG',
  priceMillimes: 4500,
  minQuantity: 100,
  quantityStep: 100,
  maxQuantity: 10_000,
  trackStock: false,
  stockQuantity: null,
  isAvailable: true,
  archivedAt: null,
} as const;

const makeOffering = async (
  storeId: number,
  productId: number,
  overrides: Record<string, unknown> = {},
) => {
  const offering = await db.orm.public.StoreProduct.create({
    storeId,
    productId,
    ...offeringFields,
    ...overrides,
  });
  offeringIds.push(offering.id);
  return offering;
};

/** The Postgres SQLSTATE a rejected write failed with. */
const failsWith = (sqlState: string) => ({ sqlState });
const UNIQUE = '23505';
const CHECK = '23514';
const FOREIGN_KEY = '23503';

let storeId: number;
let otherStoreId: number;

beforeAll(async () => {
  await startApp();
  storeId = (await registerOwnerWithStore()).store.id;
  otherStoreId = (await registerOwnerWithStore({ name: 'Autre magasin' })).store
    .id;
});

afterAll(async () => {
  for (const id of offeringIds) {
    await db.orm.public.StoreProduct.select('id').where({ id }).delete();
  }
  for (const id of productIds) {
    await db.orm.public.Product.select('id').where({ id }).delete();
  }
  for (const id of categoryIds) {
    await db.orm.public.Category.select('id').where({ id }).delete();
  }
  await stopApp();
});

describe('Category (global)', () => {
  it('belongs to no store', async () => {
    const category = await makeCategory();
    expect(category).not.toHaveProperty('storeId');
    expect(category.archivedAt).toBeNull();
  });

  it('has a unique slug', async () => {
    const category = await makeCategory();
    await expect(
      makeCategory({ slug: category.slug, name: 'Autre nom' }),
    ).rejects.toMatchObject(failsWith(UNIQUE));
  });

  it.each(['Bad Slug', 'bad--slug', '-leading', 'trailing-', 'ÉCOLE'])(
    'rejects the malformed slug %j',
    async (bad) => {
      await expect(makeCategory({ slug: bad })).rejects.toMatchObject(
        failsWith(CHECK),
      );
    },
  );

  it('keeps active names unique, ignoring case, and frees archived ones', async () => {
    const first = await makeCategory({ name: `Epicerie ${tag}` });
    await expect(
      makeCategory({ name: `epicerie ${tag}` }),
    ).rejects.toMatchObject(failsWith(UNIQUE));

    await db.orm.public.Category.where({ id: first.id }).update({
      archivedAt: new Date().toISOString(),
    });
    await expect(
      makeCategory({ name: `Epicerie ${tag}` }),
    ).resolves.toBeDefined();
  });

  it('rejects a blank name', async () => {
    await expect(makeCategory({ name: '   ' })).rejects.toMatchObject(
      failsWith(CHECK),
    );
  });
});

describe('Product (global)', () => {
  it('belongs to a category, not to a store', async () => {
    const category = await makeCategory();
    const product = await makeProduct(category.id);
    expect(product.categoryId).toBe(category.id);
    for (const storeField of [
      'storeId',
      'priceMillimes',
      'isAvailable',
      'trackStock',
      'stockQuantity',
    ]) {
      expect(product).not.toHaveProperty(storeField);
    }
  });

  it('requires an existing category', async () => {
    await expect(makeProduct(2_147_000_000)).rejects.toMatchObject(
      failsWith(FOREIGN_KEY),
    );
  });

  it('has a unique slug', async () => {
    const category = await makeCategory();
    const product = await makeProduct(category.id);
    await expect(
      makeProduct(category.id, { slug: product.slug, name: 'Autre' }),
    ).rejects.toMatchObject(failsWith(UNIQUE));
  });

  it('updates the same row when the name changes under the same slug', async () => {
    const category = await makeCategory();
    const product = await makeProduct(category.id, {
      name: `Lait Délice 1 L ${tag}`,
    });

    const renamed = await db.orm.public.Product.where({
      slug: product.slug,
    }).update({ name: `Lait Délice Entier 1 L ${tag}` });

    expect(renamed?.id).toBe(product.id);
    const rows = await db.orm.public.Product.where({
      slug: product.slug,
    }).all();
    expect(rows).toHaveLength(1);
    expect(rows[0]?.name).toBe(`Lait Délice Entier 1 L ${tag}`);
  });

  it('keeps active names unique, ignoring case, and frees archived ones', async () => {
    const category = await makeCategory();
    const first = await makeProduct(category.id, { name: `Tomate ${tag}` });
    await expect(
      makeProduct(category.id, { name: `TOMATE ${tag}` }),
    ).rejects.toMatchObject(failsWith(UNIQUE));

    await db.orm.public.Product.where({ id: first.id }).update({
      archivedAt: new Date().toISOString(),
    });
    await expect(
      makeProduct(category.id, { name: `Tomate ${tag}` }),
    ).resolves.toBeDefined();
  });

  it.each([
    [
      'a minimum that is not a multiple of the step',
      { defaultMinQuantity: 150 },
    ],
    ['a zero step', { defaultQuantityStep: 0, defaultMinQuantity: 100 }],
    ['a zero minimum', { defaultMinQuantity: 0 }],
    [
      'a maximum below the minimum',
      { defaultMaxQuantity: 100, defaultMinQuantity: 200 },
    ],
    ['a maximum off the step', { defaultMaxQuantity: 1050 }],
    ['a malformed slug', { slug: 'Not A Slug' }],
    ['a blank name', { name: '  ' }],
  ])('rejects %s', async (_label, overrides) => {
    const category = await makeCategory();
    await expect(makeProduct(category.id, overrides)).rejects.toMatchObject(
      failsWith(CHECK),
    );
  });

  it('refuses to delete a category that still has products', async () => {
    const category = await makeCategory();
    await makeProduct(category.id);
    await expect(
      db.orm.public.Category.select('id').where({ id: category.id }).delete(),
    ).rejects.toMatchObject(failsWith(FOREIGN_KEY));
  });
});

describe('StoreProduct', () => {
  it('records how one store sells one product', async () => {
    const product = await makeProduct((await makeCategory()).id);
    const offering = await makeOffering(storeId, product.id);
    expect(offering).toMatchObject({
      storeId,
      productId: product.id,
      saleUnit: 'KG',
      priceMillimes: 4500,
      trackStock: false,
      stockQuantity: null,
      isAvailable: true,
      archivedAt: null,
    });
  });

  it('allows one offering per store and product, but the same product in several stores', async () => {
    const product = await makeProduct((await makeCategory()).id);
    await makeOffering(storeId, product.id);
    await expect(makeOffering(storeId, product.id)).rejects.toMatchObject(
      failsWith(UNIQUE),
    );
    await expect(
      makeOffering(otherStoreId, product.id, { priceMillimes: 5000 }),
    ).resolves.toMatchObject({ priceMillimes: 5000 });
  });

  it('lets two stores configure the same product differently', async () => {
    const product = await makeProduct((await makeCategory()).id);
    const a = await makeOffering(storeId, product.id, {
      priceMillimes: 4500,
      minQuantity: 100,
      quantityStep: 100,
    });
    const b = await makeOffering(otherStoreId, product.id, {
      priceMillimes: 5000,
      minQuantity: 250,
      quantityStep: 250,
    });
    expect([a.priceMillimes, a.quantityStep]).toEqual([4500, 100]);
    expect([b.priceMillimes, b.quantityStep]).toEqual([5000, 250]);
  });

  describe('stock invariants', () => {
    it('needs a quantity while stock is tracked', async () => {
      const product = await makeProduct((await makeCategory()).id);
      await expect(
        makeOffering(storeId, product.id, { trackStock: true }),
      ).rejects.toMatchObject(failsWith(CHECK));
    });

    it('forbids a quantity while stock is not tracked', async () => {
      const product = await makeProduct((await makeCategory()).id);
      await expect(
        makeOffering(storeId, product.id, { stockQuantity: 500 }),
      ).rejects.toMatchObject(failsWith(CHECK));
    });

    it('rejects negative stock', async () => {
      const product = await makeProduct((await makeCategory()).id);
      await expect(
        makeOffering(storeId, product.id, {
          trackStock: true,
          stockQuantity: -1,
        }),
      ).rejects.toMatchObject(failsWith(CHECK));
    });

    it('accepts tracked stock, including an empty shelf', async () => {
      const category = await makeCategory();
      const withStock = await makeOffering(
        storeId,
        (await makeProduct(category.id)).id,
        { trackStock: true, stockQuantity: 20_000 },
      );
      const empty = await makeOffering(
        storeId,
        (await makeProduct(category.id)).id,
        { trackStock: true, stockQuantity: 0 },
      );
      expect(withStock.stockQuantity).toBe(20_000);
      expect(empty.stockQuantity).toBe(0);
    });

    it('cannot be switched off without clearing the quantity', async () => {
      const product = await makeProduct((await makeCategory()).id);
      const offering = await makeOffering(storeId, product.id, {
        trackStock: true,
        stockQuantity: 500,
      });
      await expect(
        db.orm.public.StoreProduct.where({ id: offering.id }).update({
          trackStock: false,
        }),
      ).rejects.toMatchObject(failsWith(CHECK));
    });
  });

  it.each([
    ['a zero price', { priceMillimes: 0 }],
    ['a negative price', { priceMillimes: -10 }],
    ['a minimum that is not a multiple of the step', { minQuantity: 150 }],
    ['a zero step', { quantityStep: 0 }],
    ['a maximum below the minimum', { maxQuantity: 50 }],
    ['a maximum off the step', { maxQuantity: 1050 }],
  ])('rejects %s', async (_label, overrides) => {
    const product = await makeProduct((await makeCategory()).id);
    await expect(
      makeOffering(storeId, product.id, overrides),
    ).rejects.toMatchObject(failsWith(CHECK));
  });

  describe('history is protected', () => {
    it('refuses to delete a product that a store sells', async () => {
      const product = await makeProduct((await makeCategory()).id);
      await makeOffering(storeId, product.id);
      await expect(
        db.orm.public.Product.select('id').where({ id: product.id }).delete(),
      ).rejects.toMatchObject(failsWith(FOREIGN_KEY));
    });

    it('refuses to delete a store that has offerings', async () => {
      const product = await makeProduct((await makeCategory()).id);
      await makeOffering(storeId, product.id);
      await expect(
        db.orm.public.Store.select('id').where({ id: storeId }).delete(),
      ).rejects.toMatchObject(failsWith(FOREIGN_KEY));
    });

    it('leaves an offering untouched when its product or category is archived or renamed', async () => {
      const category = await makeCategory();
      const product = await makeProduct(category.id);
      const offering = await makeOffering(storeId, product.id, {
        priceMillimes: 4700,
        trackStock: true,
        stockQuantity: 3000,
        isAvailable: false,
      });

      const now = new Date().toISOString();
      await db.orm.public.Product.where({ id: product.id }).update({
        name: `Renommé ${tag}`,
        archivedAt: now,
      });
      await db.orm.public.Category.where({ id: category.id }).update({
        archivedAt: now,
      });

      const after = await db.orm.public.StoreProduct.first({ id: offering.id });
      expect(after).toMatchObject({
        priceMillimes: 4700,
        saleUnit: 'KG',
        trackStock: true,
        stockQuantity: 3000,
        isAvailable: false,
        archivedAt: null,
      });
    });
  });
});
