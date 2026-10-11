import { isURL } from 'class-validator';
import { parseCatalog } from '../../src/catalog/catalog-file.js';
import { PHOTO_URL_OPTIONS, URL_MAX_LENGTH } from '../../src/common/limits.js';
import {
  CATEGORIES,
  PATH_RULES,
  classifyUnit,
  cleanText,
  convertCarrefour,
  fixAllCaps,
  looksPacked,
  mapCategory,
  parseCsv,
  slugify,
} from './lib.js';

const isValidPhoto = (url: string) =>
  url.length <= URL_MAX_LENGTH && isURL(url, PHOTO_URL_OPTIONS);

const row = (overrides: Record<string, string> = {}) => ({
  sku: '1000',
  name: 'Ketchup',
  brand: '',
  category: 'Épicerie Salée > Sauces et Assaisonnements > Ketchup',
  image_url: 'https://img.example/1000.webp',
  product_url: 'https://shop.example/ketchup-1000.html',
  source: 'Carrefour Tunisia',
  ...overrides,
});

const convert = (rows: Record<string, string>[]) =>
  convertCarrefour(rows, { isValidPhoto });

describe('parseCsv', () => {
  it('reads quoted fields with commas, doubled quotes and newlines', () => {
    const rows = parseCsv(
      'name,category\n"Sauce, piquante","A > B, C"\n"Dit ""oui""","Ligne 1\nligne 2"\n',
    );
    expect(rows).toEqual([
      { name: 'Sauce, piquante', category: 'A > B, C' },
      { name: 'Dit "oui"', category: 'Ligne 1\nligne 2' },
    ]);
  });

  it('copes with a BOM, CRLF line ends and a blank last line', () => {
    const rows = parseCsv('﻿a,b\r\n1,2\r\n\r\n');
    expect(rows).toEqual([{ a: '1', b: '2' }]);
  });

  it('keeps empty fields empty', () => {
    expect(parseCsv('a,b,c\n1,,3\n')).toEqual([{ a: '1', b: '', c: '3' }]);
  });
});

describe('slugify', () => {
  it.each([
    ['Crème brûlée', 'creme-brulee'],
    ['Œufs jaune orange', 'oeufs-jaune-orange'],
    ["L'EPI D'OR", 'lepi-dor'],
    ['Thon à l’huile d’olive', 'thon-a-lhuile-dolive'],
    ['N°1', 'n1'],
    ['DR.OETKER', 'dr-oetker'],
    ['100 % lait', '100-lait'],
    ['Street & Co', 'street-co'],
    ['  Multiple   spaces  ', 'multiple-spaces'],
    ['Épicerie', 'epicerie'],
  ])('%s → %s', (input, expected) => {
    expect(slugify(input)).toBe(expected);
  });

  it('always matches the importer slug pattern', () => {
    for (const text of ['Café & Thé', '¿Qué?', "L'été — 2026", 'Déjà-vu']) {
      expect(slugify(text)).toMatch(/^[a-z0-9]+(-[a-z0-9]+)*$/);
    }
  });
});

describe('text cleaning', () => {
  it('trims and collapses whitespace only', () => {
    expect(cleanText('  Lait   demi-écrémé \n')).toBe('Lait demi-écrémé');
    expect(cleanText(undefined)).toBe('');
  });

  it('fixes an all-caps name, and leaves any other casing alone', () => {
    expect(fixAllCaps('COCA COLA')).toBe('Coca Cola');
    expect(fixAllCaps("L'EAU")).toBe("L'Eau");
    expect(fixAllCaps('FANTA orange')).toBe('FANTA orange');
    expect(fixAllCaps('Eau minérale MELLITI')).toBe('Eau minérale MELLITI');
    expect(fixAllCaps('UHT')).toBe('UHT'); // too short to be sure
  });
});

