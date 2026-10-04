import { unavailabilityReason } from '../products/product-rules.js';
import type { SaleUnit } from '../products/sale-unit.enum.js';
import type {
  CustomerCatalogItemEntity,
  CustomerStoreEntity,
} from './entities/customer-catalog.entity.js';

export interface StoreRow {
  id: number;
  name: string;
  description: string | null;
  photo: string | null;
  address: string;
  latitude: number | null;
  longitude: number | null;
  isOpen: boolean;
}

export interface OfferingRow {
  id: number;
  saleUnit: SaleUnit;
  priceMillimes: number;
  minQuantity: number;
  quantityStep: number;
  maxQuantity: number | null;
  trackStock: boolean;
  stockQuantity: number | null;
  isAvailable: boolean;
  archivedAt: string | null;
  product: {
    name: string;
    description: string | null;
    photo: string | null;
    archivedAt: string | null;
    category: { id: number; name: string; archivedAt: string | null } | null;
  } | null;
}

export function toCustomerStore(row: StoreRow): CustomerStoreEntity {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    photo: row.photo,
    address: row.address,
    latitude: row.latitude,
    longitude: row.longitude,
    isOpen: row.isOpen,
  };
}

/**
 * An offering as a customer sees it, or `null` when it is not listed: the
 * store's own removals (`ARCHIVED`) and products archived in the catalog
 * (`CATALOG_ARCHIVED`) are gone from the customer's view. The orderability
 * itself is the canonical `unavailabilityReason`, not restated here, and the
 * stock figure is read only to feed it — it is never copied to the result.
 */
export function toCustomerCatalogItem(
  row: OfferingRow,
): CustomerCatalogItemEntity | null {
  const { product } = row;
  const category = product?.category ?? null;
  if (product === null || category === null) {
    // The foreign keys are NOT NULL + Restrict, so this cannot happen.
    throw new Error(`Store product ${row.id} has no catalog product/category`);
  }
  const input = {
    offeringIsActive: row.archivedAt === null,
    isAvailable: row.isAvailable,
    productIsActive: product.archivedAt === null,
    categoryIsActive: category.archivedAt === null,
    trackStock: row.trackStock,
    stockQuantity: row.stockQuantity,
    minQuantity: row.minQuantity,
  };
  // Listed or not is also the canonical rule's answer, asked with the
  // owner's switch and stock out of the way: the rule checks the owner switch
  // before the catalog, so an owner-disabled product that was archived in the
  // catalog would otherwise show up as merely "disabled".
  const gone = unavailabilityReason({
    ...input,
    isAvailable: true,
    trackStock: false,
  });
  if (gone !== null) return null;
  const reason = unavailabilityReason(input);
  return {
    id: row.id,
    name: product.name,
    description: product.description,
    photo: product.photo,
    category: { id: category.id, name: category.name },
    saleUnit: row.saleUnit,
    priceMillimes: row.priceMillimes,
    minQuantity: row.minQuantity,
    quantityStep: row.quantityStep,
    maxQuantity: row.maxQuantity,
    isOrderable: reason === null,
    unavailabilityReason: reason,
  };
}
