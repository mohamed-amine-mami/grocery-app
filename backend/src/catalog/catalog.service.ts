import { Injectable, NotFoundException } from '@nestjs/common';
import { db } from '../prisma/db.js';
import { allowedSaleUnits } from '../products/product-rules.js';
import type { SaleUnit } from '../products/sale-unit.enum.js';
import { StoresService } from '../stores/stores.service.js';
import {
  decodeCursor,
  encodeCursor,
  FOLD_FROM,
  FOLD_TO,
  searchTerms,
} from './catalog-browse.js';
import {
  CATALOG_PAGE_DEFAULT_LIMIT,
  type BrowseCatalogQuery,
} from './dto/browse-catalog.query.js';
import type { ListCatalogProductsQuery } from './dto/list-catalog-products.query.js';

/**
 * Read-only access to the global catalog for owners. There is deliberately no
 * write here: only the catalog importer ever writes `Category` / `Product`.
 */
@Injectable()
export class CatalogService {
  constructor(private readonly storesService: StoresService) {}

  /** Active categories, with how many active products each holds. */
  async categories() {
    const categories = await db.orm.public.Category.where((row) =>
      row.archivedAt.isNull(),
    ).all();
    // One grouped count, not every product row.
    const grouped = await db.orm.public.Product.where((row) =>
      row.archivedAt.isNull(),
    )
      .groupBy('categoryId')
      .aggregate((agg) => ({ total: agg.count() }));

    const counts = new Map<number, number>();
    for (const row of grouped) {
      counts.set(row.categoryId, Number(row.total ?? 0));
    }
    return categories
      .map((category) => ({
        id: category.id,
        slug: category.slug,
        name: category.name,
        description: category.description,
        photo: category.photo,
        productCount: counts.get(category.id) ?? 0,
      }))
      .sort((a, b) => a.name.localeCompare(b.name, 'fr'));
  }

  /**
   * Active catalog products — in active categories — each flagged with whether
   * this owner's store already has it. Needs the store, so it is a 404 for an
   * owner who has not created one yet.
   *
   * The whole catalog in one array: kept for existing consumers. The owner
   * picker uses `browse` instead.
   */
  async products(ownerId: number, filters: ListCatalogProductsQuery) {
    const storeId = (await this.storesService.findByOwner(ownerId)).id;

    const products = await db.orm.public.Product.where((row) =>
      row.archivedAt.isNull(),
    )
      .include('category')
      .include('brand')
      .all();
    const offerings = await db.orm.public.StoreProduct.where({ storeId }).all();
    const offeringByProduct = new Map(
      offerings.map((offering) => [offering.productId, offering]),
    );

    return products
      .filter(
        (product) =>
          product.category !== null &&
          product.category.archivedAt === null &&
          (filters.categoryId === undefined ||
            product.categoryId === filters.categoryId),
      )
      .map((product) => toEntity(product, offeringByProduct.get(product.id)))
      .sort(
        (a, b) =>
          a.name.localeCompare(b.name, 'fr') ||
          (a.brand?.name ?? '').localeCompare(b.brand?.name ?? '', 'fr') ||
          a.id - b.id,
      );
  }

