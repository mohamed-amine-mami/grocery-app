import { isURL } from 'class-validator';
import {
  DESCRIPTION_MAX_LENGTH,
  NAME_MAX_LENGTH,
  PHOTO_URL_OPTIONS,
  URL_MAX_LENGTH,
} from '../common/limits.js';
import {
  quantityRuleErrors,
  withQuantityDefaults,
} from '../products/product-rules.js';
import { SaleUnit } from '../products/sale-unit.enum.js';

/**
 * The shape of `seed/catalog.json` and its validation. Pure — no database — so
 * a whole file can be checked, and every problem reported, before anything is
 * written. Slugs are the stable identity of catalog entries: the importer
 * matches on them, so a changed name never means a new entry.
 */

export interface CatalogProduct {
  slug: string;
  name: string;
  description: string | null;
  photo: string | null;
  defaultSaleUnit: SaleUnit;
  defaultMinQuantity: number;
  defaultQuantityStep: number;
  defaultMaxQuantity: number | null;
  archived: boolean;
}

export interface CatalogCategory {
  slug: string;
  name: string;
  description: string | null;
  photo: string | null;
  archived: boolean;
  products: CatalogProduct[];
}

export interface Catalog {
  categories: CatalogCategory[];
}

export const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SLUG_MAX_LENGTH = 100;

const CATEGORY_KEYS = [
  'slug',
  'name',
  'description',
  'photo',
  'archived',
  'products',
];
const PRODUCT_KEYS = [
  'slug',
  'name',
  'description',
  'photo',
  'defaultSaleUnit',
  'defaultMinQuantity',
  'defaultQuantityStep',
  'defaultMaxQuantity',
  'archived',
];
/** Keys people reach for to point a product at a category — the nesting already does that. */
const CATEGORY_REFERENCE_KEYS = ['category', 'categoryId', 'categorySlug'];

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export interface ParsedCatalog {
  /** Present only when `errors` is empty. */
  catalog: Catalog | null;
  errors: string[];
}