describe('category mapping', () => {
  it('only uses categories that are defined', () => {
    const slugs = new Set(CATEGORIES.map((c) => c.slug));
    for (const rule of PATH_RULES) expect(slugs.has(rule.slug)).toBe(true);
    expect(slugs.size).toBe(CATEGORIES.length);
  });

  it('keeps the slug and name of the development catalog’s categories', () => {
    const named = Object.fromEntries(CATEGORIES.map((c) => [c.slug, c.name]));
    expect(named).toMatchObject({
      fruits: 'Fruits',
      legumes: 'Légumes',
      'viandes-poissons': 'Viandes et poissons',
      'produits-laitiers': 'Produits laitiers',
      boulangerie: 'Boulangerie',
      boissons: 'Boissons',
    });
  });

  it.each([
    ['Boissons > Eaux > Eaux Plates', 'Eau', 'boissons'],
    ['Le marché > Fruits de saison', 'Kiwi', 'fruits'],
    ['Le marché > Légumes > Salades et Tomates', 'Laitue', 'legumes'],
    [
      'Le marché > Légumes > Légumes secs',
      'Lentilles',
      'pates-riz-legumes-secs',
    ],
    [
      'Le marché > Volaille > Poulets > Pilon de poulet',
      'Pilons',
      'viandes-poissons',
    ],
    [
      'Crèmerie et Produits Laitiers > Fromages > Blancs',
      'Fromage',
      'fromages',
    ],
    [
      'Crèmerie et Produits Laitiers > Fromages à la coupe > Edam',
      'Edam',
      'fromages',
    ],
    [
      'Crèmerie et Produits Laitiers > Yaourts et Fromages blancs > Fromages blancs',
      'Fromage blanc',
      'produits-laitiers',
    ],
    ['Crèmerie et Produits Laitiers > Les Œufs', 'Œufs', 'produits-laitiers'],
    ['Épicerie Salée > Snack et Apéritif > Fruits Secs', 'Mix', 'fruits-secs'],
    ['Épicerie Salée > Snack et Apéritif > Chips', 'Chips', 'snacks-aperitif'],
    [
      'Épicerie Salée > Pâtes Couscous et Riz > Bouillons',
      'Bouillon',
      'sauces-condiments',
    ],
    [
      'Épicerie Salée > Pâtes Couscous et Riz > Riz',
      'Riz',
      'pates-riz-legumes-secs',
    ],
    ['Épicerie Sucrée > Café > Moulus', 'Café', 'cafe-the'],
    ['Surgelés > Légumes et Fruits', 'Petits pois', 'surgeles'],
  ])('%s → %s', (path, name, expected) => {
    expect(mapCategory(path, name).slug).toBe(expected);
  });

  it('the most specific rule wins over its parent', () => {
    expect(
      mapCategory(
        'Épicerie Salée > Conserves et Plats Cuisinés > Condiments',
        'Cornichons',
      ).slug,
    ).toBe('sauces-condiments');
    expect(
      mapCategory(
        'Épicerie Salée > Conserves et Plats Cuisinés > Maïs',
        'Maïs doux',
      ).slug,
    ).toBe('conserves');
  });

  it('corrects a product filed in the wrong place, by its name, only there', () => {
    const tomatoes =
      'Épicerie Salée > Conserves et Plats Cuisinés > Tomates concassées et pelées';
    expect(mapCategory(tomatoes, 'Moutarde 260 ml')).toMatchObject({
      slug: 'sauces-condiments',
      overridden: true,
    });
    expect(mapCategory(tomatoes, 'Tomates concassées')).toMatchObject({
      slug: 'conserves',
      overridden: false,
    });
    // The same word elsewhere is not touched.
    expect(
      mapCategory(
        'Épicerie Salée > Sauces et Assaisonnements > Moutarde',
        'Moutarde',
      ).overridden,
    ).toBe(false);
  });

  it('places the products the CSV files directly under a root, by name', () => {
    const root = 'Épicerie Sucrée';
    expect(mapCategory(root, 'Bonbons Worms').slug).toBe('chocolat-confiserie');
    expect(mapCategory(root, 'Cake marbré').slug).toBe('biscuits-gateaux');
    expect(mapCategory(root, 'Céréales Chocapic').slug).toBe('petit-dejeuner');
    expect(
      mapCategory('Crèmerie et Produits Laitiers', 'Fromage ricotta').slug,
    ).toBe('fromages');
    expect(mapCategory('Le marché', 'Mini salami de dinde').slug).toBe(
      'charcuterie-traiteur',
    );
  });

  it('does not let the root rules reach into sub-categories', () => {
    expect(
      mapCategory(
        'Épicerie Sucrée > Bonbons et Chocolats > Barres de chocolat',
        'Barre de chocolat',
      ).slug,
    ).toBe('chocolat-confiserie');
  });

  it('leaves a path it does not know unmapped, never guessed', () => {
    expect(mapCategory('Jardin > Outils', 'Pelle').slug).toBeNull();
    expect(mapCategory('Épicerie Sucrée', 'Quelque chose').slug).toBeNull();
  });
});

