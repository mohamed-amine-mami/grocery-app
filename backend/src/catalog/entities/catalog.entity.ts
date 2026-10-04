import { ApiProperty } from '@nestjs/swagger';
import { SaleUnit } from '../../products/sale-unit.enum.js';

export class CatalogCategoryEntity {
  @ApiProperty() id!: number;
  @ApiProperty({ description: 'Stable catalog identifier.' }) slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) description!: string | null;
  @ApiProperty({ nullable: true, type: String, description: 'An image URL.' })
  photo!: string | null;
  @ApiProperty({ description: 'Active products in this category.' })
  productCount!: number;
}

export class CatalogProductCategoryEntity {
  @ApiProperty() id!: number;
  @ApiProperty() slug!: string;
  @ApiProperty() name!: string;
}

export class CatalogProductEntity {
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
    description:
      'The units a store may sell it in: the default unit, or PIECE.',
  })
  allowedSaleUnits!: SaleUnit[];
  @ApiProperty({ description: 'Suggested rules, in base units.' })
  defaultMinQuantity!: number;
  @ApiProperty() defaultQuantityStep!: number;
  @ApiProperty({ nullable: true, type: Number })
  defaultMaxQuantity!: number | null;
  @ApiProperty({ type: CatalogProductCategoryEntity })
  category!: CatalogProductCategoryEntity;
  @ApiProperty({
    description:
      'The owner’s store currently sells it (an active store product).',
  })
  inMyStore!: boolean;
  @ApiProperty({
    nullable: true,
    type: Number,
    description:
      'The store product id when the store has one for this product — active or archived — otherwise null.',
  })
  storeProductId!: number | null;
  @ApiProperty({
    description:
      'The store has an archived store product for it: offer "restore" instead of "add".',
  })
  storeProductArchived!: boolean;
}
