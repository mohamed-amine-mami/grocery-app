import { Injectable, NotFoundException } from '@nestjs/common';
import { db } from '../prisma/db.js';
import {
  toCustomerCatalogItem,
  toCustomerStore,
  type OfferingRow,
} from './customer-catalog.mapper.js';
import type {
  CustomerCatalogItemEntity,
  CustomerStoreEntity,
} from './entities/customer-catalog.entity.js';

/**
 * Read-only browsing for customers. It decides nothing about orderability
 * (that is `product-rules.ts`, applied in the mapper) and nothing here is
 * binding: `POST /orders` revalidates every line at checkout.
 */
@Injectable()
export class CustomerCatalogService {
  /** Every store, open or closed (a closed store can still be browsed), by name. */
  async listStores(): Promise<CustomerStoreEntity[]> {
    const stores = await db.orm.public.Store.all();
    return stores
      .sort((a, b) => a.name.localeCompare(b.name, 'fr') || a.id - b.id)
      .map(toCustomerStore);
  }

  /** One store's own offerings only: every row is filtered by that `storeId`. */
  async listStoreProducts(
    storeId: number,
  ): Promise<CustomerCatalogItemEntity[]> {
    const store = await db.orm.public.Store.first({ id: storeId });
    if (!store) throw new NotFoundException(`Store ${storeId} not found`);

    const rows = (await db.orm.public.StoreProduct.where({ storeId })
      .include('product', (product) =>
        product.include('category').include('brand'),
      )
      .all()) as OfferingRow[];

    return rows
      .map(toCustomerCatalogItem)
      .filter((item): item is CustomerCatalogItemEntity => item !== null)
      .sort(
        (a, b) =>
          a.category.name.localeCompare(b.category.name, 'fr') ||
          a.name.localeCompare(b.name, 'fr') ||
          a.id - b.id,
      );
  }
}
