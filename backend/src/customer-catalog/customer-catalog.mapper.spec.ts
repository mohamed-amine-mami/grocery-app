import { isOrderable } from '../products/product-rules.js';
import { SaleUnit } from '../products/sale-unit.enum.js';
import {
  toCustomerCatalogItem,
  toCustomerStore,
  type OfferingRow,
} from './customer-catalog.mapper.js';

const offering = (overrides: Partial<OfferingRow> = {}): OfferingRow => ({
  id: 7,
  saleUnit: SaleUnit.PIECE,
  priceMillimes: 1800,
  minQuantity: 2,
  quantityStep: 1,
  maxQuantity: 12,
  trackStock: false,
  stockQuantity: null,
  isAvailable: true,
  archivedAt: null,
  product: {
    name: 'Lait',
    description: null,
    photo: null,
    archivedAt: null,
    category: { id: 3, name: 'Laitiers', archivedAt: null },
    brand: null,
  },
  ...overrides,
});

const archived = '2026-01-01T00:00:00.000Z';

describe('toCustomerCatalogItem', () => {
  it('copies the store’s own commercial values and the category', () => {
    expect(toCustomerCatalogItem(offering())).toEqual({
      id: 7,
      name: 'Lait',
      description: null,
      photo: null,
      category: { id: 3, name: 'Laitiers' },
      brand: null,
      saleUnit: 'PIECE',
      priceMillimes: 1800,
      minQuantity: 2,
      quantityStep: 1,
      maxQuantity: 12,
      isOrderable: true,
      unavailabilityReason: null,
    });
  });

  it('agrees with the canonical rule for every combination of its inputs', () => {
    for (const trackStock of [true, false]) {
      for (const stockQuantity of [null, 0, 1, 2, 50]) {
        for (const isAvailable of [true, false]) {
          for (const productArchived of [false, true]) {
            for (const categoryArchived of [false, true]) {
              const row = offering({
                trackStock,
                stockQuantity,
                isAvailable,
                product: {
                  name: 'x',
                  description: null,
                  photo: null,
                  archivedAt: productArchived ? archived : null,
                  brand: null,
                  category: {
                    id: 1,
                    name: 'c',
                    archivedAt: categoryArchived ? archived : null,
                  },
                },
              });
              const expected = isOrderable({
                offeringIsActive: true,
                isAvailable,
                productIsActive: !productArchived,
                categoryIsActive: !categoryArchived,
                trackStock,
                stockQuantity,
                minQuantity: 2,
              });
              const item = toCustomerCatalogItem(row);
              if (productArchived || categoryArchived) {
                expect(item).toBeNull(); // archived in the catalog: not listed
              } else {
                expect(item?.isOrderable).toBe(expected);
              }
            }
          }
        }
      }
    }
  });

  it('does not list the store’s own removals', () => {
    expect(
      toCustomerCatalogItem(offering({ archivedAt: archived })),
    ).toBeNull();
  });

  it('never carries the stock, tracked or not', () => {
    const item = toCustomerCatalogItem(
      offering({ trackStock: true, stockQuantity: 41 }),
    )!;
    expect(JSON.stringify(item)).not.toMatch(/stock|41/i);
  });

  it('does not make an untracked product unavailable because of its stock figure', () => {
    expect(
      toCustomerCatalogItem(offering({ trackStock: false, stockQuantity: 0 }))
        ?.isOrderable,
    ).toBe(true);
  });
});

describe('toCustomerStore', () => {
  it('copies only the customer-facing fields', () => {
    const row = {
      id: 1,
      name: 'Market',
      description: null,
      photo: null,
      address: '12 Rue',
      latitude: 36.8,
      longitude: 10.1,
      isOpen: false,
      ownerId: 99,
    };
    const store = toCustomerStore(row);
    expect(store).toEqual({
      id: 1,
      name: 'Market',
      description: null,
      photo: null,
      address: '12 Rue',
      latitude: 36.8,
      longitude: 10.1,
      isOpen: false,
    });
    expect('ownerId' in store).toBe(false);
  });
});

describe('toCustomerCatalogItem brand', () => {
  it('carries the product’s brand — and only its id, slug and name', () => {
    const base = offering();
    const item = toCustomerCatalogItem({
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
    expect(item!.brand).toEqual({ id: 4, slug: 'heinz', name: 'Heinz' });
    expect(item).not.toHaveProperty('stockQuantity');
  });

  it('is null for a brandless product', () => {
    expect(toCustomerCatalogItem(offering())!.brand).toBeNull();
  });

  it('does not change what hides or disables a product', () => {
    const base = offering();
    const withBrand = {
      ...base.product!,
      brand: { id: 1, slug: 'b', name: 'B' },
    };
    expect(
      toCustomerCatalogItem({
        ...base,
        product: { ...withBrand, archivedAt: archived },
      }),
    ).toBeNull();
    expect(
      toCustomerCatalogItem({
        ...base,
        trackStock: true,
        stockQuantity: 0,
        product: withBrand,
      }),
    ).toMatchObject({
      isOrderable: false,
      unavailabilityReason: 'OUT_OF_STOCK',
    });
  });
});
