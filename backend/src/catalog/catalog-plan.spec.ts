import { fixtureCatalog } from '../../test/catalog-fixture.js';
import { parseCatalog, type Catalog } from './catalog-file.js';
import {
  planCatalog,
  type ExistingCatalog,
  type ExistingOffering,
} from './catalog-plan.js';
import { SaleUnit } from '../products/sale-unit.enum.js';

const NOW = '2026-10-03T12:00:00.000Z';
const EARLIER = '2026-09-01T08:00:00.000Z';

const parse = (input: unknown): Catalog => {
  const { catalog, errors } = parseCatalog(input);
  expect(errors).toEqual([]);
  return catalog!;
};

/** What the database would hold after importing `catalog`. */
function stored(
  catalog: Catalog,
  offerings: ExistingOffering[] = [],
): ExistingCatalog {
  let productId = 100;
  const brands = catalog.brands.map((brand, index) => ({
    id: index + 500,
    slug: brand.slug,
    name: brand.name,
  }));
  const categories = catalog.categories.map((category, index) => ({
    id: index + 1,
    slug: category.slug,
    name: category.name,
    description: category.description,
    photo: category.photo,
    archivedAt: category.archived ? EARLIER : null,
  }));
  const products = catalog.categories.flatMap((category, index) =>
    category.products.map((product) => ({
      id: (productId += 1),
      slug: product.slug,
      categoryId: index + 1,
      brandId: brands.find((b) => b.slug === product.brandSlug)?.id ?? null,
      name: product.name,
      description: product.description,
      photo: product.photo,
      defaultSaleUnit: product.defaultSaleUnit,
      defaultMinQuantity: product.defaultMinQuantity,
      defaultQuantityStep: product.defaultQuantityStep,
      defaultMaxQuantity: product.defaultMaxQuantity,
      archivedAt: product.archived ? EARLIER : null,
    })),
  );
  return { brands, categories, products, offerings };
}

const empty: ExistingCatalog = {
  brands: [],
  categories: [],
  products: [],
  offerings: [],
};

