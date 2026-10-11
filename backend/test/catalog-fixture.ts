/**
 * A small deterministic catalog for the importer tests — never the real
 * `seed/catalog.json`. `tag` makes every slug and name unique so suites that
 * share one database cannot collide; with no tag the names are plain.
 */
export interface FixtureCatalog {
  brands?: { slug: string; name: string }[];
  categories: {
    slug: string;
    name: string;
    products: Record<string, unknown>[];
  }[];
}

export function fixtureCatalog(tag = ''): FixtureCatalog {
  const slug = (value: string) => (tag ? `${tag}-${value}` : value);
  const name = (value: string) => (tag ? `${value} ${tag}` : value);
  return {
    categories: [
      {
        slug: slug('fruits'),
        name: name('Fruits'),
        products: [
          {
            slug: slug('banane'),
            name: name('Banane'),
            defaultSaleUnit: 'KG',
            defaultMinQuantity: 100,
            defaultQuantityStep: 100,
            defaultMaxQuantity: 10_000,
          },
        ],
      },
      {
        slug: slug('laitiers'),
        name: name('Produits laitiers'),
        products: [
          {
            slug: slug('lait-delice-1l'),
            name: name('Lait Délice 1 L'),
            defaultSaleUnit: 'PIECE',
          },
          {
            slug: slug('yaourt'),
            name: name('Yaourt nature'),
            description: 'Pot individuel',
            defaultSaleUnit: 'PIECE',
            defaultMaxQuantity: 24,
          },
        ],
      },
    ],
  };
}
