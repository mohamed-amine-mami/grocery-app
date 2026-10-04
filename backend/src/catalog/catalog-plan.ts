import { allowedSaleUnits } from '../products/product-rules.js';
import { SaleUnit } from '../products/sale-unit.enum.js';
import type { Catalog } from './catalog-file.js';

/**
 * Compares a validated catalog file with what the database holds and decides
 * what the import would do. Pure: it never reads or writes anything, which is
 * what lets `--dry-run` and the real run share exactly the same decisions.
 *
 * Entries are matched by slug, never by name. `StoreProduct` is only ever
 * *read* here (to warn) — the importer has no way to change an offering.
 */

export interface ExistingCategory {
  id: number;
  slug: string;
  name: string;
  description: string | null;
  photo: string | null;
  archivedAt: string | null;
}

export interface ExistingProduct {
  id: number;
  slug: string;
  categoryId: number;
  name: string;
  description: string | null;
  photo: string | null;
  defaultSaleUnit: SaleUnit;
  defaultMinQuantity: number;
  defaultQuantityStep: number;
  defaultMaxQuantity: number | null;
  archivedAt: string | null;
}

/** An active store offering — enough to warn about the stores an archive would affect. */
export interface ExistingOffering {
  productId: number;
  storeId: number;
  saleUnit: SaleUnit;
}

export interface ExistingCatalog {
  categories: ExistingCategory[];
  products: ExistingProduct[];
  offerings: ExistingOffering[];
}

export type ActionKind = 'create' | 'update' | 'archive' | 'unchanged';

export interface CategoryColumns {
  name: string;
  description: string | null;
  photo: string | null;
  archivedAt: string | null;
}

export interface ProductColumns {
  name: string;
  description: string | null;
  photo: string | null;
  defaultSaleUnit: SaleUnit;
  defaultMinQuantity: number;
  defaultQuantityStep: number;
  defaultMaxQuantity: number | null;
  archivedAt: string | null;
}

/** A create carries every column; an update or archive only the ones that change. */
export interface CategoryAction {
  kind: ActionKind;
  slug: string;
  id?: number;
  create?: CategoryColumns;
  changes?: Partial<CategoryColumns>;
}

export interface ProductAction {
  kind: ActionKind;
  slug: string;
  id?: number;
  /** The category the product ends up in (the one it is nested under). */
  categorySlug: string;
  create?: ProductColumns;
  /** `categorySlug` is set here only when an existing product moves category. */
  changes?: Partial<ProductColumns> & { categorySlug?: string };
}

export interface Counts {
  created: number;
  updated: number;
  unchanged: number;
  archived: number;
}

export interface CatalogPlan {
  categories: CategoryAction[];
  products: ProductAction[];
  categoryCounts: Counts;
  productCounts: Counts;
  warnings: string[];
  errors: string[];
}

const emptyCounts = (): Counts => ({
  created: 0,
  updated: 0,
  unchanged: 0,
  archived: 0,
});

function tally(actions: { kind: ActionKind }[]): Counts {
  const counts = emptyCounts();
  for (const { kind } of actions) {
    if (kind === 'create') counts.created += 1;
    else if (kind === 'update') counts.updated += 1;
    else if (kind === 'archive') counts.archived += 1;
    else counts.unchanged += 1;
  }
  return counts;
}

/** The columns of `wanted` whose value differs from `current`. */
function changedColumns<T extends object>(
  current: T,
  wanted: Partial<T>,
): Partial<T> {
  const changes: Partial<T> = {};
  for (const key of Object.keys(wanted) as (keyof T)[]) {
    if (current[key] !== wanted[key]) changes[key] = wanted[key];
  }
  return changes;
}

/** Applies the file's `archived` flag on top of the other changes. */
function withArchiveState(
  changes: { archivedAt?: string | null },
  currentArchivedAt: string | null,
  archived: boolean,
  now: string,
): ActionKind {
  if (archived && currentArchivedAt === null) {
    changes.archivedAt = now;
    return 'archive';
  }
  if (!archived && currentArchivedAt !== null) {
    changes.archivedAt = null; // restored
    return 'update';
  }
  return Object.keys(changes).length > 0 ? 'update' : 'unchanged';
}

const listSome = (slugs: string[]) =>
  slugs.length <= 10
    ? slugs.join(', ')
    : `${slugs.slice(0, 10).join(', ')}, … (${slugs.length - 10} more)`;