describe('sale unit classification', () => {
  it.each([
    ['Le marché > Fruits de saison', 'Ananas', 'KG', 'market-produce', 'high'],
    [
      'Le marché > Légumes > Légumes de saison',
      'Persil',
      'KG',
      'market-produce',
      'high',
    ],
    [
      'Le marché > Légumes > Salades et Tomates',
      'Tomate ronde',
      'KG',
      'market-produce',
      'high',
    ],
    [
      'Le marché > Boucherie > Bœuf',
      'Pavé de veau',
      'KG',
      'market-butcher-poultry-fish',
      'high',
    ],
    [
      'Le marché > Volaille > Poulets > Poulets entiers',
      'Poulet',
      'KG',
      'market-butcher-poultry-fish',
      'high',
    ],
    [
      'Le marché > Poissons > Poissons entiers',
      'Sardine',
      'KG',
      'market-butcher-poultry-fish',
      'high',
    ],
    [
      'Le marché > Fruits secs et séchés',
      'Noix de cajou',
      'KG',
      'market-nuts-olives',
      'high',
    ],
    [
      'Le marché > Épices, Olives et Condiments > Olives',
      'Olives noires',
      'KG',
      'market-nuts-olives',
      'high',
    ],
    [
      'Crèmerie et Produits Laitiers > Fromages à la coupe > Gouda',
      'Gouda',
      'KG',
      'cut-cheese',
      'high',
    ],
    [
      'Le marché > Boulangerie et Pâtisserie > Pains',
      'Boule blanche',
      'PIECE',
      'bakery-and-deli-pieces',
      'high',
    ],
    [
      'Le marché > Traiteur > Chaud > Rôtisserie',
      'Poulet rôti',
      'PIECE',
      'bakery-and-deli-pieces',
      'high',
    ],
    [
      'Boissons > Eaux > Eaux Plates',
      'Eau minérale',
      'PIECE',
      'packaged',
      'high',
    ],
    [
      "Épicerie Salée > Huiles > Huile d'Olive",
      'Huile d’olive',
      'PIECE',
      'packaged',
      'high',
    ],
    [
      'Crèmerie et Produits Laitiers > Fromages > Râpé et Fondant',
      'Fromage râpé',
      'PIECE',
      'packaged',
      'high',
    ],
    [
      'Surgelés > Viandes surgelées',
      'Nuggets de poulet',
      'PIECE',
      'packaged',
      'high',
    ],
  ])('%s / %s → %s', (path, name, unit, rule, confidence) => {
    expect(classifyUnit(path, name)).toEqual({ unit, rule, confidence });
  });

  it('flags for review what could be weighed or packed', () => {
    expect(
      classifyUnit(
        'Le marché > Charcuterie > Jambon, Salami et Saucisse',
        'Jambon de dinde',
      ),
    ).toMatchObject({ unit: 'KG', confidence: 'review' });
    expect(
      classifyUnit(
        'Le marché > Traiteur > Chaud > Cordons bleus et Nuggets',
        'Cordon bleu frais',
      ),
    ).toMatchObject({ unit: 'KG', confidence: 'review' });
    expect(
      classifyUnit(
        'Le marché > Poissons > Filets, Pavés et séchés',
        'Saumon fumé',
      ),
    ).toMatchObject({ unit: 'KG', confidence: 'review' });
    expect(classifyUnit('Le marché', 'Mini salami')).toMatchObject({
      unit: 'KG',
      confidence: 'review',
    });
  });

  it('classifies a loose liquid by volume, only when the name says so', () => {
    expect(
      classifyUnit('Boissons > Jus', 'Jus d’orange en vrac'),
    ).toMatchObject({ unit: 'L' });
    expect(classifyUnit('Boissons > Jus', 'Jus d’orange 1 L')).toMatchObject({
      unit: 'PIECE',
    });
  });

  it('notices a weighed product that looks like a closed pack', () => {
    expect(looksPacked('Oignon en barquette')).toBe(true);
    expect(looksPacked('Beefteck de veau en barquete')).toBe(true);
    expect(looksPacked('Calamars panés')).toBe(true);
    expect(looksPacked('Pavé de veau')).toBe(false);
  });
});

