import { formatReport, importCatalog } from '../src/catalog/catalog-import.js';
import { db } from '../src/prisma/db.js';
import { fixtureCatalog } from './catalog-fixture.js';
import { registerOwnerWithStore, startApp, stopApp } from './support.js';

/**
 * The importer against the real (test) database. Global rows are shared, so
 * every slug carries a per-run tag and `afterAll` removes what this suite made.
 */

const tag = `e2e${Date.now()}`;

const offeringIds: number[] = [];

const catalogRows = async () => ({
  brands: (await db.orm.public.Brand.all()).filter((b) =>
    b.slug.startsWith(tag),
  ),
  categories: (await db.orm.public.Category.all()).filter((c) =>
    c.slug.startsWith(tag),
  ),
  products: (await db.orm.public.Product.all()).filter((p) =>
    p.slug.startsWith(tag),
  ),
});

const run = (catalog: unknown, dryRun = false) =>
  importCatalog(catalog, { dryRun });

let storeId: number;

beforeAll(async () => {
  await startApp();
  storeId = (await registerOwnerWithStore()).store.id;
});

afterAll(async () => {
  for (const id of offeringIds) {
    await db.orm.public.StoreProduct.select('id').where({ id }).delete();
  }
  const { products, brands, categories } = await catalogRows();
  for (const { id } of products) {
    await db.orm.public.Product.select('id').where({ id }).delete();
  }
  for (const { id } of brands) {
    await db.orm.public.Brand.select('id').where({ id }).delete();
  }
  for (const { id } of categories) {
    await db.orm.public.Category.select('id').where({ id }).delete();
  }
  await stopApp();
});

/** Each test gets its own slice of the catalog so the order of tests doesn't matter. */
let testTag: string;
let n = 0;
let fixture: ReturnType<typeof fixtureCatalog>;
beforeEach(() => {
  n += 1;
  testTag = `${tag}t${n}`;
  fixture = fixtureCatalog(testTag);
});
const own = async () => {
  const { brands, categories, products } = await catalogRows();
  // The trailing hyphen keeps `...t1-` from also matching `...t10-`.
  return {
    brands: brands.filter((b) => b.slug.startsWith(`${testTag}-`)),
    categories: categories.filter((c) => c.slug.startsWith(`${testTag}-`)),
    products: products.filter((p) => p.slug.startsWith(`${testTag}-`)),
  };
};
const bySlug = async (value: string) =>
  db.orm.public.Product.first({ slug: `${testTag}-${value}` });

describe('importing a valid catalog', () => {
  it('creates the categories and products', async () => {
    const report = await run(fixture);

    expect(report.errors).toEqual([]);
    expect(report.categories).toMatchObject({ created: 2, unchanged: 0 });
    expect(report.products).toMatchObject({ created: 3, unchanged: 0 });
    const { categories, products } = await own();
    expect(categories).toHaveLength(2);
    expect(products).toHaveLength(3);

    const banana = await bySlug('banane');
    expect(banana).toMatchObject({
      defaultSaleUnit: 'KG',
      defaultMinQuantity: 100,
      defaultQuantityStep: 100,
      defaultMaxQuantity: 10_000,
      archivedAt: null,
    });
    const milk = await bySlug('lait-delice-1l');
    expect(milk).toMatchObject({
      defaultSaleUnit: 'PIECE',
      defaultMinQuantity: 1,
      defaultQuantityStep: 1,
      defaultMaxQuantity: null,
    });
    const fruits = categories.find((c) => c.slug === `${testTag}-fruits`);
    expect(banana?.categoryId).toBe(fruits?.id);
  });

  it('is idempotent: importing twice creates no duplicates', async () => {
    await run(fixture);
    const before = await own();

    const again = await run(fixture);

    expect(again.errors).toEqual([]);
    expect(again.categories).toEqual({
      created: 0,
      updated: 0,
      unchanged: 2,
      archived: 0,
    });
    expect(again.products).toEqual({
      created: 0,
      updated: 0,
      unchanged: 3,
      archived: 0,
    });
    const after = await own();
    expect(after.products.map((p) => p.id).sort((a, b) => a - b)).toEqual(
      before.products.map((p) => p.id).sort((a, b) => a - b),
    );
    expect(after.categories).toHaveLength(2);
  });
});

