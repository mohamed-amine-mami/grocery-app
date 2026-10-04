import { Injectable } from '@nestjs/common';
import { db } from '../prisma/db.js';
import { allowedSaleUnits } from '../products/product-rules.js';
import type { SaleUnit } from '../products/sale-unit.enum.js';
import { StoresService } from '../stores/stores.service.js';
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
    const products = await db.orm.public.Product.where((row) =>
      row.archivedAt.isNull(),
    ).all();

    const counts = new Map<number, number>();
    for (const product of products) {
      counts.set(product.categoryId, (counts.get(product.categoryId) ?? 0) + 1);
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
   */
  async products(ownerId: number, filters: ListCatalogProductsQuery) {
    const storeId = (await this.storesService.findByOwner(ownerId)).id;

    const products = await db.orm.public.Product.where((row) =>
      row.archivedAt.isNull(),
    )
      .include('category')
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
      .map((product) => {
        const offering = offeringByProduct.get(product.id);
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
          inMyStore: offering !== undefined && offering.archivedAt === null,
          storeProductId: offering?.id ?? null,
          storeProductArchived:
            offering !== undefined && offering.archivedAt !== null,
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name, 'fr'));
  }
}
