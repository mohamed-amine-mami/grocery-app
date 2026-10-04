import { fixtureCatalog } from '../../test/catalog-fixture.js';
import { parseCatalog } from './catalog-file.js';

type Mutable = ReturnType<typeof fixtureCatalog>;
const product = (catalog: Mutable, category = 0, index = 0) =>
  catalog.categories[category]!.products[index]! as Record<string, unknown>;

describe('parseCatalog', () => {
  it('accepts a valid catalog and fills in the defaults', () => {
    const { catalog, errors } = parseCatalog(fixtureCatalog());

    expect(errors).toEqual([]);
    const milk = catalog!.categories[1]!.products[0]!;
    expect(milk).toEqual({
      slug: 'lait-delice-1l',
      name: 'Lait Délice 1 L',
      description: null,
      photo: null,
      defaultSaleUnit: 'PIECE',
      defaultMinQuantity: 1,
      defaultQuantityStep: 1,
      defaultMaxQuantity: null,
      archived: false,
    });
    expect(catalog!.categories[1]!.products[1]!.description).toBe(
      'Pot individuel',
    );
  });

  it('trims names and treats a blank description as none', () => {
    const input = fixtureCatalog();
    input.categories[0]!.name = '  Fruits  ';
    Object.assign(product(input), { name: '  Banane  ', description: '   ' });

    const { catalog } = parseCatalog(input);

    expect(catalog!.categories[0]!.name).toBe('Fruits');
    expect(catalog!.categories[0]!.products[0]).toMatchObject({
      name: 'Banane',
      description: null,
    });
  });

  it.each<[string, (catalog: Mutable) => void, string]>([
    [
      'a duplicate category slug',
      (c) => {
        c.categories[1]!.slug = c.categories[0]!.slug;
      },
      'categories[1].slug: "fruits" is already used by categories[0]',
    ],
    [
      'a duplicate product slug across categories',
      (c) => {
        product(c, 1, 0)['slug'] = 'banane';
      },
      'categories[1].products[0].slug: "banane" is already used by categories[0].products[0]',
    ],
    [
      'a malformed category slug',
      (c) => {
        c.categories[0]!.slug = 'Fruits Frais';
      },
      'categories[0].slug: "Fruits Frais" must be lowercase',
    ],
    [
      'a malformed product slug',
      (c) => {
        product(c)['slug'] = 'banane_jaune';
      },
      'categories[0].products[0].slug: "banane_jaune" must be lowercase',
    ],
    [
      'a missing product slug',
      (c) => {
        delete product(c)['slug'];
      },
      'categories[0].products[0].slug: is required',
    ],
    [
      'a blank product name',
      (c) => {
        product(c)['name'] = '   ';
      },
      'categories[0].products[0].name: is required',
    ],
    [
      'a blank category name',
      (c) => {
        c.categories[0]!.name = '';
      },
      'categories[0].name: is required',
    ],
    [
      'an unknown sale unit',
      (c) => {
        product(c)['defaultSaleUnit'] = 'LITRE';
      },
      'categories[0].products[0].defaultSaleUnit: must be one of PIECE, KG, L',
    ],
    [
      'a missing sale unit',
      (c) => {
        delete product(c)['defaultSaleUnit'];
      },
      'defaultSaleUnit: must be one of',
    ],
    [
      'a minimum that is not a multiple of the step',
      (c) => {
        Object.assign(product(c), {
          defaultMinQuantity: 150,
          defaultQuantityStep: 100,
        });
      },
      'defaultMinQuantity must be a multiple of defaultQuantityStep',
    ],
    [
      'a maximum below the minimum',
      (c) => {
        Object.assign(product(c), {
          defaultMinQuantity: 500,
          defaultMaxQuantity: 100,
        });
      },
      'defaultMaxQuantity must be greater than or equal to defaultMinQuantity',
    ],
    [
      'a fractional quantity',
      (c) => {
        product(c)['defaultQuantityStep'] = 100.5;
      },
      'defaultQuantityStep must be a positive integer',
    ],
    [
      'a weight step the unit does not allow',
      (c) => {
        Object.assign(product(c), {
          defaultQuantityStep: 15,
          defaultMinQuantity: 15,
          defaultMaxQuantity: null,
        });
      },
      'must be a multiple of 10 grams',
    ],
    [
      'a quantity that is not a number',
      (c) => {
        product(c)['defaultMinQuantity'] = '100';
      },
      'defaultMinQuantity: must be a number',
    ],
    [
      'a photo that is not an http(s) URL',
      (c) => {
        product(c)['photo'] = 'ftp://example.com/banane.jpg';
      },
      'categories[0].products[0].photo: must be an http(s) URL',
    ],
    [
      'a category reference on a product (the nesting is the reference)',
      (c) => {
        product(c)['categorySlug'] = 'does-not-exist';
      },
      'unknown field "categorySlug" — a product belongs to the category it is nested under',
    ],
    [
      'an unknown field',
      (c) => {
        product(c)['price'] = 4500;
      },
      'unknown field "price"',
    ],
    [
      'a category whose products are not a list',
      (c) => {
        (c.categories[0] as Record<string, unknown>)['products'] = 'banane';
      },
      'categories[0].products: must be a list',
    ],
    [
      'a duplicate active product name, ignoring case',
      (c) => {
        product(c, 1, 0)['name'] = 'BANANE';
      },
      'is already used by active product categories[0].products[0]',
    ],
    [
      'a duplicate active category name, ignoring case',
      (c) => {
        c.categories[1]!.name = 'FRUITS';
      },
      'is already used by active category categories[0]',
    ],
  ])('rejects %s', (_label, mutate, expected) => {
    const input = fixtureCatalog();
    mutate(input);

    const { catalog, errors } = parseCatalog(input);

    expect(catalog).toBeNull();
    expect(errors).toContainEqual(expect.stringContaining(expected));
  });

  it('allows an archived entry to reuse the name of an active one', () => {
    const input = fixtureCatalog();
    Object.assign(product(input, 1, 0), { name: 'Banane', archived: true });

    expect(parseCatalog(input).errors).toEqual([]);
  });

  it('reports every problem, not only the first', () => {
    const input = fixtureCatalog();
    product(input, 0, 0)['defaultSaleUnit'] = 'LITRE';
    product(input, 1, 0)['slug'] = 'Bad Slug';
    product(input, 1, 1)['name'] = '';

    expect(parseCatalog(input).errors).toHaveLength(3);
  });

  it.each([null, 'catalog', [], { categories: 'none' }, { products: [] }])(
    'rejects a file that is not { categories: [...] }: %j',
    (input) => {
      const { catalog, errors } = parseCatalog(input);
      expect(catalog).toBeNull();
      expect(errors.length).toBeGreaterThan(0);
    },
  );

  it('accepts the starter catalog shipped in seed/catalog.json', async () => {
    const { readFile } = await import('node:fs/promises');
    const seed = JSON.parse(await readFile('seed/catalog.json', 'utf8'));

    const { catalog, errors } = parseCatalog(seed);

    expect(errors).toEqual([]);
    expect(catalog!.categories.length).toBeGreaterThan(0);
  });
});
