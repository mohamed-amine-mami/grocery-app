/**
 * Carrefour CSV → GrocerGo catalog file, as pure functions: no file system, no
 * database, no GrocerGo code. The CLI (`convert-carrefour.ts`) reads the CSV,
 * calls `convertCarrefour`, validates the result with the importer's own
 * `parseCatalog`, and writes the files.
 *
 * The conversion adapts the CSV to the catalog format that exists; nothing
 * here asks for a new column or a new rule.
 */

// ── CSV ────────────────────────────────────────────────────────────────────

/** RFC 4180 parsing: quoted fields, doubled quotes, commas and newlines inside quotes. */
export function parseCsv(text: string): Record<string, string>[] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;
  const source = text.replace(/^﻿/, '');
  for (let i = 0; i < source.length; i += 1) {
    const char = source[i]!;
    if (inQuotes) {
      if (char === '"') {
        if (source[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += char;
      }
    } else if (char === '"') {
      inQuotes = true;
    } else if (char === ',') {
      row.push(field);
      field = '';
    } else if (char === '\n' || char === '\r') {
      if (char === '\r' && source[i + 1] === '\n') i += 1;
      row.push(field);
      field = '';
      if (row.some((value) => value !== '')) rows.push(row);
      row = [];
    } else {
      field += char;
    }
  }
  row.push(field);
  if (row.some((value) => value !== '')) rows.push(row);

  const [header, ...body] = rows;
  if (!header) return [];
  return body.map((values) =>
    Object.fromEntries(header.map((key, index) => [key, values[index] ?? ''])),
  );
}

// ── Text normalisation ─────────────────────────────────────────────────────

/** Trims and collapses runs of whitespace. Nothing else is changed. */
export const cleanText = (value: string | undefined): string =>
  (value ?? '').replace(/\s+/g, ' ').trim();

/**
 * Lowercase ASCII, hyphen-separated: `Crème brûlée` → `creme-brulee`.
 * Accents are removed, ligatures expanded (œ → oe), apostrophes and degree
 * signs dropped (`L'EPI D'OR` → `lepi-dor`, `N°1` → `n1`), anything else that
 * is not a letter or digit becomes a separator. Matches the importer's slug
 * pattern `^[a-z0-9]+(-[a-z0-9]+)*$`.
 */
export function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/œ/g, 'oe')
    .replace(/æ/g, 'ae')
    .replace(/ß/g, 'ss')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/['’‘`´°%]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/** Folds for matching only (never for output). */
const fold = (value: string): string => slugify(value).replace(/-/g, ' ');

/** `COCA COLA` → `Coca Cola`; a name with any lowercase letter is left alone. */
export function fixAllCaps(name: string): string {
  if (
    name.length < 4 ||
    name !== name.toUpperCase() ||
    name === name.toLowerCase()
  ) {
    return name;
  }
  return name
    .toLowerCase()
    .replace(
      /(^|[\s'’-])(\p{L})/gu,
      (_, before: string, letter: string) => `${before}${letter.toUpperCase()}`,
    );
}

// ── Categories ─────────────────────────────────────────────────────────────

export interface GrocerCategory {
  slug: string;
  name: string;
}

/**
 * The flat GrocerGo categories. The first six keep the slug and name of the
 * categories the development catalog already has, so the importer sees them
 * as unchanged rather than as new ones.
 */
export const CATEGORIES: GrocerCategory[] = [
  { slug: 'fruits', name: 'Fruits' },
  { slug: 'legumes', name: 'Légumes' },
  { slug: 'viandes-poissons', name: 'Viandes et poissons' },
  { slug: 'produits-laitiers', name: 'Produits laitiers' },
  { slug: 'boulangerie', name: 'Boulangerie' },
  { slug: 'boissons', name: 'Boissons' },
  { slug: 'fromages', name: 'Fromages' },
  { slug: 'charcuterie-traiteur', name: 'Charcuterie et traiteur' },
  { slug: 'surgeles', name: 'Surgelés' },
  { slug: 'pates-riz-legumes-secs', name: 'Pâtes, riz et légumes secs' },
  { slug: 'conserves', name: 'Conserves et plats cuisinés' },
  { slug: 'thon-sardines', name: 'Thon et sardines' },
  { slug: 'huiles', name: 'Huiles' },
  { slug: 'sauces-condiments', name: 'Sauces et condiments' },
  { slug: 'epices-olives', name: 'Épices et olives' },
  { slug: 'fruits-secs', name: 'Fruits secs' },
  { slug: 'snacks-aperitif', name: 'Snacks et apéritif' },
  { slug: 'biscuits-gateaux', name: 'Biscuits et gâteaux' },
  { slug: 'chocolat-confiserie', name: 'Chocolat et confiserie' },
  { slug: 'petit-dejeuner', name: 'Petit déjeuner' },
  { slug: 'cafe-the', name: 'Café, thés et infusions' },
  { slug: 'sucre-farine', name: 'Sucre, farine et pâtisserie' },
];

interface PathRule {
  /** A Carrefour category path (segments joined by " > "). */
  path: string;
  /** `exact`: only this very path; `prefix`: it and everything below. */
  match: 'exact' | 'prefix';
  slug: string;
}

/** The most specific matching rule wins (exact over prefix, then the longest path). */
export const PATH_RULES: PathRule[] = [
  { path: 'Boissons', match: 'prefix', slug: 'boissons' },

  {
    path: 'Crèmerie et Produits Laitiers',
    match: 'prefix',
    slug: 'produits-laitiers',
  },
  {
    path: 'Crèmerie et Produits Laitiers > Fromages',
    match: 'prefix',
    slug: 'fromages',
  },
  {
    path: 'Crèmerie et Produits Laitiers > Fromages à la coupe',
    match: 'prefix',
    slug: 'fromages',
  },

  { path: 'Le marché > Fruits de saison', match: 'prefix', slug: 'fruits' },
  {
    path: 'Le marché > Fruits secs et séchés',
    match: 'prefix',
    slug: 'fruits-secs',
  },
  { path: 'Le marché > Légumes', match: 'prefix', slug: 'legumes' },
  {
    path: 'Le marché > Légumes > Légumes secs',
    match: 'prefix',
    slug: 'pates-riz-legumes-secs',
  },
  { path: 'Le marché > Boucherie', match: 'prefix', slug: 'viandes-poissons' },
  { path: 'Le marché > Volaille', match: 'prefix', slug: 'viandes-poissons' },
  { path: 'Le marché > Poissons', match: 'prefix', slug: 'viandes-poissons' },
  {
    path: 'Le marché > Charcuterie',
    match: 'prefix',
    slug: 'charcuterie-traiteur',
  },
  {
    path: 'Le marché > Traiteur',
    match: 'prefix',
    slug: 'charcuterie-traiteur',
  },
  {
    path: 'Le marché > Boulangerie et Pâtisserie',
    match: 'prefix',
    slug: 'boulangerie',
  },
  {
    path: 'Le marché > Épices, Olives et Condiments',
    match: 'prefix',
    slug: 'epices-olives',
  },
  {
    path: 'Le marché > Épices, Olives et Condiments > Condiments',
    match: 'prefix',
    slug: 'sauces-condiments',
  },

  { path: 'Surgelés', match: 'prefix', slug: 'surgeles' },

  {
    path: 'Épicerie Salée > Barquettes à garnir',
    match: 'prefix',
    slug: 'sucre-farine',
  },
  {
    path: 'Épicerie Salée > Blé et Semoule',
    match: 'prefix',
    slug: 'pates-riz-legumes-secs',
  },
  {
    path: 'Épicerie Salée > Conserves et Plats Cuisinés',
    match: 'prefix',
    slug: 'conserves',
  },
  {
    path: 'Épicerie Salée > Conserves et Plats Cuisinés > Condiments',
    match: 'prefix',
    slug: 'sauces-condiments',
  },
  { path: 'Épicerie Salée > Huiles', match: 'prefix', slug: 'huiles' },
  {
    path: 'Épicerie Salée > Pâtes Couscous et Riz',
    match: 'prefix',
    slug: 'pates-riz-legumes-secs',
  },
  {
    path: 'Épicerie Salée > Pâtes Couscous et Riz > Bouillons',
    match: 'prefix',
    slug: 'sauces-condiments',
  },
  {
    path: 'Épicerie Salée > Sauces et Assaisonnements',
    match: 'prefix',
    slug: 'sauces-condiments',
  },
  {
    path: 'Épicerie Salée > Snack et Apéritif',
    match: 'prefix',
    slug: 'snacks-aperitif',
  },
  {
    path: 'Épicerie Salée > Snack et Apéritif > Fruits Secs',
    match: 'prefix',
    slug: 'fruits-secs',
  },
  {
    path: 'Épicerie Salée > Thon et Sardine',
    match: 'prefix',
    slug: 'thon-sardines',
  },

  {
    path: 'Épicerie Sucrée > Biscuits',
    match: 'prefix',
    slug: 'biscuits-gateaux',
  },
  {
    path: 'Épicerie Sucrée > Bonbons et Chocolats',
    match: 'prefix',
    slug: 'chocolat-confiserie',
  },
  { path: 'Épicerie Sucrée > Café', match: 'prefix', slug: 'cafe-the' },
  {
    path: 'Épicerie Sucrée > Gâteaux Moelleux',
    match: 'prefix',
    slug: 'biscuits-gateaux',
  },
  {
    path: 'Épicerie Sucrée > Petit Déjeuner',
    match: 'prefix',
    slug: 'petit-dejeuner',
  },
  {
    path: 'Épicerie Sucrée > Sucre, Farine et Préparation Pâtisserie',
    match: 'prefix',
    slug: 'sucre-farine',
  },
  {
    path: 'Épicerie Sucrée > Thés et Infusions',
    match: 'prefix',
    slug: 'cafe-the',
  },

  // A few root-level paths, where the CSV gives no sub-category at all.
  { path: 'Le marché', match: 'exact', slug: 'charcuterie-traiteur' }, // the one "Mini salami de dinde"
];

interface NameRule {
  id: string;
  /** Only for products filed under exactly this Carrefour path (not below it). */
  under: string;
  /** Matched on the accent-folded, lowercase name. */
  pattern: RegExp;
  slug: string;
  why: string;
}

/**
 * Where the Carrefour category is plainly wrong or too vague for the product
 * it holds, the name decides. Each is reported; nothing is guessed silently.
 */
export const NAME_RULES: NameRule[] = [
  {
    id: 'misfiled-mustard',
    under:
      'Épicerie Salée > Conserves et Plats Cuisinés > Tomates concassées et pelées',
    pattern: /^moutarde\b/,
    slug: 'sauces-condiments',
    why: 'a mustard filed under crushed tomatoes',
  },
  {
    id: 'misfiled-garlic-sauce',
    under:
      'Épicerie Salée > Conserves et Plats Cuisinés > Tomates doubles concentrées',
    pattern: /^sauce\b/,
    slug: 'sauces-condiments',
    why: 'a sauce filed under tomato paste',
  },
  {
    id: 'cheese-without-subcategory',
    under: 'Crèmerie et Produits Laitiers',
    pattern: /^fromage\b/,
    slug: 'fromages',
    why: 'a cheese filed directly under the dairy root',
  },
  {
    id: 'sweet-root-candy',
    under: 'Épicerie Sucrée',
    pattern: /bonbon|gummy|candy/,
    slug: 'chocolat-confiserie',
    why: 'a sweet filed directly under the sweet-grocery root',
  },
  {
    id: 'sweet-root-cake-bar',
    under: 'Épicerie Sucrée',
    pattern: /\bcake\b|muffin|barre/,
    slug: 'biscuits-gateaux',
    why: 'a cake or bar filed directly under the sweet-grocery root',
  },
  {
    id: 'sweet-root-cereal',
    under: 'Épicerie Sucrée',
    pattern: /cereale|corn flakes|flocons|granola/,
    slug: 'petit-dejeuner',
    why: 'a cereal filed directly under the sweet-grocery root',
  },
];

const segmentsOf = (path: string) => path.split(' > ');

function matchesPath(
  path: string,
  rule: { path: string; match?: 'exact' | 'prefix' },
) {
  return rule.match === 'exact'
    ? path === rule.path
    : path === rule.path || path.startsWith(`${rule.path} > `);
}

export interface CategoryChoice {
  slug: string | null;
  /** The rule that decided: a path rule's path, or a name rule's id. */
  via: string;
  overridden: boolean;
}

export function mapCategory(path: string, name: string): CategoryChoice {
  const folded = fold(name);
  for (const rule of NAME_RULES) {
    if (path === rule.under && rule.pattern.test(folded)) {
      return { slug: rule.slug, via: rule.id, overridden: true };
    }
  }
  const candidates = PATH_RULES.filter((rule) => matchesPath(path, rule)).sort(
    (a, b) =>
      Number(b.match === 'exact') - Number(a.match === 'exact') ||
      segmentsOf(b.path).length - segmentsOf(a.path).length,
  );
  const best = candidates[0];
  return best
    ? { slug: best.slug, via: best.path, overridden: false }
    : { slug: null, via: '', overridden: false };
}

// ── Sale units ─────────────────────────────────────────────────────────────

export type Unit = 'PIECE' | 'KG' | 'L';
export type Confidence = 'high' | 'review';

interface UnitRule {
  id: string;
  description: string;
  unit: Unit;
  confidence: Confidence;
  /** Carrefour paths (prefix) this rule covers; omitted = any. */
  under?: string[];
  /** Matched on the folded name; omitted = any name. */
  name?: RegExp;
  /** Carrefour paths excluded from `under`. */
  except?: string[];
}

/**
 * First match wins. KG means "weighed": the catalog lets a store still sell a
 * KG product by the piece, while a PIECE product can never be sold by weight —
 * so wherever weight is plausible the rule says KG. `review` marks the
 * classifications a person should look at; they stay in the catalog.
 */
export const UNIT_RULES: UnitRule[] = [
  {
    id: 'loose-volume',
    description: 'a liquid sold loose, by name ("vrac", "au litre")',
    unit: 'L',
    confidence: 'review',
    under: ['Boissons', 'Épicerie Salée > Huiles'],
    name: /\bvrac\b|au litre/,
  },
  {
    id: 'market-produce',
    description: 'fresh fruit, vegetables and salads of the market (weighed)',
    unit: 'KG',
    confidence: 'high',
    under: [
      'Le marché > Fruits de saison',
      'Le marché > Légumes > Légumes de saison',
      'Le marché > Légumes > Salades et Tomates',
      'Le marché > Légumes > Légumes secs',
    ],
  },
  {
    id: 'market-packed-vegetables',
    description: 'vegetables already in trays or cleaned (weighed or by tray)',
    unit: 'KG',
    confidence: 'review',
    under: ['Le marché > Légumes > Légumes nettoyés emballés'],
  },
  {
    id: 'market-butcher-poultry-fish',
    description: 'butcher, poultry and whole fish / seafood (weighed)',
    unit: 'KG',
    confidence: 'high',
    under: [
      'Le marché > Boucherie',
      'Le marché > Volaille',
      'Le marché > Poissons > Poissons entiers',
      'Le marché > Poissons > Fruits de Mer',
    ],
  },
  {
    id: 'market-smoked-fish',
    description: 'smoked or fillet fish, often pre-sliced packs',
    unit: 'KG',
    confidence: 'review',
    under: ['Le marché > Poissons'],
  },
  {
    id: 'market-nuts-olives',
    description: 'dried fruit, nuts and olives of the market (weighed)',
    unit: 'KG',
    confidence: 'high',
    under: [
      'Le marché > Fruits secs et séchés',
      'Le marché > Épices, Olives et Condiments > Olives',
    ],
  },
  {
    id: 'market-spices-condiments',
    description:
      'spices, herbs and condiments of the market (weighed or by jar)',
    unit: 'KG',
    confidence: 'review',
    under: ['Le marché > Épices, Olives et Condiments'],
  },
  {
    id: 'market-deli',
    description: 'cold cuts of the market (weighed, or pre-packed slices)',
    unit: 'KG',
    confidence: 'review',
    under: ['Le marché > Charcuterie', 'Le marché'],
    // the bare "Le marché" root holds one salami
  },
  {
    id: 'cut-cheese',
    description: 'cheese "à la coupe": cut to order (weighed)',
    unit: 'KG',
    confidence: 'high',
    under: ['Crèmerie et Produits Laitiers > Fromages à la coupe'],
  },
  {
    id: 'counter-prepared',
    description:
      'fresh breaded poultry from the deli counter (weighed or by piece)',
    unit: 'KG',
    confidence: 'review',
    under: ['Le marché > Traiteur > Chaud'],
    name: /cordon bleu|nuggets/,
  },
  {
    id: 'bakery-and-deli-pieces',
    description:
      'bread, pastry, cakes, roast chicken, pizzas, prepared salads (by piece)',
    unit: 'PIECE',
    confidence: 'high',
    under: ['Le marché > Boulangerie et Pâtisserie', 'Le marché > Traiteur'],
  },
  {
    id: 'packaged',
    description:
      'everything else is a packaged product counted in units (a 1 L bottle, a 500 g pack, a jar)',
    unit: 'PIECE',
    confidence: 'high',
  },
];

export interface UnitChoice {
  unit: Unit;
  confidence: Confidence;
  rule: string;
}

export function classifyUnit(path: string, name: string): UnitChoice {
  const folded = fold(name);
  for (const rule of UNIT_RULES) {
    if (
      rule.under &&
      !rule.under.some((prefix) =>
        matchesPath(path, {
          path: prefix,
          match: prefix === 'Le marché' ? 'exact' : 'prefix',
        }),
      )
    ) {
      continue;
    }
    if (rule.except?.some((prefix) => matchesPath(path, { path: prefix })))
      continue;
    if (rule.name && !rule.name.test(folded)) continue;
    return { unit: rule.unit, confidence: rule.confidence, rule: rule.id };
  }
  // Unreachable: the last rule has no condition.
  return { unit: 'PIECE', confidence: 'review', rule: 'fallback' };
}

/** A weighed product whose name looks like a closed pack: worth a second look. */
const PACK_WORDS =
  /barquet|emball|slice|fume|pane|lot de|\ben boite\b|conserve/;
export const looksPacked = (name: string): boolean =>
  PACK_WORDS.test(fold(name));

// ── Conversion ─────────────────────────────────────────────────────────────

export interface SourceRow {
  sku: string;
  name: string;
  brand: string;
  category: string;
  image_url: string;
  product_url: string;
  source: string;
}

export interface ConvertOptions {
  /** The importer's photo rule (http(s) URL, within its length limit). */
  isValidPhoto: (url: string) => boolean;
  maxSlugLength?: number;
}

export interface CatalogProductOut {
  slug: string;
  name: string;
  brandSlug?: string;
  photo?: string;
  defaultSaleUnit: Unit;
}

export interface CatalogOut {
  brands: { slug: string; name: string }[];
  categories: {
    slug: string;
    name: string;
    products: CatalogProductOut[];
  }[];
}

const examples = (items: string[], count = 5) => items.slice(0, count);

export function convertCarrefour(
  rawRows: Record<string, string>[],
  options: ConvertOptions,
) {
  const maxSlug = options.maxSlugLength ?? 100;
  const rows: (SourceRow & { line: number })[] = rawRows.map((raw, index) => ({
    sku: cleanText(raw['sku']),
    name: cleanText(raw['name']),
    brand: cleanText(raw['brand']),
    category: cleanText(raw['category']).replace(/\s*>\s*/g, ' > '),
    image_url: cleanText(raw['image_url']),
    product_url: cleanText(raw['product_url']),
    source: cleanText(raw['source']),
    line: index + 2, // 1-based, after the header
  }));

  const excluded: {
    sku: string;
    line: number;
    name: string;
    reason: string;
  }[] = [];
  const duplicates: {
    kind: string;
    keptSku: string | null;
    discardedSku: string;
    name: string;
    brand: string;
    detail: string;
  }[] = [];

  // 1. Rows that cannot be a product at all.
  const usable = rows.filter((row) => {
    const reason = !row.name
      ? 'blank name'
      : !row.sku
        ? 'blank sku'
        : !row.category
          ? 'blank category'
          : null;
    if (reason)
      excluded.push({ sku: row.sku, line: row.line, name: row.name, reason });
    return reason === null;
  });

  // 2. The same SKU twice is the same product: keep the first.
  const seenSku = new Map<string, string>();
  const unique = usable.filter((row) => {
    if (seenSku.has(row.sku)) {
      duplicates.push({
        kind: 'same sku',
        keptSku: row.sku,
        discardedSku: row.sku,
        name: row.name,
        brand: row.brand,
        detail: `line ${row.line} repeats an earlier row`,
      });
      return false;
    }
    seenSku.set(row.sku, row.name);
    return true;
  });

  // The same product page twice is the same product too (keep the first).
  const seenUrl = new Map<string, string>();
  const distinct = unique.filter((row) => {
    const kept = row.product_url ? seenUrl.get(row.product_url) : undefined;
    if (kept !== undefined) {
      duplicates.push({
        kind: 'same product url',
        keptSku: kept,
        discardedSku: row.sku,
        name: row.name,
        brand: row.brand,
        detail: row.product_url,
      });
      return false;
    }
    if (row.product_url) seenUrl.set(row.product_url, row.sku);
    return true;
  });

  // 3. Brands: one per distinct slug. Spellings that slugify the same way are
  // obvious formatting variants and share one brand; the most frequent
  // spelling is kept as its name.
  const brandSpellings = new Map<string, Map<string, number>>();
  for (const row of distinct) {
    if (!row.brand) continue;
    const key = slugify(row.brand);
    const spellings = brandSpellings.get(key) ?? new Map<string, number>();
    spellings.set(row.brand, (spellings.get(row.brand) ?? 0) + 1);
    brandSpellings.set(key, spellings);
  }
  const brandNames = new Map<string, string>();
  const brandMerges: { slug: string; spellings: string[]; kept: string }[] = [];
  for (const [slug, spellings] of brandSpellings) {
    // Most used spelling; on a tie the one that keeps its accents, then alphabetical.
    const accents = (text: string) => text.replace(/[\x00-\x7f]/g, '').length;
    const ranked = [...spellings].sort(
      (a, b) =>
        b[1] - a[1] ||
        accents(b[0]) - accents(a[0]) ||
        a[0].localeCompare(b[0]),
    );
    brandNames.set(slug, ranked[0]![0]);
    if (spellings.size > 1) {
      brandMerges.push({
        slug,
        spellings: ranked.map(([s]) => s),
        kept: ranked[0]![0],
      });
    }
  }

  // 4. Product identity: the cleaned name, and the brand slug (or none).
  interface Draft {
    row: SourceRow & { line: number };
    name: string;
    nameChanged: boolean;
    brandSlug: string | null;
    categorySlug: string | null;
    categoryVia: string;
    categoryOverridden: boolean;
  }
  const drafts: Draft[] = distinct.map((row) => {
    const name = fixAllCaps(row.name);
    const category = mapCategory(row.category, name);
    return {
      row,
      name,
      nameChanged: name !== row.name,
      brandSlug: row.brand ? slugify(row.brand) : null,
      categorySlug: category.slug,
      categoryVia: category.via,
      categoryOverridden: category.overridden,
    };
  });

  const unmapped = drafts.filter((d) => d.categorySlug === null);
  const unmappedCategories = [
    ...new Map(unmapped.map((d) => [d.row.category, 0])).keys(),
  ].map((path) => ({
    category: path,
    products: unmapped
      .filter((d) => d.row.category === path)
      .map((d) => d.row.sku),
  }));
  for (const d of unmapped) {
    excluded.push({
      sku: d.row.sku,
      line: d.row.line,
      name: d.row.name,
      reason: `no GrocerGo category for "${d.row.category}"`,
    });
  }
  const mapped = drafts.filter((d) => d.categorySlug !== null);

  // 5. Two active products with the same name and the same brand cannot both
  // exist (the catalog's identity rule). They are duplicates: keep the lowest SKU.
  const identity = new Map<string, Draft>();
  const bySkuAscending = [...mapped].sort((a, b) =>
    a.row.sku.localeCompare(b.row.sku),
  );
  const duplicateSkus = new Set<string>();
  for (const draft of bySkuAscending) {
    const key = `${draft.name.toLowerCase()}\u0000${draft.brandSlug ?? ''}`;
    const kept = identity.get(key);
    if (kept) {
      duplicateSkus.add(draft.row.sku);
      duplicates.push({
        kind: 'same name and brand',
        keptSku: kept.row.sku,
        discardedSku: draft.row.sku,
        name: draft.name,
        brand: draft.row.brand,
        detail: `image ${draft.row.image_url} · ${draft.row.product_url}`,
      });
    } else {
      identity.set(key, draft);
    }
  }
  const finalDrafts = mapped.filter((d) => !duplicateSkus.has(d.row.sku));

  // 6. Product slugs. name + brand, deterministic; when the brand already ends
  // the name ("Coca Cola" by COCA COLA) it is not repeated. A slug taken twice
  // gets -2, -3… in SKU order, and is reported.
  const slugCollisions: {
    slug: string;
    resolved: { sku: string; slug: string; name: string; image: string }[];
  }[] = [];
  const baseSlug = (d: Draft): string => {
    const nameSlug = slugify(d.name);
    const brand = d.brandSlug;
    if (!brand) return nameSlug.slice(0, maxSlug).replace(/-+$/g, '');
    const nameTokens = nameSlug.split('-');
    const brandTokens = brand.split('-');
    const containsBrand = nameTokens.some((_, start) =>
      brandTokens.every(
        (token, offset) => nameTokens[start + offset] === token,
      ),
    );
    const joined = containsBrand ? nameSlug : `${nameSlug}-${brand}`;
    return joined.slice(0, maxSlug).replace(/-+$/g, '');
  };
  const slugOf = new Map<string, string>();
  const taken = new Map<string, string>();
  const groups = new Map<string, Draft[]>();
  for (const d of [...finalDrafts].sort((a, b) =>
    a.row.sku.localeCompare(b.row.sku),
  )) {
    const base = baseSlug(d);
    groups.set(base, [...(groups.get(base) ?? []), d]);
  }
  for (const [base, members] of groups) {
    members.forEach((d, index) => {
      let slug = base;
      if (index > 0) {
        let n = index + 1;
        slug = `${base.slice(0, maxSlug - `-${n}`.length)}-${n}`;
        while (taken.has(slug)) {
          n += 1;
          slug = `${base.slice(0, maxSlug - `-${n}`.length)}-${n}`;
        }
      }
      taken.set(slug, d.row.sku);
      slugOf.set(d.row.sku, slug);
    });
    if (members.length > 1) {
      slugCollisions.push({
        slug: base,
        resolved: members.map((d) => ({
          sku: d.row.sku,
          slug: slugOf.get(d.row.sku)!,
          name: d.name,
          image: d.row.image_url,
        })),
      });
    }
  }

  // 7. Photos, units, and the catalog.
  const missingPhotos: string[] = [];
  const invalidPhotos: { sku: string; url: string }[] = [];
  const unitRuleCounts = new Map<
    string,
    { count: number; skus: string[]; names: string[] }
  >();
  const needsReview: {
    sku: string;
    name: string;
    category: string;
    unit: Unit;
    rule: string;
    reason: string;
  }[] = [];
  const categoryOverrides: {
    sku: string;
    name: string;
    from: string;
    to: string;
    rule: string;
  }[] = [];
  const nameNormalizations: { sku: string; from: string; to: string }[] = [];
  const skuToSlug: Record<string, string> = {};

  const products = new Map<string, CatalogProductOut[]>();
  for (const d of finalDrafts) {
    const slug = slugOf.get(d.row.sku)!;
    skuToSlug[d.row.sku] = slug;

    let photo: string | undefined;
    if (!d.row.image_url) {
      missingPhotos.push(d.row.sku);
    } else if (options.isValidPhoto(d.row.image_url)) {
      photo = d.row.image_url;
    } else {
      invalidPhotos.push({ sku: d.row.sku, url: d.row.image_url });
    }

    const unit = classifyUnit(d.row.category, d.name);
    const entry = unitRuleCounts.get(unit.rule) ?? {
      count: 0,
      skus: [],
      names: [],
    };
    entry.count += 1;
    entry.skus.push(d.row.sku);
    entry.names.push(d.name);
    unitRuleCounts.set(unit.rule, entry);
    if (unit.confidence === 'review') {
      needsReview.push({
        sku: d.row.sku,
        name: d.name,
        category: d.row.category,
        unit: unit.unit,
        rule: unit.rule,
        reason: UNIT_RULES.find((r) => r.id === unit.rule)!.description,
      });
    } else if (unit.unit === 'KG' && looksPacked(d.name)) {
      needsReview.push({
        sku: d.row.sku,
        name: d.name,
        category: d.row.category,
        unit: unit.unit,
        rule: unit.rule,
        reason: 'weighed by category, but the name looks like a closed pack',
      });
    }

    if (d.categoryOverridden) {
      categoryOverrides.push({
        sku: d.row.sku,
        name: d.name,
        from: d.row.category,
        to: d.categorySlug!,
        rule: d.categoryVia,
      });
    }
    if (d.nameChanged) {
      nameNormalizations.push({ sku: d.row.sku, from: d.row.name, to: d.name });
    }

    const out: CatalogProductOut = {
      slug,
      name: d.name,
      defaultSaleUnit: unit.unit,
    };
    if (d.brandSlug) out.brandSlug = d.brandSlug;
    if (photo) out.photo = photo;
    // Key order of the file: slug, name, brandSlug, photo, unit.
    const ordered: CatalogProductOut = {
      slug: out.slug,
      name: out.name,
      ...(out.brandSlug ? { brandSlug: out.brandSlug } : {}),
      ...(out.photo ? { photo: out.photo } : {}),
      defaultSaleUnit: out.defaultSaleUnit,
    };
    products.set(d.categorySlug!, [
      ...(products.get(d.categorySlug!) ?? []),
      ordered,
    ]);
  }

  const usedBrandSlugs = new Set(
    finalDrafts.flatMap((d) => (d.brandSlug ? [d.brandSlug] : [])),
  );
  const catalog: CatalogOut = {
    brands: [...usedBrandSlugs]
      .sort((a, b) => a.localeCompare(b))
      .map((slug) => ({ slug, name: brandNames.get(slug)! })),
    categories: CATEGORIES.filter((c) => products.has(c.slug)).map((c) => ({
      slug: c.slug,
      name: c.name,
      products: products
        .get(c.slug)!
        .sort((a, b) => a.slug.localeCompare(b.slug)),
    })),
  };

  // Brands that differ by more than formatting but look alike: reported, never merged.
  const brandList = [...usedBrandSlugs].sort().map((slug) => ({
    slug,
    name: brandNames.get(slug)!,
  }));
  const possibleBrandVariants: { a: string; b: string; why: string }[] = [];
  for (let i = 0; i < brandList.length; i += 1) {
    for (let j = i + 1; j < brandList.length; j += 1) {
      const a = brandList[i]!;
      const b = brandList[j]!;
      const closeSpelling =
        editDistance(a.slug, b.slug) <= 1 && a.slug.length > 3;
      const oneContainsOther =
        a.slug.endsWith(`-${b.slug}`) ||
        b.slug.endsWith(`-${a.slug}`) ||
        a.slug.startsWith(`${b.slug}-`) ||
        b.slug.startsWith(`${a.slug}-`);
      if (closeSpelling || oneContainsOther) {
        possibleBrandVariants.push({
          a: a.name,
          b: b.name,
          why: closeSpelling
            ? 'one letter apart'
            : 'one name contains the other',
        });
      }
    }
  }

  const categoryCounts = catalog.categories.map((c) => ({
    slug: c.slug,
    name: c.name,
    products: c.products.length,
  }));
  const carrefourToCategory = new Map<
    string,
    { slug: string; count: number; via: string }
  >();
  for (const d of finalDrafts) {
    const key = d.row.category;
    const current = carrefourToCategory.get(key);
    if (current) current.count += 1;
    else
      carrefourToCategory.set(key, {
        slug: d.categorySlug!,
        count: 1,
        via: d.categoryVia,
      });
  }

  const brandCounts = new Map<string, number>();
  for (const d of finalDrafts) {
    if (d.brandSlug)
      brandCounts.set(d.brandSlug, (brandCounts.get(d.brandSlug) ?? 0) + 1);
  }

  const unitTotals = { PIECE: 0, KG: 0, L: 0 };
  for (const products of catalog.categories.flatMap((c) => c.products)) {
    unitTotals[products.defaultSaleUnit] += 1;
  }

  // What was checked for duplicates, whether or not anything was found.
  const countDuplicates = (values: string[]) =>
    values.length - new Set(values.filter((v) => v !== '')).size;
  const sameName = new Map<string, string[]>();
  for (const row of distinct) {
    const key = row.name.toLowerCase();
    sameName.set(key, [
      ...(sameName.get(key) ?? []),
      `${row.sku} (${row.brand || 'no brand'})`,
    ]);
  }
  const sameNameGroups = [...sameName].filter(([, skus]) => skus.length > 1);
  const duplicateAnalysis = {
    sameSku: usable.length - unique.length,
    sameProductUrl: unique.length - distinct.length,
    sameImageUrl: countDuplicates(rows.map((r) => r.image_url)),
    sameNameAndBrand: duplicates.filter((d) => d.kind === 'same name and brand')
      .length,
    sameGeneratedSlug: slugCollisions.length,
    sameNameDifferentBrand: {
      groups: sameNameGroups.length,
      note: 'valid: each brand is its own product',
      examples: sameNameGroups
        .slice(0, 5)
        .map(([name, skus]) => ({ name, skus })),
    },
  };

  const report = {
    sourceRows: rows.length,
    convertedProducts: finalDrafts.length,
    excludedProducts: { count: excluded.length, items: excluded },
    duplicateProducts: {
      count: duplicates.length,
      items: duplicates,
      analysis: duplicateAnalysis,
    },
    brands: {
      unique: catalog.brands.length,
      brandlessProducts: finalDrafts.filter((d) => d.brandSlug === null).length,
      merges: brandMerges,
      possibleVariantsNotMerged: possibleBrandVariants,
      list: catalog.brands.map((b) => ({
        slug: b.slug,
        name: b.name,
        products: brandCounts.get(b.slug) ?? 0,
      })),
    },
    categories: {
      grocerGo: categoryCounts,
      carrefourPathMapping: [...carrefourToCategory]
        .map(([path, v]) => ({
          carrefourCategory: path,
          grocerGoCategory: v.slug,
          products: v.count,
          rule: v.via,
        }))
        .sort((a, b) => a.carrefourCategory.localeCompare(b.carrefourCategory)),
      overriddenByName: categoryOverrides,
    },
    missingBrands: {
      count: finalDrafts.filter((d) => d.brandSlug === null).length,
      note: 'a blank Carrefour brand is a brandless product; none was invented',
    },
    missingPhotos: { count: missingPhotos.length, skus: missingPhotos },
    invalidPhotos: { count: invalidPhotos.length, items: invalidPhotos },
    validPhotos:
      finalDrafts.length - missingPhotos.length - invalidPhotos.length,
    unitClassification: {
      totals: unitTotals,
      rules: UNIT_RULES.map((rule) => {
        const hit = unitRuleCounts.get(rule.id);
        return {
          rule: rule.id,
          unit: rule.unit,
          confidence: rule.confidence,
          description: rule.description,
          products: hit?.count ?? 0,
          examples: examples(hit?.names ?? []),
        };
      }),
      needsReview: { count: needsReview.length, items: needsReview },
    },
    unmappedCategories,
    slugCollisions: { count: slugCollisions.length, items: slugCollisions },
    nameNormalizations,
    skuToSlug,
  };

  return { catalog, report };
}

function editDistance(a: string, b: string): number {
  const previous = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i += 1) {
    let diagonal = previous[0]!;
    previous[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const above = previous[j]!;
      previous[j] = Math.min(
        previous[j]! + 1,
        previous[j - 1]! + 1,
        diagonal + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
      diagonal = above;
    }
  }
  return previous[b.length]!;
}

export type ConversionReport = ReturnType<typeof convertCarrefour>['report'];
