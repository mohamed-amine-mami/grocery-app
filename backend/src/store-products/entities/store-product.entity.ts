import { ApiProperty } from '@nestjs/swagger';
import type { UnavailabilityReason } from '../../products/product-rules.js';
import { SaleUnit } from '../../products/sale-unit.enum.js';

export class StoreProductCategoryEntity {
  @ApiProperty() id!: number;
  @ApiProperty() slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ description: 'false once archived in the catalog.' })
  isActive!: boolean;
}

export class StoreProductCatalogEntity {
  @ApiProperty() id!: number;
  @ApiProperty({ description: 'Stable catalog identifier.' }) slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) description!: string | null;
  @ApiProperty({ nullable: true, type: String, description: 'An image URL.' })
  photo!: string | null;
  @ApiProperty({ enum: SaleUnit }) defaultSaleUnit!: SaleUnit;
  @ApiProperty({
    enum: SaleUnit,
    isArray: true,
    description: 'The units this store may use: the default unit, or PIECE.',
  })
  allowedSaleUnits!: SaleUnit[];
  @ApiProperty({ description: 'Catalog default, in base units.' })
  defaultMinQuantity!: number;
  @ApiProperty() defaultQuantityStep!: number;
  @ApiProperty({ nullable: true, type: Number })
  defaultMaxQuantity!: number | null;
  @ApiProperty({ description: 'false once archived in the catalog.' })
  isActive!: boolean;
}

export const UNAVAILABILITY_REASONS = [
  'ARCHIVED',
  'OWNER_DISABLED',
  'CATALOG_ARCHIVED',
  'OUT_OF_STOCK',
  'STOCK_BELOW_MINIMUM',
] as const satisfies readonly UnavailabilityReason[];

export class StoreProductEntity {
  @ApiProperty() id!: number;
  @ApiProperty() productId!: number;
  @ApiProperty({ enum: SaleUnit }) saleUnit!: SaleUnit;
  @ApiProperty({
    description: 'Price of one sale unit, in millimes (4500 = 4.500 DT).',
  })
  priceMillimes!: number;
  @ApiProperty({ description: 'In base units: pieces / grams / millilitres.' })
  minQuantity!: number;
  @ApiProperty({ description: 'In base units.' }) quantityStep!: number;
  @ApiProperty({ nullable: true, type: Number, description: 'In base units.' })
  maxQuantity!: number | null;
  @ApiProperty({ description: 'Whether stock is tracked for this product.' })
  trackStock!: boolean;
  @ApiProperty({
    nullable: true,
    type: Number,
    description: 'Current stock in base units; null when stock is not tracked.',
  })
  stockQuantity!: number | null;
  @ApiProperty({ description: 'The owner’s manual on/off switch.' })
  isAvailable!: boolean;
  @ApiProperty({
    description:
      'Derived, never stored: can customers order this right now? Combines the archive state, the owner switch, the catalog state and tracked stock.',
  })
  isOrderable!: boolean;
  @ApiProperty({
    nullable: true,
    type: String,
    enum: UNAVAILABILITY_REASONS,
    description:
      'Why `isOrderable` is false: OUT_OF_STOCK = tracked stock is zero (automatic, no manual toggle needed); STOCK_BELOW_MINIMUM = stock is below the minimum order; OWNER_DISABLED; CATALOG_ARCHIVED; ARCHIVED.',
  })
  unavailabilityReason!: UnavailabilityReason | null;
  @ApiProperty({ nullable: true, type: String })
  archivedAt!: string | null;
  @ApiProperty() createdAt!: string;
  @ApiProperty() updatedAt!: string;
  @ApiProperty({ type: StoreProductCatalogEntity })
  product!: StoreProductCatalogEntity;
  @ApiProperty({ type: StoreProductCategoryEntity })
  category!: StoreProductCategoryEntity;
}

export class StockChangedEntity {
  @ApiProperty({ example: 409 }) statusCode!: number;
  @ApiProperty({ example: 'Conflict' }) error!: string;
  @ApiProperty({ example: 'STOCK_CHANGED' }) code!: string;
  @ApiProperty({ example: 'Stock changed since it was loaded' })
  message!: string;
  @ApiProperty({
    nullable: true,
    type: Number,
    description:
      'The stock right now (null if tracking was switched off meanwhile). Nothing from the request was applied.',
  })
  currentStockQuantity!: number | null;
}