describe('renaming under the same slug', () => {
  it('updates the existing product instead of creating a second one', async () => {
    await run(fixture);
    const original = await bySlug('lait-delice-1l');

    fixture.categories[1]!.products[0]!.name = `Lait Délice Entier 1 L ${testTag}`;
    const report = await run(fixture);

    expect(report.products).toMatchObject({ created: 0, updated: 1 });
    const { products } = await own();
    expect(products).toHaveLength(3);
    const renamed = await bySlug('lait-delice-1l');
    expect(renamed?.id).toBe(original?.id);
    expect(renamed?.name).toBe(`Lait Délice Entier 1 L ${testTag}`);
    expect(
      products.filter((p) => p.name.startsWith('Lait Délice')),
    ).toHaveLength(1);
  });
});

describe('invalid files write nothing', () => {
  const rejected = async (mutate: (c: typeof fixture) => void) => {
    mutate(fixture);
    const report = await run(fixture);
    expect(report.errors.length).toBeGreaterThan(0);
    expect(report.categories.created + report.products.created).toBe(0);
    const { categories, products } = await own();
    expect(categories).toHaveLength(0);
    expect(products).toHaveLength(0);
    return report;
  };

  it('a duplicate slug', async () => {
    const report = await rejected((c) => {
      c.categories[1]!.products[0]!.slug = c.categories[0]!.products[0]!.slug;
    });
    expect(report.errors[0]).toContain('is already used by');
  });

  it('an invalid category', async () => {
    const report = await rejected((c) => {
      Object.assign(c.categories[0]!.products[0]!, {
        categorySlug: 'does-not-exist',
      });
    });
    expect(report.errors[0]).toContain('nested under');
  });

  it('an invalid quantity rule', async () => {
    const report = await rejected((c) => {
      Object.assign(c.categories[0]!.products[0]!, {
        defaultMinQuantity: 150,
        defaultQuantityStep: 100,
      });
    });
    expect(report.errors[0]).toContain(
      'defaultMinQuantity must be a multiple of defaultQuantityStep',
    );
  });

  it('an invalid unit', async () => {
    const report = await rejected((c) => {
      c.categories[0]!.products[0]!.defaultSaleUnit = 'LITRE';
    });
    expect(report.errors[0]).toContain('defaultSaleUnit: must be one of');
  });
});

describe('archiving', () => {
  it('archives instead of deleting, once, and can restore', async () => {
    await run(fixture);
    const yogurt = await bySlug('yaourt');

    Object.assign(fixture.categories[1]!.products[1]!, { archived: true });
    const archived = await run(fixture);
    expect(archived.products).toMatchObject({ archived: 1, unchanged: 2 });
    const row = await bySlug('yaourt');
    expect(row?.id).toBe(yogurt?.id);
    expect(row?.archivedAt).not.toBeNull();

    const repeated = await run(fixture);
    expect(repeated.products).toMatchObject({ archived: 0, unchanged: 3 });

    Object.assign(fixture.categories[1]!.products[1]!, { archived: false });
    const restored = await run(fixture);
    expect(restored.products).toMatchObject({ updated: 1, archived: 0 });
    expect((await bySlug('yaourt'))?.archivedAt).toBeNull();
  });

  it('never deletes what the file stops mentioning', async () => {
    await run(fixture);

    fixture.categories[1]!.products.pop();
    const report = await run(fixture);

    expect(report.warnings).toContainEqual(
      expect.stringContaining('not in the file and were left unchanged'),
    );
    expect((await own()).products).toHaveLength(3);
  });
});

