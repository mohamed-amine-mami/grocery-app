import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  Max,
  Min,
} from 'class-validator';
import { SaleUnit } from '../../products/sale-unit.enum.js';

/** Sanity ceiling: 10 000 DT per sale unit. Also keeps the value inside int4. */
export const MAX_PRICE_MILLIMES = 10_000_000;

/**
 * How the owner's store sells one global catalog product. Only the offering
 * is configurable: the product's name, description, photo, category and slug
 * belong to the catalog and are rejected here (the global ValidationPipe
 * forbids unknown fields), as are `storeId` — it comes from the JWT.
 *
 * Unit-dependent rules (allowed units, granularity, ceilings, alignment, stock)
 * are checked in the service.
 */
export class CreateStoreProductDto {
  @ApiProperty({
    example: 12,
    description: 'A product from `GET /owner/catalog/products`.',
  })
  @IsInt()
  @Min(1)
  productId!: number;

  @ApiProperty({
    example: 4500,
    description:
      'Price of ONE sale unit (1 piece / 1 kg / 1 L) in millimes: 4500 = 4.500 DT.',
    minimum: 1,
    maximum: MAX_PRICE_MILLIMES,
  })
  @IsInt()
  @Min(1)
  @Max(MAX_PRICE_MILLIMES)
  priceMillimes!: number;

  @ApiPropertyOptional({
    enum: SaleUnit,
    description:
      "The product's default unit or PIECE. Defaults to the product's default unit.",
  })
  @IsOptional()
  @IsEnum(SaleUnit)
  saleUnit?: SaleUnit;

  @ApiPropertyOptional({
    example: 100,
    description:
      'Smallest orderable quantity, in base units (pieces / grams / mL). Omitted rules default to the catalog’s (or, in another unit, that unit’s own defaults).',
  })
  @IsOptional()
  @IsInt()
  minQuantity?: number;

  @ApiPropertyOptional({
    example: 100,
    description: 'Increment between orderable quantities, in base units.',
  })
  @IsOptional()
  @IsInt()
  quantityStep?: number;

  @ApiPropertyOptional({
    example: 10000,
    nullable: true,
    description:
      'Largest orderable quantity, in base units. `null` = no maximum; omitted = the catalog default.',
  })
  @IsOptional()
  @IsInt()
  maxQuantity?: number | null;

  @ApiPropertyOptional({
    default: false,
    description:
      'Track stock for this product. When true, `stockQuantity` is required.',
  })
  @IsOptional()
  @IsBoolean()
  trackStock?: boolean;

  @ApiPropertyOptional({
    example: 20000,
    nullable: true,
    description:
      'Current stock in base units (20 kg = 20000). Required when `trackStock` is true, and must be omitted otherwise.',
  })
  @IsOptional()
  @IsInt()
  stockQuantity?: number | null;

  @ApiPropertyOptional({
    default: true,
    description: 'The owner’s manual on/off switch.',
  })
  @IsOptional()
  @IsBoolean()
  isAvailable?: boolean;
}