  /**
   * One page of the active catalog, searched and filtered in the database.
   *
   * The order is total: the product name folded (lower case, no accents) and
   * then the id, under the `C` collation so it does not depend on the database
   * locale. Paging is keyset: the cursor carries the last row's (key, id), so
   * walking the pages of an *unchanging* match set returns every row exactly
   * once — no offset to shift. There is no snapshot: a row inserted, renamed or
   * moved in or out of the filter (category, brand, archive) between two pages
   * can be missed, or returned again if it moved past the cursor. `total`
   * counts the current matches over all pages and can change between requests.
   */
  async browse(ownerId: number, query: BrowseCatalogQuery) {
    const storeId = (await this.storesService.findByOwner(ownerId)).id;
    const limit = query.limit ?? CATALOG_PAGE_DEFAULT_LIMIT;
    const cursor = query.cursor ? decodeCursor(query.cursor) : null;
    const terms = searchTerms(query.q).join(' ');

    // The fold below is `foldSearchText` in SQL (it is written out twice, for
    // the sort key and for the searched text, because a raw template cannot
    // splice SQL fragments). The cursor and category are parameters; 0 means
    // "none" (ids start at 1).
    const plan = db.raw.sql`
      with raw as (
        select p.id as id,
               p.name as name,
               p.name || ' ' || coalesce(b.name, '') || ' ' || c.name as hay
        from "Product" p
        join "Category" c on c.id = p."categoryId"
        left join "Brand" b on b.id = p."brandId"
        where p."archivedAt" is null
          and c."archivedAt" is null
          and (${query.categoryId ?? 0} = 0 or p."categoryId" = ${query.categoryId ?? 0})
      ),
      folded as (
        select id,
               lower(translate(replace(replace(replace(replace(name, 'Œ', 'oe'), 'œ', 'oe'), 'Æ', 'ae'), 'æ', 'ae'), ${FOLD_FROM}, ${FOLD_TO})) as sort_key,
               lower(translate(replace(replace(replace(replace(hay, 'Œ', 'oe'), 'œ', 'oe'), 'Æ', 'ae'), 'æ', 'ae'), ${FOLD_FROM}, ${FOLD_TO})) as hay
        from raw
      ),
      matched as (
        select id, sort_key
        from folded
        where not exists (
          select 1
          from unnest(string_to_array(${terms}, ' ')) as t(term)
          where t.term <> '' and strpos(folded.hay, t.term) = 0
        )
      ),
      page as (
        select id, sort_key
        from matched
        where ${cursor?.id ?? 0} = 0
           or (sort_key collate "C", id) > (${cursor?.key ?? ''} collate "C", ${cursor?.id ?? 0})
        order by sort_key collate "C", id
        limit ${limit + 1}
      ),
      counted as (select count(*) as total from matched)
      select r.id, r.sort_key, r.total
      from (
        select page.id as id, page.sort_key as sort_key, counted.total as total
        from page cross join counted
        union all
        -- A page past the last row has no row to carry the total: a sentinel does.
        select 0, '', counted.total
        from counted
        where not exists (select 1 from page)
      ) as r
      order by r.sort_key collate "C", r.id
    `
      .returnsRow({
        id: { codecId: 'pg/int4@1', nullable: false },
        sort_key: { codecId: 'pg/text@1', nullable: false },
        total: { codecId: 'pg/int8@1', nullable: false },
      })
      .build();
    const found = await db.runtime().query(plan);

    // `total` is the same on every row (and on the sentinel of an empty page).
    const total = found.length > 0 ? Number(found[0]!.total) : 0;
    const rows = found.filter((row) => row.id !== 0);
    const hasMore = rows.length > limit;
    const pageRows = rows.slice(0, limit);

    const ids = pageRows.map((row) => row.id);
    const items = await this.entitiesFor(storeId, ids);
    const last = pageRows[pageRows.length - 1];
    return {
      items,
      total,
      nextCursor:
        hasMore && last
          ? encodeCursor({ key: last.sort_key, id: last.id })
          : null,
    };
  }

  /** One active catalog product, flagged for this owner's store; 404 when it is archived or unknown. */
  async product(ownerId: number, productId: number) {
    const storeId = (await this.storesService.findByOwner(ownerId)).id;
    const [entity] = await this.entitiesFor(storeId, [productId]);
    if (!entity) {
      throw new NotFoundException(`Catalog product ${productId} not found`);
    }
    return entity;
  }

  /** The active products among `ids` (active category too), in the order of `ids`. */
  private async entitiesFor(storeId: number, ids: number[]) {
    if (ids.length === 0) return [];
    const products = await db.orm.public.Product.where((row) => row.id.in(ids))
      .include('category')
      .include('brand')
      .all();
    const offerings = await db.orm.public.StoreProduct.where((row) =>
      row.productId.in(ids),
    )
      .where({ storeId })
      .all();
    const productById = new Map(products.map((p) => [p.id, p]));
    const offeringByProduct = new Map(offerings.map((o) => [o.productId, o]));
    const entities = [];
    for (const id of ids) {
      const product = productById.get(id);
      if (
        !product ||
        product.archivedAt !== null ||
        product.category === null ||
        product.category.archivedAt !== null
      ) {
        continue; // archived between the id query and this one
      }
      entities.push(toEntity(product, offeringByProduct.get(id)));
    }
    return entities;
  }
}

interface ProductWithRelations {
  id: number;
  slug: string;
  name: string;
  description: string | null;
  photo: string | null;
  defaultSaleUnit: string;
  defaultMinQuantity: number;
  defaultQuantityStep: number;
  defaultMaxQuantity: number | null;
  category: { id: number; slug: string; name: string } | null;
  brand: { id: number; slug: string; name: string } | null;
}

type OfferingRow = { id: number; archivedAt: string | Date | null };

function toEntity(product: ProductWithRelations, offering?: OfferingRow) {
  const category = product.category!;
  const defaultSaleUnit = product.defaultSaleUnit as SaleUnit;
  return {
    id: product.id,
    slug: product.slug,
    name: product.name,
    description: product.description,
    photo: product.photo,
    defaultSaleUnit,
    allowedSaleUnits: allowedSaleUnits(defaultSaleUnit),
    defaultMinQuantity: product.defaultMinQuantity,
    defaultQuantityStep: product.defaultQuantityStep,
    defaultMaxQuantity: product.defaultMaxQuantity,
    category: {
      id: category.id,
      slug: category.slug,
      name: category.name,
    },
    brand: product.brand
      ? {
          id: product.brand.id,
          slug: product.brand.slug,
          name: product.brand.name,
        }
      : null,
    inMyStore: offering !== undefined && offering.archivedAt === null,
    storeProductId: offering?.id ?? null,
    storeProductArchived:
      offering !== undefined && offering.archivedAt !== null,
  };
}