describe('StoreProduct is never modified', () => {
  it('keeps price, unit, stock, availability and rules whatever the catalog changes', async () => {
    await run(fixture);
    const banana = (await bySlug('banane'))!;
    const offering = await db.orm.public.StoreProduct.create({
      storeId,
      productId: banana.id,
      saleUnit: 'PIECE',
      priceMillimes: 700,
      minQuantity: 2,
      quantityStep: 2,
      maxQuantity: 40,
      trackStock: true,
      stockQuantity: 36,
      isAvailable: false,
      archivedAt: null,
    });
    offeringIds.push(offering.id);

    // Change everything the catalog can change about the product — and archive it.
    Object.assign(fixture.categories[0]!.products[0]!, {
      name: `Banane plantain ${testTag}`,
      description: 'Autre description',
      photo: 'https://cdn.example.com/banane.jpg',
      defaultSaleUnit: 'PIECE',
      defaultMinQuantity: 3,
      defaultQuantityStep: 3,
      defaultMaxQuantity: 30,
      archived: true,
    });
    const [banane] = fixture.categories[0]!.products.splice(0, 1);
    fixture.categories[1]!.products.push(banane!); // and move it to another category
    const report = await run(fixture);

    expect(report.errors).toEqual([]);
    expect(report.products.archived).toBe(1);
    expect(report.warnings).toContainEqual(
      expect.stringContaining('1 store(s) still sell it'),
    );
    const changed = (await bySlug('banane'))!;
    expect(changed).toMatchObject({
      name: `Banane plantain ${testTag}`,
      defaultSaleUnit: 'PIECE',
      defaultMinQuantity: 3,
    });
    expect(changed.categoryId).not.toBe(banana.categoryId);
    expect(changed.archivedAt).not.toBeNull();

    // The offering is byte-for-byte what it was — even `updatedAt` did not move.
    const after = await db.orm.public.StoreProduct.first({ id: offering.id });
    expect(after).toEqual(offering);
  });
});

describe('dry run', () => {
  it('reports what would happen on an empty catalog and writes nothing', async () => {
    const report = await run(fixture, true);

    expect(report.dryRun).toBe(true);
    expect(report.errors).toEqual([]);
    expect(report.categories.created).toBe(2);
    expect(report.products.created).toBe(3);
    const { categories, products } = await own();
    expect(categories).toHaveLength(0);
    expect(products).toHaveLength(0);
  });

  it('reports planned updates and archives without applying them', async () => {
    await run(fixture);
    const snapshot = await own();

    fixture.categories[1]!.products[0]!.name = `Lait Délice Entier 1 L ${testTag}`;
    Object.assign(fixture.categories[1]!.products[1]!, { archived: true });
    fixture.categories[0]!.products.push({
      slug: `${testTag}-orange`,
      name: `Orange ${testTag}`,
      defaultSaleUnit: 'KG',
      defaultMinQuantity: 100,
      defaultQuantityStep: 100,
      defaultMaxQuantity: 10_000,
    });
    const report = await run(fixture, true);

    expect(report.products).toEqual({
      created: 1,
      updated: 1,
      unchanged: 1,
      archived: 1,
    });
    const after = await own();
    expect(after.products).toEqual(snapshot.products);
    expect(after.categories).toEqual(snapshot.categories);
  });

  it('still reports validation errors', async () => {
    fixture.categories[0]!.products[0]!.defaultSaleUnit = 'LITRE';

    const report = await run(fixture, true);

    expect(report.errors.length).toBeGreaterThan(0);
  });
});

describe('transaction', () => {
  it('rolls everything back when a write fails part-way', async () => {
    await run(fixture);
    const before = await own();

    // Two products swapping names is valid in the end but not one write at a
    // time (active names are unique), so the database rejects the second write.
    // A new category is written first — it must not survive.
    const [fruits, dairy] = fixture.categories;
    const banana = fruits!.products[0]!;
    const milk = dairy!.products[0]!;
    [banana.name, milk.name] = [milk.name, banana.name];
    fixture.categories.push({
      slug: `${testTag}-epicerie`,
      name: `Épicerie ${testTag}`,
      products: [],
    });

    const report = await run(fixture);

    expect(report.errors).toEqual([
      expect.stringContaining('Nothing was written'),
    ]);
    const after = await own();
    expect(after.categories).toEqual(before.categories);
    expect(after.products).toEqual(before.products);
    expect(after.categories.map((c) => c.slug)).not.toContain(
      `${testTag}-epicerie`,
    );
  });
});

