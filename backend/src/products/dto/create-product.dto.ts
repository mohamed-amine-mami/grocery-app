import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUrl,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import {
  DESCRIPTION_MAX_LENGTH,
  NAME_MAX_LENGTH,
  PHOTO_URL_OPTIONS,
  URL_MAX_LENGTH,
} from '../../common/limits.js';
import { trimString } from '../../common/transforms.js';
import { SaleUnit } from '../sale-unit.enum.js';

/** Sanity ceiling: 10 000 DT per sale unit. Also keeps the value inside int4. */
export const MAX_PRICE_MILLIMES = 10_000_000;

/**
 * The store is never part of the payload — it comes from the JWT. Unit-dependent
 * quantity rules (granularity, ceilings, alignment) are checked in the service.
 */
export class CreateProductDto {
  @ApiProperty({
    example: 'Tomates',
    description: 'Unique among the store’s active products, ignoring case.',
  })
  @Transform(trimString)
  @IsString()
  @IsNotEmpty()
  @MaxLength(NAME_MAX_LENGTH)
  name!: string;

  @ApiPropertyOptional({ example: 'Tomates de saison.' })
  @IsOptional()
  @IsString()
  @MaxLength(DESCRIPTION_MAX_LENGTH)
  description?: string;

  @ApiPropertyOptional({
    example: 'https://cdn.example.com/products/tomates.jpg',
    description:
      'A URL string, like store and user photos — there is no upload yet.',
  })
  @IsOptional()
  @IsUrl(PHOTO_URL_OPTIONS)
  @MaxLength(URL_MAX_LENGTH)
  photo?: string;

  @ApiPropertyOptional({
    example: 1,
    description:
      'A category of this owner’s store. Omit (or null) for an uncategorized product.',
  })
  @IsOptional()
  @IsInt()
  categoryId?: number;

  @ApiProperty({
    enum: SaleUnit,
    description:
      'PIECE: priced per piece. KG: priced per kilogram, quantities in grams. L: priced per litre, quantities in millilitres.',
  })
  @IsEnum(SaleUnit)
  saleUnit!: SaleUnit;

  @ApiProperty({
    example: 1800,
    description:
      'Price of ONE sale unit (1 piece / 1 kg / 1 L) in millimes: 1800 = 1.800 DT.',
    minimum: 1,
    maximum: MAX_PRICE_MILLIMES,
  })
  @IsInt()
  @Min(1)
  @Max(MAX_PRICE_MILLIMES)
  priceMillimes!: number;

  @ApiPropertyOptional({
    example: 500,
    description:
      'Smallest orderable quantity, in base units (pieces / grams / mL). Defaults to one step.',
  })
  @IsOptional()
  @IsInt()
  minQuantity?: number;

  @ApiPropertyOptional({
    example: 500,
    description:
      'Increment between orderable quantities, in base units. Defaults per unit: PIECE 1, KG 100 g, L 100 mL.',
  })
  @IsOptional()
  @IsInt()
  quantityStep?: number;

  @ApiPropertyOptional({
    example: 10000,
    description:
      'Largest orderable quantity, in base units. Omit for no maximum.',
  })
  @IsOptional()
  @IsInt()
  maxQuantity?: number;
}
