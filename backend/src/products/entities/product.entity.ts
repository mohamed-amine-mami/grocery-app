import { ApiProperty } from '@nestjs/swagger';
import { SaleUnit } from '../sale-unit.enum.js';

export class ProductEntity {
  @ApiProperty() id!: number;
  @ApiProperty() storeId!: number;
  @ApiProperty({ nullable: true, type: Number }) categoryId!: number | null;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) description!: string | null;
  @ApiProperty({ nullable: true, type: String }) photo!: string | null;
  @ApiProperty({ enum: SaleUnit }) saleUnit!: SaleUnit;
  @ApiProperty({
    description: 'Price of one sale unit, in millimes (1800 = 1.800 DT).',
  })
  priceMillimes!: number;
  @ApiProperty({ description: 'In base units: pieces / grams / millilitres.' })
  minQuantity!: number;
  @ApiProperty({ description: 'In base units.' }) quantityStep!: number;
  @ApiProperty({ nullable: true, type: Number, description: 'In base units.' })
  maxQuantity!: number | null;
  @ApiProperty({ description: 'false = temporarily unavailable.' })
  isAvailable!: boolean;
  @ApiProperty({
    nullable: true,
    type: String,
    description:
      'Set when archived; the product is then hidden from the catalog.',
  })
  archivedAt!: string | null;
  @ApiProperty() createdAt!: string;
  @ApiProperty() updatedAt!: string;
}