describe('planCatalog', () => {
  it('creates everything when the database is empty', () => {
    const plan = planCatalog(parse(fixtureCatalog()), empty, NOW);

    expect(plan.errors).toEqual([]);
    expect(plan.categoryCounts).toEqual({
      created: 2,
      updated: 0,
      unchanged: 0,
      archived: 0,
    });
    expect(plan.productCounts).toEqual({
      created: 3,
      updated: 0,
      unchanged: 0,
      archived: 0,
    });
    const banana = plan.products.find((p) => p.slug === 'banane')!;
    expect(banana.categorySlug).toBe('fruits');
    expect(banana.create).toMatchObject({
      name: 'Banane',
      defaultSaleUnit: 'KG',
      archivedAt: null,
    });
  });

  it('plans nothing when the database already matches (idempotent)', () => {
    const catalog = parse(fixtureCatalog());

    const plan = planCatalog(catalog, stored(catalog), NOW);

    expect(plan.categoryCounts).toEqual({
      created: 0,
      updated: 0,
      unchanged: 2,
      archived: 0,
    });
    expect(plan.productCounts).toEqual({
      created: 0,
      updated: 0,
      unchanged: 3,
      archived: 0,
    });
    expect(plan.warnings).toEqual([]);
  });

  it('updates the existing product when the name changes under the same slug', () => {
    const before = parse(fixtureCatalog());
    const existing = stored(before);
    const renamed = fixtureCatalog();
    renamed.categories[1]!.products[0]!.name = 'Lait Délice Entier 1 L';

    const plan = planCatalog(parse(renamed), existing, NOW);

    expect(plan.productCounts).toMatchObject({ created: 0, updated: 1 });
    const action = plan.products.find((p) => p.slug === 'lait-delice-1l')!;
    expect(action).toMatchObject({
      kind: 'update',
      id: existing.products.find((p) => p.slug === 'lait-delice-1l')!.id,
      changes: { name: 'Lait Délice Entier 1 L' },
    });
    expect(action.create).toBeUndefined();
  });

  it('writes only the columns that changed', () => {
    const existing = stored(parse(fixtureCatalog()));
    const changed = fixtureCatalog();
    Object.assign(changed.categories[0]!.products[0]!, {
      description: 'Jaune',
      defaultMaxQuantity: 5000,
    });

    const plan = planCatalog(parse(changed), existing, NOW);

    expect(plan.products.find((p) => p.slug === 'banane')!.changes).toEqual({
      description: 'Jaune',
      defaultMaxQuantity: 5000,
    });
  });

  it('archives instead of deleting, and only once', () => {
    const existing = stored(parse(fixtureCatalog()));
    const archived = fixtureCatalog();
    Object.assign(archived.categories[1]!.products[1]!, { archived: true });

    const first = planCatalog(parse(archived), existing, NOW);
    expect(first.productCounts).toMatchObject({ archived: 1, unchanged: 2 });
    expect(first.products.find((p) => p.slug === 'yaourt')).toMatchObject({
      kind: 'archive',
      changes: { archivedAt: NOW },
    });

    const second = planCatalog(parse(archived), stored(parse(archived)), NOW);
    expect(second.productCounts).toMatchObject({ archived: 0, unchanged: 3 });
  });

  it('restores an archived entry when the file no longer archives it', () => {
    const archived = fixtureCatalog();
    Object.assign(archived.categories[0]!.products[0]!, { archived: true });
    const existing = stored(parse(archived));

    const plan = planCatalog(parse(fixtureCatalog()), existing, NOW);

    expect(plan.products.find((p) => p.slug === 'banane')).toMatchObject({
      kind: 'update',
      changes: { archivedAt: null },
    });
  });

  it('moves a product to another category', () => {
    const existing = stored(parse(fixtureCatalog()));
    const moved = fixtureCatalog();
    const [banana] = moved.categories[0]!.products.splice(0, 1);
    moved.categories[1]!.products.push(banana!);

    const plan = planCatalog(parse(moved), existing, NOW);

    expect(plan.products.find((p) => p.slug === 'banane')).toMatchObject({
      kind: 'update',
      categorySlug: 'laitiers',
      changes: { categorySlug: 'laitiers' },
    });
  });

  describe('name collisions', () => {
    it('rejects a name already held by an active row the file does not list', () => {
      const existing = stored(parse(fixtureCatalog()));
      existing.products.push({
        id: 999,
        slug: 'old-banane',
        categoryId: 1,
        brandId: null,
        name: 'Nouvelle Banane',
        description: null,
        photo: null,
        defaultSaleUnit: SaleUnit.KG,
        defaultMinQuantity: 100,
        defaultQuantityStep: 100,
        defaultMaxQuantity: null,
        archivedAt: null,
      });
      const renamed = fixtureCatalog();
      renamed.categories[0]!.products[0]!.name = 'nouvelle banane';

      const plan = planCatalog(parse(renamed), existing, NOW);

      expect(plan.errors).toEqual([
        'Product name "nouvelle banane" would be used by both "old-banane" and "banane"',
      ]);
    });

    it('allows the name of an archived row', () => {
      const existing = stored(parse(fixtureCatalog()));
      existing.products.push({
        id: 999,
        slug: 'old-banane',
        categoryId: 1,
        brandId: null,
        name: 'Nouvelle Banane',
        description: null,
        photo: null,
        defaultSaleUnit: SaleUnit.KG,
        defaultMinQuantity: 100,
        defaultQuantityStep: 100,
        defaultMaxQuantity: null,
        archivedAt: EARLIER,
      });
      const renamed = fixtureCatalog();
      renamed.categories[0]!.products[0]!.name = 'Nouvelle Banane';

      expect(planCatalog(parse(renamed), existing, NOW).errors).toEqual([]);
    });
  });

  describe('warnings', () => {
    const offering = (
      productId: number,
      storeId: number,
      saleUnit: SaleUnit = SaleUnit.PIECE,
    ): ExistingOffering => ({ productId, storeId, saleUnit });

    it('warns when archiving a product that stores still sell', () => {
      const catalog = parse(fixtureCatalog());
      const base = stored(catalog);
      const yogurt = base.products.find((p) => p.slug === 'yaourt')!;
      const existing = {
        ...base,
        offerings: [offering(yogurt.id, 1), offering(yogurt.id, 2)],
      };
      const archived = fixtureCatalog();
      Object.assign(archived.categories[1]!.products[1]!, { archived: true });

      const plan = planCatalog(parse(archived), existing, NOW);

      expect(plan.warnings).toEqual([
        'Archiving product "yaourt" while 2 store(s) still sell it: their offerings stay as configured, but customers can no longer order it',
      ]);
    });

    it('warns when archiving a category whose products stores sell', () => {
      const catalog = parse(fixtureCatalog());
      const base = stored(catalog);
      const banana = base.products.find((p) => p.slug === 'banane')!;
      const existing = { ...base, offerings: [offering(banana.id, 7)] };
      const archived = fixtureCatalog();
      Object.assign(archived.categories[0]!, { archived: true });

      const plan = planCatalog(parse(archived), existing, NOW);

      expect(plan.warnings).toEqual([
        'Archiving category "fruits" while 1 store(s) sell products in it: customers can no longer order them through this category',
      ]);
    });

    it('warns when a new default unit leaves an offering in a disallowed unit', () => {
      const catalog = parse(fixtureCatalog());
      const base = stored(catalog);
      const banana = base.products.find((p) => p.slug === 'banane')!;
      const existing = {
        ...base,
        offerings: [
          offering(banana.id, 1, SaleUnit.KG),
          offering(banana.id, 2, SaleUnit.PIECE),
        ],
      };
      const changed = fixtureCatalog();
      Object.assign(changed.categories[0]!.products[0]!, {
        defaultSaleUnit: 'L',
        defaultMinQuantity: 250,
        defaultQuantityStep: 250,
      });

      const plan = planCatalog(parse(changed), existing, NOW);

      expect(plan.warnings).toEqual([
        'Product "banane" now defaults to L, but 1 store offering(s) are sold in a unit that is no longer allowed for it (they are not changed)',
      ]);
    });

    it('mentions catalog entries the file leaves out, without touching them', () => {
      const catalog = parse(fixtureCatalog());
      const existing = stored(catalog);
      const smaller = fixtureCatalog();
      smaller.categories[1]!.products.pop();

      const plan = planCatalog(parse(smaller), existing, NOW);

      expect(plan.warnings).toEqual([
        '1 catalog product(s) are not in the file and were left unchanged: yaourt',
      ]);
      expect(plan.products.map((p) => p.slug)).not.toContain('yaourt');
    });
  });
});