describe('convertCarrefour', () => {
  it('turns a row into a product with the brand, category, photo and unit', () => {
    const { catalog, report } = convert([
      row({ sku: '1', name: 'Ketchup', brand: 'HEINZ' }),
    ]);
    expect(catalog).toEqual({
      brands: [{ slug: 'heinz', name: 'HEINZ' }],
      categories: [
        {
          slug: 'sauces-condiments',
          name: 'Sauces et condiments',
          products: [
            {
              slug: 'ketchup-heinz',
              name: 'Ketchup',
              brandSlug: 'heinz',
              photo: 'https://img.example/1000.webp',
              defaultSaleUnit: 'PIECE',
            },
          ],
        },
      ],
    });
    expect(report).toMatchObject({ sourceRows: 1, convertedProducts: 1 });
    expect(report.skuToSlug).toEqual({ '1': 'ketchup-heinz' });
  });

  it('never writes the Carrefour sku, url, price, stock or quantity rules into a product', () => {
    const { catalog } = convert([row({ sku: '999', brand: 'HEINZ' })]);
    const product = catalog.categories[0]!.products[0]!;
    expect(Object.keys(product).sort()).toEqual(
      ['brandSlug', 'defaultSaleUnit', 'name', 'photo', 'slug'].sort(),
    );
    expect(JSON.stringify(catalog)).not.toContain('999');
    expect(JSON.stringify(catalog)).not.toContain('shop.example');
  });

  it('keeps the same name under different brands, and without a brand', () => {
    const { catalog, report } = convert([
      row({ sku: '1', brand: 'HEINZ' }),
      row({
        sku: '2',
        brand: 'AMORA',
        image_url: 'https://img.example/2.webp',
        product_url: 'u2',
      }),
      row({
        sku: '3',
        brand: '',
        image_url: 'https://img.example/3.webp',
        product_url: 'u3',
      }),
    ]);
    const slugs = catalog.categories[0]!.products.map((p) => p.slug);
    expect(slugs).toEqual(['ketchup', 'ketchup-amora', 'ketchup-heinz']);
    expect(report.duplicateProducts.count).toBe(0);
    expect(report.excludedProducts.count).toBe(0);
    expect(
      report.duplicateProducts.analysis.sameNameDifferentBrand.groups,
    ).toBe(1);
    expect(report.brands.brandlessProducts).toBe(1);
  });

  it('treats a blank brand as no brand and creates one brand per distinct brand', () => {
    const { catalog } = convert([
      row({
        sku: '1',
        name: 'A',
        brand: 'HEINZ',
        image_url: 'i1',
        product_url: 'u1',
      }),
      row({
        sku: '2',
        name: 'B',
        brand: 'HEINZ',
        image_url: 'i2',
        product_url: 'u2',
      }),
      row({
        sku: '3',
        name: 'C',
        brand: '   ',
        image_url: 'i3',
        product_url: 'u3',
      }),
    ]);
    expect(catalog.brands).toEqual([{ slug: 'heinz', name: 'HEINZ' }]);
    const products = catalog.categories[0]!.products;
    expect(products.find((p) => p.name === 'C')).not.toHaveProperty(
      'brandSlug',
    );
  });

  it('merges brand spellings that differ only in formatting, reports them, and does not merge look-alikes', () => {
    const { catalog, report } = convert([
      row({
        sku: '1',
        name: 'A',
        brand: 'Délice',
        image_url: 'i1',
        product_url: 'u1',
      }),
      row({
        sku: '2',
        name: 'B',
        brand: 'DÉLICE',
        image_url: 'i2',
        product_url: 'u2',
      }),
      row({
        sku: '7',
        name: 'G',
        brand: 'DÉLICE',
        image_url: 'i7',
        product_url: 'u7',
      }),
      row({
        sku: '3',
        name: 'C',
        brand: 'DELICE',
        image_url: 'i3',
        product_url: 'u3',
      }),
      row({
        sku: '4',
        name: 'D',
        brand: 'DÉLICE DANONE',
        image_url: 'i4',
        product_url: 'u4',
      }),
      row({
        sku: '5',
        name: 'E',
        brand: 'AL JAZIRA',
        image_url: 'i5',
        product_url: 'u5',
      }),
      row({
        sku: '6',
        name: 'F',
        brand: 'AL JAZIA',
        image_url: 'i6',
        product_url: 'u6',
      }),
    ]);
    expect(catalog.brands.map((b) => b.slug)).toEqual([
      'al-jazia',
      'al-jazira',
      'delice',
      'delice-danone',
    ]);
    expect(report.brands.merges).toHaveLength(1);
    expect(report.brands.merges[0]!.slug).toBe('delice');
    expect(report.brands.merges[0]!.kept).toBe('DÉLICE'); // the most used spelling
    expect(
      report.brands.possibleVariantsNotMerged.map((v) => [v.a, v.b]),
    ).toEqual(
      expect.arrayContaining([
        ['AL JAZIA', 'AL JAZIRA'],
        ['DÉLICE', 'DÉLICE DANONE'],
      ]),
    );
  });

  it('on a tie between spellings, keeps the one with its accents', () => {
    const { catalog } = convert([
      row({
        sku: '1',
        name: 'A',
        brand: 'DELICE',
        image_url: 'i1',
        product_url: 'u1',
      }),
      row({
        sku: '2',
        name: 'B',
        brand: 'DÉLICE',
        image_url: 'i2',
        product_url: 'u2',
      }),
    ]);
    expect(catalog.brands).toEqual([{ slug: 'delice', name: 'DÉLICE' }]);
  });

  it('drops a repeated sku, and a repeated product page, and reports each', () => {
    const { report, catalog } = convert([
      row({ sku: '1', name: 'A' }),
      row({ sku: '1', name: 'A again', image_url: 'x', product_url: 'ua' }),
      row({ sku: '2', name: 'B', product_url: 'ub', image_url: 'y' }),
      row({ sku: '3', name: 'C', product_url: 'ub', image_url: 'z' }),
    ]);
    expect(catalog.categories[0]!.products.map((p) => p.name)).toEqual([
      'A',
      'B',
    ]);
    expect(
      report.duplicateProducts.items.map((d) => [d.kind, d.discardedSku]),
    ).toEqual([
      ['same sku', '1'],
      ['same product url', '3'],
    ]);
    expect(report.sourceRows).toBe(4);
    expect(
      report.convertedProducts +
        report.duplicateProducts.count +
        report.excludedProducts.count,
    ).toBe(report.sourceRows);
  });

  it('keeps one of two products with the same name and brand, the lowest sku, and says which went', () => {
    const { report, catalog } = convert([
      row({
        sku: '20',
        name: 'Ketchup',
        brand: 'HEINZ',
        image_url: 'i20',
        product_url: 'u20',
      }),
      row({
        sku: '10',
        name: 'ketchup',
        brand: 'HEINZ',
        image_url: 'i10',
        product_url: 'u10',
      }),
    ]);
    expect(report.skuToSlug).toEqual({ '10': 'ketchup-heinz' });
    expect(catalog.categories[0]!.products).toHaveLength(1);
    expect(report.duplicateProducts.items).toEqual([
      expect.objectContaining({
        kind: 'same name and brand',
        keptSku: '10',
        discardedSku: '20',
      }),
    ]);
  });

  it('resolves a slug collision by sku order and reports it', () => {
    const { report, catalog } = convert([
      row({
        sku: '2',
        name: 'Thon à l’huile',
        brand: 'CAP BLANC',
        image_url: 'i2',
        product_url: 'u2',
      }),
      row({
        sku: '1',
        name: "Thon à l'huile CAP BLANC",
        brand: 'CAP BLANC',
        image_url: 'i1',
        product_url: 'u1',
      }),
    ]);
    // Different names, the same slug once the brand ending the name is not repeated.
    expect(report.skuToSlug).toEqual({
      '1': 'thon-a-lhuile-cap-blanc',
      '2': 'thon-a-lhuile-cap-blanc-2',
    });
    expect(report.slugCollisions.count).toBe(1);
    expect(report.slugCollisions.items[0]!.resolved.map((r) => r.slug)).toEqual(
      ['thon-a-lhuile-cap-blanc', 'thon-a-lhuile-cap-blanc-2'],
    );
    expect(report.excludedProducts.count).toBe(0);
    expect(catalog.categories[0]!.products).toHaveLength(2);
  });

  it('does not repeat a brand that already ends the name', () => {
    const { report } = convert([
      row({
        sku: '1',
        name: 'Coca Cola',
        brand: 'COCA COLA',
        category: 'Boissons > Boissons Gazeuses',
      }),
    ]);
    expect(report.skuToSlug['1']).toBe('coca-cola');
  });

  it('keeps a product whose photo is missing or invalid, and reports it', () => {
    const { report, catalog } = convert([
      row({ sku: '1', name: 'A', image_url: '', product_url: 'u1' }),
      row({ sku: '2', name: 'B', image_url: 'not a url', product_url: 'u2' }),
      row({
        sku: '3',
        name: 'C',
        image_url: 'ftp://x.test/c.jpg',
        product_url: 'u3',
      }),
      row({
        sku: '4',
        name: 'D',
        image_url: `https://x.test/${'a'.repeat(2100)}.jpg`,
        product_url: 'u4',
      }),
      row({
        sku: '5',
        name: 'E',
        image_url: 'https://x.test/e.webp',
        product_url: 'u5',
      }),
    ]);
    const products = catalog.categories[0]!.products;
    expect(products).toHaveLength(5);
    expect(products.filter((p) => 'photo' in p).map((p) => p.name)).toEqual([
      'E',
    ]);
    expect(report.missingPhotos).toEqual({ count: 1, skus: ['1'] });
    expect(report.invalidPhotos.items.map((i) => i.sku)).toEqual([
      '2',
      '3',
      '4',
    ]);
    expect(report.validPhotos).toBe(1);
  });

  it('excludes a product with no category it can be placed in, and says why', () => {
    const { report, catalog } = convert([
      row({ sku: '1', name: 'A' }),
      row({
        sku: '2',
        name: 'Pelle',
        category: 'Jardin > Outils',
        product_url: 'u2',
      }),
      row({ sku: '3', name: '', product_url: 'u3' }),
    ]);
    expect(catalog.categories.flatMap((c) => c.products)).toHaveLength(1);
    expect(report.excludedProducts.items.map((e) => [e.sku, e.reason])).toEqual(
      [
        ['3', 'blank name'],
        ['2', 'no GrocerGo category for "Jardin > Outils"'],
      ],
    );
    expect(report.unmappedCategories).toEqual([
      { category: 'Jardin > Outils', products: ['2'] },
    ]);
  });

  it('cleans whitespace and an all-caps name, and keeps the original in the report', () => {
    const { report, catalog } = convert([
      row({
        sku: '1',
        name: '  COCA   COLA ',
        brand: ' COCA  COLA ',
        category: 'Boissons > Boissons Gazeuses',
      }),
    ]);
    expect(catalog.categories[0]!.products[0]!.name).toBe('Coca Cola');
    expect(catalog.brands).toEqual([{ slug: 'coca-cola', name: 'COCA COLA' }]);
    expect(report.nameNormalizations).toEqual([
      { sku: '1', from: 'COCA COLA', to: 'Coca Cola' },
    ]);
  });

  it('produces the same catalog whatever the order of the rows', () => {
    const rows = [
      row({
        sku: '3',
        name: 'C',
        brand: 'X',
        image_url: 'i3',
        product_url: 'u3',
      }),
      row({ sku: '1', name: 'A', image_url: 'i1', product_url: 'u1' }),
      row({
        sku: '2',
        name: 'A',
        brand: 'Y',
        image_url: 'i2',
        product_url: 'u2',
      }),
      row({
        sku: '4',
        name: 'A',
        brand: 'Y ',
        image_url: 'i4',
        product_url: 'u4',
      }),
    ];
    const first = convert(rows);
    const second = convert([...rows].reverse());
    expect(second.catalog).toEqual(first.catalog);
    expect(second.report.skuToSlug).toEqual(first.report.skuToSlug);
  });

  it('is accepted by the importer’s own validation', () => {
    const { catalog } = convert([
      row({ sku: '1', name: 'Ketchup', brand: 'HEINZ' }),
      row({
        sku: '2',
        name: 'Ketchup',
        brand: 'AMORA',
        image_url: 'i2',
        product_url: 'u2',
      }),
      row({
        sku: '3',
        name: 'Ketchup',
        image_url: 'https://x.test/3.webp',
        product_url: 'u3',
      }),
      row({
        sku: '4',
        name: 'Ananas',
        category: 'Le marché > Fruits de saison',
        image_url: 'https://x.test/4.webp',
        product_url: 'u4',
      }),
    ]);
    const parsed = parseCatalog(JSON.parse(JSON.stringify(catalog)));
    expect(parsed.errors).toEqual([]);
    const all = parsed.catalog!.categories.flatMap((c) => c.products);
    expect(all.find((p) => p.slug === 'ananas')).toMatchObject({
      defaultSaleUnit: 'KG',
      // Left to the importer's per-unit defaults.
      defaultMinQuantity: 100,
      defaultQuantityStep: 100,
      defaultMaxQuantity: null,
    });
    expect(all.find((p) => p.slug === 'ketchup-heinz')).toMatchObject({
      defaultSaleUnit: 'PIECE',
      defaultMinQuantity: 1,
      defaultQuantityStep: 1,
    });
  });

  it('counts every row exactly once', () => {
    const { report } = convert([
      row({ sku: '1' }),
      row({ sku: '1', product_url: 'u' }),
      row({ sku: '2', name: '', product_url: 'u2' }),
      row({ sku: '3', category: 'Jardin', product_url: 'u3' }),
      row({ sku: '4', name: 'Z', product_url: 'u4' }),
    ]);
    expect(
      report.convertedProducts +
        report.excludedProducts.count +
        report.duplicateProducts.count,
    ).toBe(report.sourceRows);
  });
});
