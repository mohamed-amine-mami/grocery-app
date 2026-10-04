import { ApiProperty } from '@nestjs/swagger';
import { SaleUnit } from '../../products/sale-unit.enum.js';
import { UNAVAILABILITY_REASONS } from '../../store-products/entities/store-product.entity.js';

/**
 * What a customer may see. Written out field by field (never derived from a
 * database row) so a column added later cannot leak: there is no stock figure,
 * no owner, and no internal catalog configuration anywhere in these shapes.
 */

export class CustomerStoreEntity {
  @ApiProperty() id!: number;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) description!: string | null;
  @ApiProperty({ nullable: true, type: String, description: 'An image URL.' })
  photo!: string | null;
  @ApiProperty() address!: string;
  @ApiProperty({ nullable: true, type: Number }) latitude!: number | null;
  @ApiProperty({ nullable: true, type: Number }) longitude!: number | null;
  @ApiProperty({
    description:
      'Whether the store accepts new orders. A closed store can still be browsed.',
  })
  isOpen!: boolean;
}

export class CustomerCategoryEntity {
  @ApiProperty() id!: number;
  @ApiProperty() name!: string;
}

export class CustomerCatalogItemEntity {
  @ApiProperty({
    description: 'The store product id: what `POST /orders` lines refer to.',
  })
  id!: number;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) description!: string | null;
  @ApiProperty({ nullable: true, type: String, description: 'An image URL.' })
  photo!: string | null;
  @ApiProperty({ type: CustomerCategoryEntity })
  category!: CustomerCategoryEntity;
  @ApiProperty({ enum: SaleUnit }) saleUnit!: SaleUnit;
  @ApiProperty({
    description:
      'This store’s price of one sale unit, in millimes (4500 = 4.500 DT).',
  })
  priceMillimes!: number;
  @ApiProperty({ description: 'In base units: pieces / grams / millilitres.' })
  minQuantity!: number;
  @ApiProperty({ description: 'In base units.' }) quantityStep!: number;
  @ApiProperty({ nullable: true, type: Number, description: 'In base units.' })
  maxQuantity!: number | null;
  @ApiProperty({
    description:
      'Derived on every read by the canonical rule (`product-rules.ts`); a hint only. `POST /orders` revalidates everything.',
  })
  isOrderable!: boolean;
  @ApiProperty({
    nullable: true,
    enum: UNAVAILABILITY_REASONS,
    description:
      'Why it cannot be ordered right now, or null. Never a quantity. Offerings the store removed and products archived in the catalog are not listed at all.',
  })
  unavailabilityReason!: (typeof UNAVAILABILITY_REASONS)[number] | null;
}