describe('planCatalog brands', () => {
  const ketchupCatalog = () => {
    const input = fixtureCatalog();
    input.brands = [
      { slug: 'heinz', name: 'Heinz' },
      { slug: 'amora', name: 'Amora' },
    ];
    input.categories[1]!.products.push(
      {
        slug: 'ketchup-heinz',
        name: 'Ketchup',
        brandSlug: 'heinz',
        defaultSaleUnit: 'PIECE',
      },
      {
        slug: 'ketchup-amora',
        name: 'Ketchup',
        brandSlug: 'amora',
        defaultSaleUnit: 'PIECE',
      },
      { slug: 'ketchup', name: 'Ketchup', defaultSaleUnit: 'PIECE' },
    );
    return input;
  };

  it('creates the brands and carries each product’s brand', () => {
    const plan = planCatalog(parse(ketchupCatalog()), empty, NOW);

    expect(plan.errors).toEqual([]);
    expect(plan.brandCounts).toEqual({
      created: 2,
      updated: 0,
      unchanged: 0,
      archived: 0,
    });
    expect(plan.brands).toEqual([
      { kind: 'create', slug: 'heinz', create: { name: 'Heinz' } },
      { kind: 'create', slug: 'amora', create: { name: 'Amora' } },
    ]);
    const brandOf = (slug: string) =>
      plan.products.find((p) => p.slug === slug)!.brandSlug;
    expect(brandOf('ketchup-heinz')).toBe('heinz');
    expect(brandOf('ketchup-amora')).toBe('amora');
    expect(brandOf('ketchup')).toBeNull();
    expect(brandOf('banane')).toBeNull();
  });

  it('plans nothing when the database already matches (idempotent)', () => {
    const catalog = parse(ketchupCatalog());
    const plan = planCatalog(catalog, stored(catalog), NOW);

    expect(plan.errors).toEqual([]);
    expect(plan.brandCounts).toEqual({
      created: 0,
      updated: 0,
      unchanged: 2,
      archived: 0,
    });
    expect(plan.productCounts).toMatchObject({ created: 0, updated: 0 });
    expect(plan.products.every((p) => p.kind === 'unchanged')).toBe(true);
  });

  it('renames a brand under the same slug', () => {
    const existing = stored(parse(ketchupCatalog()));
    const renamed = ketchupCatalog();
    renamed.brands![0]!.name = 'Heinz France';

    const plan = planCatalog(parse(renamed), existing, NOW);

    expect(plan.brands.find((b) => b.slug === 'heinz')).toMatchObject({
      kind: 'update',
      changes: { name: 'Heinz France' },
    });
    expect(plan.brandCounts).toMatchObject({ updated: 1, unchanged: 1 });
    expect(plan.productCounts).toMatchObject({ updated: 0 });
  });

  it('gives an existing product a brand, takes it away, or changes it', () => {
    const existing = stored(parse(ketchupCatalog()));
    const changed = ketchupCatalog();
    const [heinz, amora, plain] = changed.categories[1]!.products.slice(-3) as [
      Record<string, unknown>,
      Record<string, unknown>,
      Record<string, unknown>,
    ];
    delete heinz['brandSlug']; // loses its brand (still unique: names differ below)
    heinz['name'] = 'Ketchup nature';
    amora['brandSlug'] = 'heinz'; // another brand
    plain['brandSlug'] = 'amora'; // gains one

    const plan = planCatalog(parse(changed), existing, NOW);
    const changes = (slug: string) =>
      plan.products.find((p) => p.slug === slug)!.changes;

    expect(plan.errors).toEqual([]);
    expect(changes('ketchup-heinz')).toEqual({
      name: 'Ketchup nature',
      brandSlug: null,
    });
    expect(changes('ketchup-amora')).toEqual({ brandSlug: 'heinz' });
    expect(changes('ketchup')).toEqual({ brandSlug: 'amora' });
  });

  describe('name collisions', () => {
    it('allows the same name under different brands and brandless', () => {
      const plan = planCatalog(parse(ketchupCatalog()), empty, NOW);
      expect(plan.errors).toEqual([]);
    });

    it('rejects a branded name held by a stored row the file does not list', () => {
      const existing = stored(parse(fixtureCatalog()));
      existing.brands.push({ id: 900, slug: 'heinz', name: 'Heinz' });
      existing.products.push({
        id: 999,
        slug: 'old-ketchup',
        categoryId: 1,
        brandId: 900,
        name: 'Ketchup',
        description: null,
        photo: null,
        defaultSaleUnit: SaleUnit.PIECE,
        defaultMinQuantity: 1,
        defaultQuantityStep: 1,
        defaultMaxQuantity: null,
        archivedAt: null,
      });
      const input = fixtureCatalog();
      input.brands = [{ slug: 'heinz', name: 'Heinz' }];
      input.categories[0]!.products.push({
        slug: 'ketchup-heinz',
        name: 'ketchup',
        brandSlug: 'heinz',
        defaultSaleUnit: 'PIECE',
      });

      const plan = planCatalog(parse(input), existing, NOW);

      expect(plan.errors).toEqual([
        'Product name "ketchup" (brand "heinz") would be used by both "old-ketchup" and "ketchup-heinz"',
      ]);
    });

    it('does not clash a branded stored row with a brandless entry of the same name', () => {
      const existing = stored(parse(fixtureCatalog()));
      existing.brands.push({ id: 900, slug: 'heinz', name: 'Heinz' });
      existing.products.push({
        id: 999,
        slug: 'old-ketchup',
        categoryId: 1,
        brandId: 900,
        name: 'Ketchup',
        description: null,
        photo: null,
        defaultSaleUnit: SaleUnit.PIECE,
        defaultMinQuantity: 1,
        defaultQuantityStep: 1,
        defaultMaxQuantity: null,
        archivedAt: null,
      });
      const input = fixtureCatalog();
      input.categories[0]!.products.push({
        slug: 'ketchup',
        name: 'Ketchup',
        defaultSaleUnit: 'PIECE',
      });

      expect(planCatalog(parse(input), existing, NOW).errors).toEqual([]);
    });

    it('rejects a brand name already held by a stored brand the file does not list', () => {
      const existing = stored(parse(fixtureCatalog()));
      existing.brands.push({ id: 900, slug: 'old-heinz', name: 'Heinz' });
      const input = fixtureCatalog();
      input.brands = [{ slug: 'heinz', name: 'HEINZ' }];

      expect(planCatalog(parse(input), existing, NOW).errors).toEqual([
        'Brand name "HEINZ" would be used by both "old-heinz" and "heinz"',
      ]);
    });
  });

  it('mentions brands the file leaves out, without touching them', () => {
    const existing = stored(parse(fixtureCatalog()));
    existing.brands.push({ id: 900, slug: 'old-heinz', name: 'Old Heinz' });

    const plan = planCatalog(parse(fixtureCatalog()), existing, NOW);

    expect(plan.warnings).toContain(
      '1 catalog brand(s) are not in the file and were left unchanged: old-heinz',
    );
    expect(plan.brands).toEqual([]);
  });
});