export function planCatalog(
  catalog: Catalog,
  existing: ExistingCatalog,
  now: string,
): CatalogPlan {
  const categoryBySlug = new Map(existing.categories.map((c) => [c.slug, c]));
  const categoryById = new Map(existing.categories.map((c) => [c.id, c]));
  const productBySlug = new Map(existing.products.map((p) => [p.slug, p]));

  const categories: CategoryAction[] = [];
  const products: ProductAction[] = [];

  for (const category of catalog.categories) {
    const row = categoryBySlug.get(category.slug);
    const values = {
      name: category.name,
      description: category.description,
      photo: category.photo,
    };
    if (!row) {
      categories.push({
        kind: 'create',
        slug: category.slug,
        create: { ...values, archivedAt: category.archived ? now : null },
      });
    } else {
      const changes = changedColumns<CategoryColumns>(row, values);
      const kind = withArchiveState(
        changes,
        row.archivedAt,
        category.archived,
        now,
      );
      categories.push({ kind, slug: category.slug, id: row.id, changes });
    }

    for (const product of category.products) {
      const productRow = productBySlug.get(product.slug);
      const productValues = {
        name: product.name,
        description: product.description,
        photo: product.photo,
        defaultSaleUnit: product.defaultSaleUnit,
        defaultMinQuantity: product.defaultMinQuantity,
        defaultQuantityStep: product.defaultQuantityStep,
        defaultMaxQuantity: product.defaultMaxQuantity,
      };
      if (!productRow) {
        products.push({
          kind: 'create',
          slug: product.slug,
          categorySlug: category.slug,
          create: {
            ...productValues,
            archivedAt: product.archived ? now : null,
          },
        });
        continue;
      }
      const changes: Partial<ProductColumns> & { categorySlug?: string } =
        changedColumns<ProductColumns>(productRow, productValues);
      if (categoryById.get(productRow.categoryId)?.slug !== category.slug) {
        changes.categorySlug = category.slug; // moved; resolved to an id when written
      }
      const kind = withArchiveState(
        changes,
        productRow.archivedAt,
        product.archived,
        now,
      );
      products.push({
        kind,
        slug: product.slug,
        id: productRow.id,
        categorySlug: category.slug,
        changes,
      });
    }
  }

  const errors = nameCollisions(catalog, existing);
  const warnings =
    errors.length > 0
      ? []
      : planWarnings(catalog, existing, categories, products);

  return {
    categories,
    products,
    categoryCounts: tally(categories),
    productCounts: tally(products),
    warnings,
    errors,
  };
}

/**
 * Active names are unique in the database, and rows the file doesn't mention
 * keep their names — so a file can clash with a row it never lists.
 */
function nameCollisions(catalog: Catalog, existing: ExistingCatalog): string[] {
  const errors: string[] = [];

  const check = (
    label: string,
    inFile: { slug: string; name: string; archived: boolean }[],
    stored: { slug: string; name: string; archivedAt: string | null }[],
  ) => {
    const fileSlugs = new Set(inFile.map((entry) => entry.slug));
    const holders = new Map<string, string>();
    const claim = (name: string, slug: string) => {
      const key = name.toLowerCase();
      const holder = holders.get(key);
      if (holder !== undefined && holder !== slug) {
        errors.push(
          `${label} name "${name}" would be used by both "${holder}" and "${slug}"`,
        );
      }
      holders.set(key, slug);
    };
    for (const row of stored) {
      if (!fileSlugs.has(row.slug) && row.archivedAt === null) {
        claim(row.name, row.slug);
      }
    }
    for (const entry of inFile) {
      if (!entry.archived) claim(entry.name, entry.slug);
    }
  };

  check('Category', catalog.categories, existing.categories);
  check(
    'Product',
    catalog.categories.flatMap((category) => category.products),
    existing.products,
  );
  return errors;
}

function planWarnings(
  catalog: Catalog,
  existing: ExistingCatalog,
  categories: CategoryAction[],
  products: ProductAction[],
): string[] {
  const warnings: string[] = [];
  const offeringsOf = (productId: number) =>
    existing.offerings.filter((offering) => offering.productId === productId);
  const storeCount = (productIds: number[]) =>
    new Set(
      existing.offerings
        .filter((offering) => productIds.includes(offering.productId))
        .map((offering) => offering.storeId),
    ).size;

  for (const action of products) {
    if (action.id === undefined) continue;
    if (action.kind === 'archive') {
      const stores = storeCount([action.id]);
      if (stores > 0) {
        warnings.push(
          `Archiving product "${action.slug}" while ${stores} store(s) still sell it: their offerings stay as configured, but customers can no longer order it`,
        );
      }
    }
    const newUnit = action.changes?.defaultSaleUnit;
    if (newUnit !== undefined) {
      const outside = offeringsOf(action.id).filter(
        (offering) => !allowedSaleUnits(newUnit).includes(offering.saleUnit),
      );
      if (outside.length > 0) {
        warnings.push(
          `Product "${action.slug}" now defaults to ${newUnit}, but ${outside.length} store offering(s) are sold in a unit that is no longer allowed for it (they are not changed)`,
        );
      }
    }
  }

  const archivedCategorySlugs = new Set(
    categories.filter((a) => a.kind === 'archive').map((a) => a.slug),
  );
  for (const slug of archivedCategorySlugs) {
    const inCategory = existing.products.filter((p) => {
      const category = existing.categories.find((c) => c.id === p.categoryId);
      return category?.slug === slug && p.archivedAt === null;
    });
    const stores = storeCount(inCategory.map((p) => p.id));
    if (stores > 0) {
      warnings.push(
        `Archiving category "${slug}" while ${stores} store(s) sell products in it: customers can no longer order them through this category`,
      );
    }
  }

  const fileProductSlugs = new Set(
    catalog.categories.flatMap((c) => c.products.map((p) => p.slug)),
  );
  const fileCategorySlugs = new Set(catalog.categories.map((c) => c.slug));
  const missingProducts = existing.products
    .filter((p) => !fileProductSlugs.has(p.slug))
    .map((p) => p.slug);
  const missingCategories = existing.categories
    .filter((c) => !fileCategorySlugs.has(c.slug))
    .map((c) => c.slug);
  if (missingProducts.length > 0) {
    warnings.push(
      `${missingProducts.length} catalog product(s) are not in the file and were left unchanged: ${listSome(missingProducts)}`,
    );
  }
  if (missingCategories.length > 0) {
    warnings.push(
      `${missingCategories.length} catalog categor${missingCategories.length === 1 ? 'y is' : 'ies are'} not in the file and were left unchanged: ${listSome(missingCategories)}`,
    );
  }
  return warnings;
}
