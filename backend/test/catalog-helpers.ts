import { importCatalog } from '../src/catalog/catalog-import.js';
import { db } from '../src/prisma/db.js';
import { fixtureCatalog } from './catalog-fixture.js';

/**
 * Catalog rows are global and shared by every suite, so each suite seeds its
 * own tagged slice (through the real importer) and removes it at the end.
 */

export async function seedCatalog(tag: string) {
  const report = await importCatalog(fixtureCatalog(tag), { dryRun: false });
  expect(report.errors).toEqual([]);

  const products = await db.orm.public.Product.all();
  const categories = await db.orm.public.Category.all();
  const productId = (slug: string) => {
    const row = products.find((p) => p.slug === `${tag}-${slug}`);
    if (!row) throw new Error(`fixture product ${slug} missing`);
    return row.id;
  };
  const categoryId = (slug: string) => {
    const row = categories.find((c) => c.slug === `${tag}-${slug}`);
    if (!row) throw new Error(`fixture category ${slug} missing`);
    return row.id;
  };
  return { productId, categoryId };
}

/** Call after `stopApp()` — the store products that reference these rows are gone by then. */
export async function removeCatalog(tag: string) {
  for (const product of await db.orm.public.Product.all()) {
    if (product.slug.startsWith(`${tag}-`)) {
      await db.orm.public.Product.select('id')
        .where({ id: product.id })
        .delete();
    }
  }
  for (const category of await db.orm.public.Category.all()) {
    if (category.slug.startsWith(`${tag}-`)) {
      await db.orm.public.Category.select('id')
        .where({ id: category.id })
        .delete();
    }
  }
}

/** Marks a catalog row archived behind the API's back (only the importer does that for real). */
export const archiveProduct = (id: number) =>
  db.orm.public.Product.where({ id }).update({
    archivedAt: new Date().toISOString(),
  });
export const archiveCategory = (id: number) =>
  db.orm.public.Category.where({ id }).update({
    archivedAt: new Date().toISOString(),
  });
