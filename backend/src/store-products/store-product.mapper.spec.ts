import { SaleUnit } from '../products/sale-unit.enum.js';
import {
  toStoreProductEntity,
  type OfferingWithCatalog,
} from './store-product.mapper.js';

const offering = (
  overrides: Partial<OfferingWithCatalog> = {},
): OfferingWithCatalog => ({
  id: 1,
  productId: 10,
  saleUnit: SaleUnit.KG,
  priceMillimes: 4500,
  minQuantity: 100,
  quantityStep: 100,
  maxQuantity: 10_000,
  trackStock: false,
  stockQuantity: null,
  isAvailable: true,
  archivedAt: null,
  createdAt: '2026-10-03 10:00:00+00',
  updatedAt: '2026-10-03 10:00:00+00',
  product: {
    id: 10,
    slug: 'banane',
    name: 'Banane',
    description: null,
    photo: null,
    defaultSaleUnit: SaleUnit.KG,
    defaultMinQuantity: 100,
    defaultQuantityStep: 100,
    defaultMaxQuantity: 10_000,
    archivedAt: null,
    category: { id: 2, slug: 'fruits', name: 'Fruits', archivedAt: null },
  },
  ...overrides,
});

describe('toStoreProductEntity', () => {
  it('keeps commercial data and stock on the store product, and none on the catalog product', () => {
    const entity = toStoreProductEntity(
      offering({ trackStock: true, stockQuantity: 20_000 }),
    );

    expect(entity).toMatchObject({
      priceMillimes: 4500,
      saleUnit: 'KG',
      minQuantity: 100,
      trackStock: true,
      stockQuantity: 20_000,
      isAvailable: true,
    });
    // The embedded catalog product exposes identity and *defaults* only.
    expect(Object.keys(entity.product).sort()).toEqual(
      [
        'allowedSaleUnits',
        'brand',
        'defaultMaxQuantity',
        'defaultMinQuantity',
        'defaultQuantityStep',
        'defaultSaleUnit',
        'description',
        'id',
        'isActive',
        'name',
        'photo',
        'slug',
      ].sort(),
    );
    expect(Object.keys(entity.category).sort()).toEqual(
      ['id', 'isActive', 'name', 'slug'].sort(),
    );
  });

  it('derives availability from the offering, the catalog and stock', () => {
    expect(toStoreProductEntity(offering())).toMatchObject({
      isOrderable: true,
      unavailabilityReason: null,
    });
    expect(
      toStoreProductEntity(offering({ trackStock: true, stockQuantity: 0 })),
    ).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'OUT_OF_STOCK',
    });
  });

  it('leaves an untracked product to the owner’s switch alone', () => {
    expect(
      toStoreProductEntity(offering({ isAvailable: false })),
    ).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'OWNER_DISABLED',
    });
    expect(toStoreProductEntity(offering({ isAvailable: true }))).toMatchObject(
      { isOrderable: true },
    );
  });

  it('reports a catalog-archived product as unorderable without touching its data', () => {
    const base = offering();
    const entity = toStoreProductEntity(
      offering({
        trackStock: true,
        stockQuantity: 500,
        product: { ...base.product!, archivedAt: '2026-10-01 00:00:00+00' },
      }),
    );

    expect(entity).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'CATALOG_ARCHIVED',
      stockQuantity: 500,
      priceMillimes: 4500,
    });
    expect(entity.product.isActive).toBe(false);
  });

  it('refuses a store product without its catalog product (a broken foreign key)', () => {
    expect(() => toStoreProductEntity(offering({ product: null }))).toThrow(
      'has no catalog product/category',
    );
  });
});

describe('toStoreProductEntity brand', () => {
  it('is null for a brandless product — also when the caller did not load it', () => {
    expect(toStoreProductEntity(offering()).product.brand).toBeNull();
  });

  it('shows only the brand’s id, slug and name', () => {
    const base = offering();
    const entity = toStoreProductEntity({
      ...base,
      product: {
        ...base.product!,
        brand: { id: 4, slug: 'heinz', name: 'Heinz', createdAt: 'x' } as {
          id: number;
          slug: string;
          name: string;
        },
      },
    });
    expect(entity.product.brand).toEqual({
      id: 4,
      slug: 'heinz',
      name: 'Heinz',
    });
  });
});
