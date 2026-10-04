import {
  allowedSaleUnits,
  unavailabilityReason,
} from '../products/product-rules.js';
import type { SaleUnit } from '../products/sale-unit.enum.js';
import type { StoreProductEntity } from './entities/store-product.entity.js';

/** What the mapper needs from a store product loaded with its product and category. */
export interface OfferingWithCatalog {
  id: number;
  productId: number;
  saleUnit: SaleUnit;
  priceMillimes: number;
  minQuantity: number;
  quantityStep: number;
  maxQuantity: number | null;
  trackStock: boolean;
  stockQuantity: number | null;
  isAvailable: boolean;
  archivedAt: string | null;
  createdAt: string;
  updatedAt: string;
  product: {
    id: number;
    slug: string;
    name: string;
    description: string | null;
    photo: string | null;
    defaultSaleUnit: SaleUnit;
    defaultMinQuantity: number;
    defaultQuantityStep: number;
    defaultMaxQuantity: number | null;
    archivedAt: string | null;
    category: {
      id: number;
      slug: string;
      name: string;
      archivedAt: string | null;
    } | null;
  } | null;
}

/**
 * The API shape of a store product: its own commercial configuration, the
 * catalog product and category it is an offering of, and the derived
 * availability. Availability is computed here on every read, never stored.
 */
export function toStoreProductEntity(
  row: OfferingWithCatalog,
): StoreProductEntity {
  const { product } = row;
  const category = product?.category ?? null;
  if (product === null || category === null) {
    // The foreign keys are NOT NULL + Restrict, so this cannot happen.
    throw new Error(`Store product ${row.id} has no catalog product/category`);
  }
  const reason = unavailabilityReason({
    offeringIsActive: row.archivedAt === null,
    isAvailable: row.isAvailable,
    productIsActive: product.archivedAt === null,
    categoryIsActive: category.archivedAt === null,
    trackStock: row.trackStock,
    stockQuantity: row.stockQuantity,
    minQuantity: row.minQuantity,
  });
  return {
    id: row.id,
    productId: row.productId,
    saleUnit: row.saleUnit,
    priceMillimes: row.priceMillimes,
    minQuantity: row.minQuantity,
    quantityStep: row.quantityStep,
    maxQuantity: row.maxQuantity,
    trackStock: row.trackStock,
    stockQuantity: row.stockQuantity,
    isAvailable: row.isAvailable,
    isOrderable: reason === null,
    unavailabilityReason: reason,
    archivedAt: row.archivedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    product: {
      id: product.id,
      slug: product.slug,
      name: product.name,
      description: product.description,
      photo: product.photo,
      defaultSaleUnit: product.defaultSaleUnit,
      allowedSaleUnits: allowedSaleUnits(product.defaultSaleUnit),
      defaultMinQuantity: product.defaultMinQuantity,
      defaultQuantityStep: product.defaultQuantityStep,
      defaultMaxQuantity: product.defaultMaxQuantity,
      isActive: product.archivedAt === null,
    },
    category: {
      id: category.id,
      slug: category.slug,
      name: category.name,
      isActive: category.archivedAt === null,
    },
  };
}