describe('brands', () => {
  /** The fixture plus two brands and three "Ketchup" products (Heinz, Amora, none). */
  const withKetchups = () => {
    fixture.brands = [
      { slug: `${testTag}-heinz`, name: `Heinz ${testTag}` },
      { slug: `${testTag}-amora`, name: `Amora ${testTag}` },
    ];
    fixture.categories[1]!.products.push(
      {
        slug: `${testTag}-ketchup-heinz`,
        name: `Ketchup ${testTag}`,
        brandSlug: `${testTag}-heinz`,
        defaultSaleUnit: 'PIECE',
      },
      {
        slug: `${testTag}-ketchup-amora`,
        name: `Ketchup ${testTag}`,
        brandSlug: `${testTag}-amora`,
        defaultSaleUnit: 'PIECE',
      },
      {
        slug: `${testTag}-ketchup`,
        name: `Ketchup ${testTag}`,
        defaultSaleUnit: 'PIECE',
      },
    );
    return fixture;
  };
  const brandOf = async (value: string) => {
    const product = await bySlug(value);
    if (product?.brandId == null) return null;
    return (await db.orm.public.Brand.first({ id: product.brandId }))?.slug;
  };

  it('creates the brands and resolves each product’s brand from its slug', async () => {
    const report = await run(withKetchups());

    expect(report.errors).toEqual([]);
    expect(report.brands).toEqual({
      created: 2,
      updated: 0,
      unchanged: 0,
      archived: 0,
    });
    expect(report.products).toMatchObject({ created: 6 });
    expect((await own()).brands.map((b) => b.name).sort()).toEqual([
      `Amora ${testTag}`,
      `Heinz ${testTag}`,
    ]);
    expect(await brandOf('ketchup-heinz')).toBe(`${testTag}-heinz`);
    expect(await brandOf('ketchup-amora')).toBe(`${testTag}-amora`);
    expect(await brandOf('ketchup')).toBeNull();
    expect(await brandOf('banane')).toBeNull();
  });

  it('is idempotent: importing twice creates no duplicate brand or product', async () => {
    await run(withKetchups());
    const before = await own();

    const again = await run(fixture);

    expect(again.errors).toEqual([]);
    expect(again.brands).toEqual({
      created: 0,
      updated: 0,
      unchanged: 2,
      archived: 0,
    });
    expect(again.products).toMatchObject({ created: 0, updated: 0 });
    const after = await own();
    expect(after.brands).toEqual(before.brands);
    expect(after.products).toEqual(before.products);
  });

  it('adds a brand to a product that already exists without changing its identity', async () => {
    await run(fixture);
    const before = await bySlug('banane');

    fixture.brands = [
      { slug: `${testTag}-del-monte`, name: `Del Monte ${testTag}` },
    ];
    fixture.categories[0]!.products[0]!['brandSlug'] = `${testTag}-del-monte`;
    const report = await run(fixture);

    expect(report.errors).toEqual([]);
    expect(report.brands).toMatchObject({ created: 1 });
    expect(report.products).toMatchObject({ created: 0, updated: 1 });
    const after = await bySlug('banane');
    expect(after).toMatchObject({ id: before!.id, slug: before!.slug });
    expect(after!.name).toBe(before!.name);
    expect(await brandOf('banane')).toBe(`${testTag}-del-monte`);
    expect((await own()).products).toHaveLength(3);
  });

  it('changes a brand, removes it, and renames a brand under the same slug', async () => {
    await run(withKetchups());

    const changed = structuredClone(fixture);
    changed.brands![0]!.name = `Heinz France ${testTag}`;
    const products = changed.categories[1]!.products;
    const heinz = products.find(
      (p) => p['slug'] === `${testTag}-ketchup-heinz`,
    )!;
    const plain = products.find((p) => p['slug'] === `${testTag}-ketchup`)!;
    heinz['name'] = `Ketchup nature ${testTag}`; // keeps the name unique once brandless
    delete heinz['brandSlug'];
    plain['brandSlug'] = `${testTag}-amora`;
    plain['name'] = `Ketchup bio ${testTag}`;

    const report = await run(changed);

    expect(report.errors).toEqual([]);
    expect(report.brands).toMatchObject({
      created: 0,
      updated: 1,
      unchanged: 1,
    });
    expect(await brandOf('ketchup-heinz')).toBeNull();
    expect(await brandOf('ketchup')).toBe(`${testTag}-amora`);
    expect(
      (await db.orm.public.Brand.first({ slug: `${testTag}-heinz` }))?.name,
    ).toBe(`Heinz France ${testTag}`);
  });

  it('never touches the store products when a brand changes', async () => {
    await run(withKetchups());
    const product = await bySlug('ketchup');
    const offering = await db.orm.public.StoreProduct.create({
      storeId,
      productId: product!.id,
      saleUnit: 'PIECE',
      priceMillimes: 3200,
      minQuantity: 2,
      quantityStep: 1,
      maxQuantity: 12,
      trackStock: true,
      stockQuantity: 7,
      isAvailable: false,
      archivedAt: null,
    });
    offeringIds.push(offering.id);

    const changed = structuredClone(fixture);
    changed.categories[1]!.products.find(
      (p) => p['slug'] === `${testTag}-ketchup`,
    )!['brandSlug'] = `${testTag}-heinz`;
    changed.categories[1]!.products.find(
      (p) => p['slug'] === `${testTag}-ketchup`,
    )!['name'] = `Ketchup maison ${testTag}`;
    expect((await run(changed)).errors).toEqual([]);

    const after = await db.orm.public.StoreProduct.first({ id: offering.id });
    expect(after).toMatchObject({
      priceMillimes: 3200,
      minQuantity: 2,
      maxQuantity: 12,
      trackStock: true,
      stockQuantity: 7,
      isAvailable: false,
    });
  });

  describe('invalid files write nothing', () => {
    const nothingWritten = async () => {
      const after = await own();
      expect(after.brands).toEqual([]);
      expect(after.products).toEqual([]);
    };

    it('an unknown brand reference', async () => {
      fixture.categories[0]!.products[0]!['brandSlug'] = `${testTag}-inconnue`;
      fixture.brands = [{ slug: `${testTag}-heinz`, name: `Heinz ${testTag}` }];
      const report = await run(fixture);
      expect(report.errors).toEqual([expect.stringContaining('unknown brand')]);
      await nothingWritten();
    });

    it('a duplicate brand slug', async () => {
      fixture.brands = [
        { slug: `${testTag}-heinz`, name: `Heinz ${testTag}` },
        { slug: `${testTag}-heinz`, name: `Amora ${testTag}` },
      ];
      const report = await run(fixture);
      expect(report.errors).toEqual([expect.stringContaining('already used')]);
      await nothingWritten();
    });

    it('a duplicate brand name in another case', async () => {
      fixture.brands = [
        { slug: `${testTag}-heinz`, name: `Heinz ${testTag}` },
        { slug: `${testTag}-heinz-2`, name: `HEINZ ${testTag}` },
      ];
      const report = await run(fixture);
      expect(report.errors).toEqual([expect.stringContaining('already used')]);
      await nothingWritten();
    });

    it('an invalid brand slug', async () => {
      fixture.brands = [{ slug: 'Heinz Co', name: `Heinz ${testTag}` }];
      const report = await run(fixture);
      expect(report.errors).toEqual([
        expect.stringContaining('must be lowercase'),
      ]);
      await nothingWritten();
    });

    it('the same active name twice under one brand, or twice brandless', async () => {
      withKetchups();
      fixture.categories[1]!.products.push({
        slug: `${testTag}-ketchup-heinz-2`,
        name: `Ketchup ${testTag}`,
        brandSlug: `${testTag}-heinz`,
        defaultSaleUnit: 'PIECE',
      });
      expect((await run(fixture)).errors).toEqual([
        expect.stringContaining('of brand'),
      ]);
      await nothingWritten();
    });
  });

  it('rolls the brands back too when a write fails part-way', async () => {
    await run(fixture);
    const before = await own();

    // A new brand is written first; two products swapping names then fails.
    fixture.brands = [{ slug: `${testTag}-heinz`, name: `Heinz ${testTag}` }];
    const [fruits, dairy] = fixture.categories;
    const banana = fruits!.products[0]!;
    const milk = dairy!.products[0]!;
    [banana['name'], milk['name']] = [milk['name'], banana['name']];

    const report = await run(fixture);

    expect(report.errors).toEqual([
      expect.stringContaining('Nothing was written'),
    ]);
    const after = await own();
    expect(after.brands).toEqual(before.brands);
    expect(after.products).toEqual(before.products);
  });

  it('shows the brands in a dry run and writes none', async () => {
    withKetchups();
    const dry = await run(fixture, true);

    expect(dry.errors).toEqual([]);
    expect(dry.brands).toMatchObject({ created: 2 });
    expect(dry.products).toMatchObject({ created: 6 });
    expect((await own()).brands).toEqual([]);
    const text = formatReport(dry, { database: 'test', file: 'catalog.json' });
    expect(text).toContain('Brands:     created 2, updated 0, unchanged 0');
    expect(text).toContain('DRY RUN');

    await run(fixture);
    const again = await run(fixture, true);
    expect(
      formatReport(again, { database: 'test', file: 'catalog.json' }),
    ).toContain('Brands:     created 0, updated 0, unchanged 2');
  });
});
