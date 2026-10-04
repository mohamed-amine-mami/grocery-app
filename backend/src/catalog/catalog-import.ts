import { db } from '../prisma/db.js';
import { SaleUnit } from '../products/sale-unit.enum.js';
import { parseCatalog } from './catalog-file.js';
import {
  planCatalog,
  type CatalogPlan,
  type Counts,
  type ExistingCatalog,
} from './catalog-plan.js';

/**
 * Reads the catalog tables, plans, and — unless it is a dry run — writes the
 * plan in ONE transaction: either the whole file lands or nothing does.
 *
 * Only `Category` and `Product` are ever written. `StoreProduct` is read (for
 * warnings) and never touched, so a store's price, unit, stock, availability
 * and quantity rules cannot be affected by what the catalog says.
 */

export interface ImportReport {
  dryRun: boolean;
  categories: Counts;
  products: Counts;
  warnings: string[];
  errors: string[];
}

const noCounts = (): Counts => ({
  created: 0,
  updated: 0,
  unchanged: 0,
  archived: 0,
});

const failed = (errors: string[], dryRun: boolean): ImportReport => ({
  dryRun,
  categories: noCounts(),
  products: noCounts(),
  warnings: [],
  errors,
});

/** `db` and a transaction's `tx` both expose the same ORM. */
type Client = Pick<typeof db, 'orm'>;

async function loadExisting(client: Client): Promise<ExistingCatalog> {
  const { Category, Product, StoreProduct } = client.orm.public;
  // Sequential on purpose: inside a transaction there is a single connection.
  const categories = await Category.all();
  const products = await Product.all();
  const offerings = await StoreProduct.where((row) =>
    row.archivedAt.isNull(),
  ).all();
  return {
    categories: categories.map((c) => ({
      id: c.id,
      slug: c.slug,
      name: c.name,
      description: c.description,
      photo: c.photo,
      archivedAt: c.archivedAt,
    })),
    products: products.map((p) => ({
      id: p.id,
      slug: p.slug,
      categoryId: p.categoryId,
      name: p.name,
      description: p.description,
      photo: p.photo,
      defaultSaleUnit: p.defaultSaleUnit as SaleUnit,
      defaultMinQuantity: p.defaultMinQuantity,
      defaultQuantityStep: p.defaultQuantityStep,
      defaultMaxQuantity: p.defaultMaxQuantity,
      archivedAt: p.archivedAt,
    })),
    offerings: offerings.map((o) => ({
      productId: o.productId,
      storeId: o.storeId,
      saleUnit: o.saleUnit as SaleUnit,
    })),
  };
}

async function writePlan(client: Client, plan: CatalogPlan): Promise<void> {
  const { Category, Product } = client.orm.public;

  const categoryIds = new Map<string, number>();
  for (const action of plan.categories) {
    if (action.id !== undefined) categoryIds.set(action.slug, action.id);
  }

  for (const action of plan.categories) {
    if (action.kind === 'create' && action.create) {
      const row = await Category.create({
        slug: action.slug,
        ...action.create,
      });
      categoryIds.set(action.slug, row.id);
    } else if (action.id !== undefined && action.kind !== 'unchanged') {
      await Category.where({ id: action.id }).update(action.changes ?? {});
    }
  }

  const categoryIdFor = (slug: string): number => {
    const id = categoryIds.get(slug);
    if (id === undefined) {
      throw new Error(
        `Category "${slug}" has no id — the plan is inconsistent`,
      );
    }
    return id;
  };

  // Updates and archives first, so a name freed by an archive or a rename is
  // available to the creates below.
  for (const action of plan.products) {
    if (action.id === undefined || action.kind === 'unchanged') continue;
    const { categorySlug, ...columns } = action.changes ?? {};
    await Product.where({ id: action.id }).update({
      ...columns,
      ...(categorySlug === undefined
        ? {}
        : { categoryId: categoryIdFor(categorySlug) }),
    });
  }
  for (const action of plan.products) {
    if (action.kind === 'create' && action.create) {
      await Product.create({
        slug: action.slug,
        categoryId: categoryIdFor(action.categorySlug),
        ...action.create,
      });
    }
  }
}

function sqlState(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null
    ? (error as { sqlState?: string }).sqlState
    : undefined;
}

export async function importCatalog(
  input: unknown,
  options: { dryRun: boolean; now?: string },
): Promise<ImportReport> {
  const { dryRun } = options;
  const parsed = parseCatalog(input);
  if (parsed.catalog === null) {
    return failed(parsed.errors, dryRun);
  }
  const catalog = parsed.catalog;
  const now = options.now ?? new Date().toISOString();

  const report = (plan: CatalogPlan): ImportReport => ({
    dryRun,
    categories: plan.categoryCounts,
    products: plan.productCounts,
    warnings: plan.warnings,
    errors: plan.errors,
  });

  if (dryRun) {
    const plan = planCatalog(catalog, await loadExisting(db), now);
    return report(plan);
  }

  try {
    return await db.transaction(async (tx) => {
      const plan = planCatalog(catalog, await loadExisting(tx), now);
      if (plan.errors.length > 0) {
        return report(plan);
      }
      await writePlan(tx, plan);
      return report(plan);
    });
  } catch (error) {
    if (sqlState(error) === '23505') {
      // E.g. two entries swapping names: valid in the end, but not one write at a time.
      return failed(
        [
          'A name conflict occurred while writing (for example two products swapping names). Nothing was written — split the rename into two imports.',
        ],
        dryRun,
      );
    }
    throw error;
  }
}

export function formatReport(
  report: ImportReport,
  context: { database: string; file: string },
): string {
  const line = (label: string, c: Counts) =>
    `${label} created ${c.created}, updated ${c.updated}, unchanged ${c.unchanged}, archived ${c.archived}`;
  const lines = [
    `GrocerGo catalog import${report.dryRun ? ' — DRY RUN, nothing is written' : ''}`,
    `Database: ${context.database}`,
    `File:     ${context.file}`,
    '',
  ];
  if (report.errors.length === 0) {
    lines.push(line('Categories:', report.categories));
    lines.push(line('Products:  ', report.products));
  }
  lines.push('', `Warnings (${report.warnings.length})`);
  for (const warning of report.warnings) lines.push(`  - ${warning}`);
  lines.push(`Errors (${report.errors.length})`);
  for (const error of report.errors) lines.push(`  - ${error}`);
  if (report.errors.length > 0) {
    lines.push('', 'Nothing was written.');
  } else if (report.dryRun) {
    lines.push('', 'Dry run complete — run without --dry-run to apply.');
  } else {
    lines.push('', 'Import complete.');
  }
  return lines.join('\n');
}
