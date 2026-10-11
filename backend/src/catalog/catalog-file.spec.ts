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
      brandSlug: null,
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

describe('parseCatalog brands', () => {
  const withBrands = () => {
    const input = fixtureCatalog();
    input.brands = [
      { slug: 'heinz', name: 'Heinz' },
      { slug: 'amora', name: 'Amora' },
    ];
    return input;
  };
  const ketchup = (catalog: Mutable, brandSlug?: string | null) => {
    const entry: Record<string, unknown> = {
      slug: `ketchup-${brandSlug ?? 'sans-marque'}-${catalog.categories[1]!.products.length}`,
      name: 'Ketchup',
      defaultSaleUnit: 'PIECE',
    };
    if (brandSlug !== undefined) entry['brandSlug'] = brandSlug;
    catalog.categories[1]!.products.push(entry);
    return entry;
  };

  it('treats a catalog without brands as valid, with no brands', () => {
    const { catalog, errors } = parseCatalog(fixtureCatalog());
    expect(errors).toEqual([]);
    expect(catalog!.brands).toEqual([]);
    for (const p of catalog!.categories.flatMap((c) => c.products)) {
      expect(p.brandSlug).toBeNull();
    }
  });

  it('accepts brands, and a product that points at one — or at none', () => {
    const input = withBrands();
    product(input, 1, 0)['brandSlug'] = 'heinz';
    product(input, 1, 1)['brandSlug'] = null;

    const { catalog, errors } = parseCatalog(input);

    expect(errors).toEqual([]);
    expect(catalog!.brands).toEqual([
      { slug: 'heinz', name: 'Heinz' },
      { slug: 'amora', name: 'Amora' },
    ]);
    expect(catalog!.categories[1]!.products.map((p) => p.brandSlug)).toEqual([
      'heinz',
      null,
    ]);
    expect(catalog!.categories[0]!.products[0]!.brandSlug).toBeNull(); // omitted
  });

  it('trims a brand name', () => {
    const input = withBrands();
    input.brands![0]!.name = '  Heinz  ';
    expect(parseCatalog(input).catalog!.brands[0]!.name).toBe('Heinz');
  });

  it.each<[string, (catalog: Mutable) => void, string]>([
    [
      'an unknown brand reference',
      (c) => {
        product(c)['brandSlug'] = 'inconnue';
      },
      'categories[0].products[0].brandSlug: unknown brand "inconnue" — add it to "brands"',
    ],
    [
      'a brand reference when the file has no brands at all',
      (c) => {
        delete c.brands;
        product(c)['brandSlug'] = 'heinz';
      },
      'unknown brand "heinz"',
    ],
    [
      'a malformed brand reference',
      (c) => {
        product(c)['brandSlug'] = 'Heinz Co';
      },
      'categories[0].products[0].brandSlug: must be the slug of a brand',
    ],
    [
      'a brand reference that is not text',
      (c) => {
        product(c)['brandSlug'] = 12;
      },
      'categories[0].products[0].brandSlug: must be the slug of a brand',
    ],
    [
      'a brand reached for by name or id',
      (c) => {
        product(c)['brand'] = 'Heinz';
      },
      'categories[0].products[0]: unknown field "brand" — point a product at its brand with "brandSlug"',
    ],
    [
      'a duplicate brand slug',
      (c) => {
        c.brands![1]!.slug = 'heinz';
      },
      'brands[1].slug: "heinz" is already used by brands[0]',
    ],
    [
      'a duplicate brand name in another case',
      (c) => {
        c.brands![1]!.name = 'HEINZ';
      },
      'brands[1].name: "HEINZ" is already used by brand brands[0]',
    ],
    [
      'a malformed brand slug',
      (c) => {
        c.brands![0]!.slug = 'Heinz Co';
      },
      'brands[0].slug: "Heinz Co" must be lowercase',
    ],
    [
      'a missing brand slug',
      (c) => {
        delete (c.brands![0] as Record<string, unknown>)['slug'];
      },
      'brands[0].slug: is required',
    ],
    [
      'a blank brand name',
      (c) => {
        c.brands![0]!.name = '  ';
      },
      'brands[0].name: is required',
    ],
    [
      'an over-long brand name',
      (c) => {
        c.brands![0]!.name = 'x'.repeat(101);
      },
      'brands[0].name: must be at most 100 characters',
    ],
    [
      'an unknown brand field',
      (c) => {
        (c.brands![0] as Record<string, unknown>)['logo'] = 'https://x.test/a';
      },
      'brands[0]: unknown field "logo"',
    ],
    [
      'brands that are not a list',
      (c) => {
        (c as unknown as Record<string, unknown>)['brands'] = {};
      },
      'catalog.brands: must be a list',
    ],
  ])('rejects %s', (_label, mutate, expected) => {
    const input = withBrands();
    mutate(input);
    const { catalog, errors } = parseCatalog(input);
    expect(catalog).toBeNull();
    expect(errors.some((error) => error.includes(expected))).toBe(true);
  });

  it('lets the same product name exist under two brands, and brandless', () => {
    const input = withBrands();
    ketchup(input, 'heinz');
    ketchup(input, 'amora');
    ketchup(input);
    expect(parseCatalog(input).errors).toEqual([]);
  });

  it('refuses the same active name twice under one brand', () => {
    const input = withBrands();
    ketchup(input, 'heinz');
    ketchup(input, 'heinz');
    const { errors } = parseCatalog(input);
    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain('"Ketchup" of brand "heinz" is already used');
  });

  it('refuses the same active name twice when both are brandless', () => {
    const input = withBrands();
    ketchup(input);
    ketchup(input, null);
    const { errors } = parseCatalog(input);
    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain('"Ketchup" is already used by active product');
  });

  it('does not count an archived product against the name', () => {
    const input = withBrands();
    ketchup(input, 'heinz')['archived'] = true;
    ketchup(input, 'heinz');
    expect(parseCatalog(input).errors).toEqual([]);
  });
});