export function parseCatalog(input: unknown): ParsedCatalog {
  const errors: string[] = [];
  const fail = (path: string, message: string) =>
    errors.push(`${path}: ${message}`);

  const rejectUnknownKeys = (
    path: string,
    record: Record<string, unknown>,
    allowed: string[],
    isProduct = false,
  ) => {
    for (const key of Object.keys(record)) {
      if (allowed.includes(key)) continue;
      if (isProduct && CATEGORY_REFERENCE_KEYS.includes(key)) {
        fail(
          path,
          `unknown field "${key}" — a product belongs to the category it is nested under`,
        );
      } else {
        fail(path, `unknown field "${key}"`);
      }
    }
  };

  const readSlug = (path: string, value: unknown): string | null => {
    if (typeof value !== 'string' || value.length === 0) {
      fail(`${path}.slug`, 'is required');
      return null;
    }
    if (value.length > SLUG_MAX_LENGTH || !SLUG_PATTERN.test(value)) {
      fail(
        `${path}.slug`,
        `"${value}" must be lowercase letters and digits separated by single hyphens (at most ${SLUG_MAX_LENGTH} characters)`,
      );
      return null;
    }
    return value;
  };

  const readName = (path: string, value: unknown): string | null => {
    if (typeof value !== 'string' || value.trim().length === 0) {
      fail(`${path}.name`, 'is required');
      return null;
    }
    const name = value.trim();
    if (name.length > NAME_MAX_LENGTH) {
      fail(`${path}.name`, `must be at most ${NAME_MAX_LENGTH} characters`);
      return null;
    }
    return name;
  };

  const readDescription = (path: string, value: unknown): string | null => {
    if (value === undefined || value === null) return null;
    if (typeof value !== 'string') {
      fail(`${path}.description`, 'must be a string');
      return null;
    }
    const description = value.trim();
    if (description.length > DESCRIPTION_MAX_LENGTH) {
      fail(
        `${path}.description`,
        `must be at most ${DESCRIPTION_MAX_LENGTH} characters`,
      );
      return null;
    }
    return description.length === 0 ? null : description;
  };

  const readPhoto = (path: string, value: unknown): string | null => {
    if (value === undefined || value === null) return null;
    if (
      typeof value !== 'string' ||
      value.length > URL_MAX_LENGTH ||
      !isURL(value, PHOTO_URL_OPTIONS)
    ) {
      fail(`${path}.photo`, 'must be an http(s) URL');
      return null;
    }
    return value;
  };

  const readArchived = (path: string, value: unknown): boolean => {
    if (value === undefined) return false;
    if (typeof value !== 'boolean') {
      fail(`${path}.archived`, 'must be true or false');
      return false;
    }
    return value;
  };

  const readOptionalNumber = (
    path: string,
    field: string,
    value: unknown,
  ): number | null | undefined => {
    if (value === undefined || value === null) return undefined;
    if (typeof value !== 'number') {
      fail(`${path}.${field}`, 'must be a number');
      return undefined;
    }
    return value;
  };

  const readProduct = (path: string, value: unknown): CatalogProduct | null => {
    if (!isRecord(value)) {
      fail(path, 'must be an object');
      return null;
    }
    const before = errors.length;
    rejectUnknownKeys(path, value, PRODUCT_KEYS, true);

    const slug = readSlug(path, value['slug']);
    const name = readName(path, value['name']);
    const description = readDescription(path, value['description']);
    const photo = readPhoto(path, value['photo']);
    const archived = readArchived(path, value['archived']);

    const unit = value['defaultSaleUnit'];
    const validUnit =
      typeof unit === 'string' &&
      (Object.values(SaleUnit) as string[]).includes(unit);
    if (!validUnit) {
      fail(
        `${path}.defaultSaleUnit`,
        `must be one of ${Object.values(SaleUnit).join(', ')}`,
      );
    }

    const min = readOptionalNumber(
      path,
      'defaultMinQuantity',
      value['defaultMinQuantity'],
    );
    const step = readOptionalNumber(
      path,
      'defaultQuantityStep',
      value['defaultQuantityStep'],
    );
    const max = readOptionalNumber(
      path,
      'defaultMaxQuantity',
      value['defaultMaxQuantity'],
    );

    if (errors.length > before || !validUnit) return null;

    // Same rules as a store's own quantities: the catalog only suggests them.
    const rules = withQuantityDefaults({
      saleUnit: unit as SaleUnit,
      minQuantity: min,
      quantityStep: step,
      maxQuantity: max,
    });
    const ruleErrors = quantityRuleErrors(rules);
    for (const message of ruleErrors) {
      fail(
        path,
        message
          .replaceAll('minQuantity', 'defaultMinQuantity')
          .replaceAll('maxQuantity', 'defaultMaxQuantity')
          .replaceAll('quantityStep', 'defaultQuantityStep'),
      );
    }
    if (
      ruleErrors.length > 0 ||
      slug === null ||
      name === null ||
      errors.length > before
    ) {
      return null;
    }
    return {
      slug,
      name,
      description,
      photo,
      defaultSaleUnit: rules.saleUnit,
      defaultMinQuantity: rules.minQuantity,
      defaultQuantityStep: rules.quantityStep,
      defaultMaxQuantity: rules.maxQuantity,
      archived,
    };
  };

  const readCategory = (
    path: string,
    value: unknown,
  ): CatalogCategory | null => {
    if (!isRecord(value)) {
      fail(path, 'must be an object');
      return null;
    }
    const before = errors.length;
    rejectUnknownKeys(path, value, CATEGORY_KEYS);

    const slug = readSlug(path, value['slug']);
    const name = readName(path, value['name']);
    const description = readDescription(path, value['description']);
    const photo = readPhoto(path, value['photo']);
    const archived = readArchived(path, value['archived']);

    const rawProducts = value['products'];
    const products: CatalogProduct[] = [];
    if (!Array.isArray(rawProducts)) {
      fail(`${path}.products`, 'must be a list (it may be empty)');
    } else {
      rawProducts.forEach((raw, index) => {
        const product = readProduct(`${path}.products[${index}]`, raw);
        if (product) products.push(product);
      });
    }
    if (errors.length > before || slug === null || name === null) return null;
    return { slug, name, description, photo, archived, products };
  };

  if (!isRecord(input)) {
    return {
      catalog: null,
      errors: ['catalog: must be an object with a "categories" list'],
    };
  }
  rejectUnknownKeys('catalog', input, ['categories']);
  const rawCategories = input['categories'];
  const categories: CatalogCategory[] = [];
  if (!Array.isArray(rawCategories)) {
    fail('catalog.categories', 'must be a list');
  } else {
    rawCategories.forEach((raw, index) => {
      const category = readCategory(`categories[${index}]`, raw);
      if (category) categories.push(category);
    });
  }

  if (errors.length === 0) {
    checkUniqueness(categories, errors);
  }
  return errors.length > 0
    ? { catalog: null, errors }
    : { catalog: { categories }, errors };
}

/** Slugs are unique across the file; active names are unique too (the database enforces both). */
function checkUniqueness(categories: CatalogCategory[], errors: string[]) {
  const categorySlugs = new Map<string, string>();
  const productSlugs = new Map<string, string>();
  const categoryNames = new Map<string, string>();
  const productNames = new Map<string, string>();

  categories.forEach((category, ci) => {
    const categoryPath = `categories[${ci}]`;
    const seenCategory = categorySlugs.get(category.slug);
    if (seenCategory) {
      errors.push(
        `${categoryPath}.slug: "${category.slug}" is already used by ${seenCategory}`,
      );
    }
    categorySlugs.set(category.slug, categoryPath);

    if (!category.archived) {
      const key = category.name.toLowerCase();
      const seen = categoryNames.get(key);
      if (seen) {
        errors.push(
          `${categoryPath}.name: "${category.name}" is already used by active category ${seen}`,
        );
      }
      categoryNames.set(key, categoryPath);
    }

    category.products.forEach((product, pi) => {
      const path = `${categoryPath}.products[${pi}]`;
      const seenProduct = productSlugs.get(product.slug);
      if (seenProduct) {
        errors.push(
          `${path}.slug: "${product.slug}" is already used by ${seenProduct}`,
        );
      }
      productSlugs.set(product.slug, path);

      if (!product.archived) {
        const key = product.name.toLowerCase();
        const seen = productNames.get(key);
        if (seen) {
          errors.push(
            `${path}.name: "${product.name}" is already used by active product ${seen}`,
          );
        }
        productNames.set(key, path);
      }
    });
  });
}
