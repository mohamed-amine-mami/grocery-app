import { readFileSync } from 'node:fs';
const D = '/Users/medamine/projects/grocery-app/backend/dist/catalog/';
const { parseCatalog } = await import(D + 'catalog-file.js');
const { planCatalog } = await import(D + 'catalog-plan.js');
const file = process.argv[2], snapFile = process.argv[3];
const input = JSON.parse(readFileSync(file, 'utf8'));
const parsed = parseCatalog(input);
const out = { parseErrors: parsed.errors.slice(0, 60), parseErrorCount: parsed.errors.length };
if (parsed.catalog) {
  const snap = JSON.parse(readFileSync(snapFile, 'utf8'));
  const existing = { brands: snap.brands, categories: snap.categories, products: snap.products, offerings: snap.offerings };
  const plan = planCatalog(parsed.catalog, existing, '2026-10-10T00:00:00.000Z');
  out.counts = { brands: plan.brandCounts, categories: plan.categoryCounts, products: plan.productCounts };
  out.warnings = plan.warnings; out.planErrors = plan.errors;
  out.updatedProducts = plan.products.filter(a => a.kind === 'update' || a.kind === 'archive').map(a => ({ slug: a.slug, kind: a.kind, changes: a.changes }));
  out.categoryActions = plan.categories.filter(a => a.kind !== 'create').map(a => ({ slug: a.slug, kind: a.kind, changes: a.changes }));
  out.totals = { brands: parsed.catalog.brands.length, categories: parsed.catalog.categories.length, products: parsed.catalog.categories.reduce((n, c) => n + c.products.length, 0) };
}
console.log(JSON.stringify(out, null, 1));
