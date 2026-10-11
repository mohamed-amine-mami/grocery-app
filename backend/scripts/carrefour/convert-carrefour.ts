/**
 * `npm run catalog:convert-carrefour [-- --csv <path>] [-- --out <dir>]`
 *
 * Carrefour CSV → a GrocerGo catalog file for the existing importer, plus a
 * conversion report. It never touches the database and never downloads an
 * image: the Carrefour image URL is kept as the product photo.
 *
 * The result is checked with the importer's own file validation (`parseCatalog`)
 * before anything is written; a file that fails it is not produced.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isURL } from 'class-validator';
import { parseCatalog } from '../../dist/catalog/catalog-file.js';
import { PHOTO_URL_OPTIONS, URL_MAX_LENGTH } from '../../dist/common/limits.js';
// Node runs this file directly, so the import names the .ts file; tsc objects to that.
// @ts-expect-error TS5097
import { convertCarrefour, parseCsv } from './lib.ts';

const here = dirname(fileURLToPath(import.meta.url));

function readArguments(argv: string[]) {
  let csv = resolve(here, '../../../carrefour_food_500.csv');
  let out = resolve(here, '../../seed/carrefour');
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--csv' && argv[i + 1]) csv = resolve(argv[(i += 1)]!);
    else if (argv[i] === '--out' && argv[i + 1]) out = resolve(argv[(i += 1)]!);
    else
      throw new Error(
        `Unknown argument "${argv[i]}". Usage: [--csv <path>] [--out <dir>]`,
      );
  }
  return { csv, out };
}

const { csv, out } = readArguments(process.argv.slice(2));
const rows = parseCsv(readFileSync(csv, 'utf8'));

const { catalog, report } = convertCarrefour(rows, {
  // The importer's own photo rule.
  isValidPhoto: (url) =>
    url.length <= URL_MAX_LENGTH && isURL(url, PHOTO_URL_OPTIONS),
});

// Where a converted product has the slug of one the development catalog
// (`seed/catalog.json`) already defines, the importer sees the same product and
// would update it. Read from the file only; the database is not consulted.
interface SeedCatalog {
  categories: {
    slug: string;
    products: {
      slug: string;
      name: string;
      defaultSaleUnit: string;
      defaultMinQuantity?: number;
      defaultQuantityStep?: number;
      defaultMaxQuantity?: number | null;
    }[];
  }[];
}
const seed = JSON.parse(
  readFileSync(resolve(here, '../../seed/catalog.json'), 'utf8'),
) as SeedCatalog;
const seedBySlug = new Map(
  seed.categories.flatMap((c) =>
    c.products.map((p) => [p.slug, { ...p, category: c.slug }] as const),
  ),
);
const unitDefaults = { KG: [100, 100], PIECE: [1, 1], L: [100, 100] } as const;
const overlap = catalog.categories.flatMap((category) =>
  category.products.flatMap((product) => {
    const existing = seedBySlug.get(product.slug);
    if (!existing) return [];
    const changes: string[] = [];
    if (existing.name !== product.name)
      changes.push(`name "${existing.name}" → "${product.name}"`);
    if (existing.defaultSaleUnit !== product.defaultSaleUnit) {
      changes.push(
        `sale unit ${existing.defaultSaleUnit} → ${product.defaultSaleUnit}`,
      );
    }
    if (existing.category !== category.slug)
      changes.push(`category ${existing.category} → ${category.slug}`);
    const [min, step] = unitDefaults[product.defaultSaleUnit];
    if (
      (existing.defaultMinQuantity ?? min) !== min ||
      (existing.defaultQuantityStep ?? step) !== step ||
      (existing.defaultMaxQuantity ?? null) !== null
    ) {
      changes.push(
        `default quantities ${existing.defaultMinQuantity ?? min}/${existing.defaultQuantityStep ?? step}/${existing.defaultMaxQuantity ?? 'no max'} → unit defaults ${min}/${step}/no max`,
      );
    }
    changes.push('photo set');
    return [{ slug: product.slug, changes }];
  }),
);
const reportWithOverlap = {
  ...report,
  overlapWithSeedCatalog: {
    note: 'same slug as a product of seed/catalog.json: the importer treats it as the same product and would update it',
    count: overlap.length,
    items: overlap,
  },
};

// The importer's own validation: nothing is written unless it accepts the file.
const parsed = parseCatalog(JSON.parse(JSON.stringify(catalog)));
if (parsed.catalog === null) {
  console.error(
    `The generated catalog is not valid (${parsed.errors.length} errors):`,
  );
  for (const error of parsed.errors.slice(0, 40)) console.error(`  - ${error}`);
  process.exit(1);
}
const parsedProducts = parsed.catalog.categories.reduce(
  (sum, c) => sum + c.products.length,
  0,
);
if (parsedProducts !== report.convertedProducts) {
  console.error(
    `Validation saw ${parsedProducts} products, the converter made ${report.convertedProducts}.`,
  );
  process.exit(1);
}

mkdirSync(out, { recursive: true });
const write = (name: string, content: string) => {
  writeFileSync(resolve(out, name), content);
  console.log(`wrote ${resolve(out, name)}`);
};
write(
  'carrefour_grocergo_catalog.json',
  `${JSON.stringify(catalog, null, 2)}\n`,
);
write(
  'carrefour_grocergo_conversion_report.json',
  `${JSON.stringify(reportWithOverlap, null, 2)}\n`,
);

const table = (header: string[], body: (string | number)[][]) =>
  [
    `| ${header.join(' | ')} |`,
    `| ${header.map(() => '---').join(' | ')} |`,
    ...body.map((row) => `| ${row.join(' | ')} |`),
  ].join('\n');

const summary = [
  '# Carrefour → GrocerGo catalog conversion',
  '',
  `Source: \`${csv}\``,
  '',
  table(
    ['', ''],
    [
      ['CSV rows', report.sourceRows],
      ['Converted products', report.convertedProducts],
      ['Excluded', report.excludedProducts.count],
      ['Duplicates removed', report.duplicateProducts.count],
      ['Unique brands', report.brands.unique],
      ['Brandless products', report.brands.brandlessProducts],
      ['Valid photo URLs', report.validPhotos],
      [
        'Missing / invalid photos',
        `${report.missingPhotos.count} / ${report.invalidPhotos.count}`,
      ],
      ['Slug collisions', report.slugCollisions.count],
    ],
  ),
  '',
  '## Categories',
  '',
  table(
    ['GrocerGo category', 'Slug', 'Products'],
    report.categories.grocerGo.map((c) => [
      c.name,
      `\`${c.slug}\``,
      c.products,
    ]),
  ),
  '',
  `Unmapped Carrefour categories: ${report.unmappedCategories.length}`,
  '',
  '## Sale units',
  '',
  table(
    ['Unit', 'Products'],
    Object.entries(report.unitClassification.totals).map(([unit, count]) => [
      unit,
      count,
    ]),
  ),
  '',
  table(
    ['Rule', 'Unit', 'Confidence', 'Products', 'Examples'],
    report.unitClassification.rules.map((r) => [
      `\`${r.rule}\``,
      r.unit,
      r.confidence,
      r.products,
      r.examples.join('; '),
    ]),
  ),
  '',
  `Products with the slug of a development-catalog product (the importer would update them): ${overlap.length} — see the JSON report.`,
  '',
  `Products to review: ${report.unitClassification.needsReview.count} (listed in the JSON report; they are in the catalog with the unit shown).`,
  '',
  'Price, stock, availability and quantity rules are not part of this catalog: the owner sets them on the store product.',
  '',
].join('\n');
write('carrefour_grocergo_conversion_summary.md', summary);

console.log(
  `\n${report.sourceRows} rows → ${report.convertedProducts} products, ${report.brands.unique} brands, ${report.categories.grocerGo.length} categories (validated by the importer's parser).`,
);
