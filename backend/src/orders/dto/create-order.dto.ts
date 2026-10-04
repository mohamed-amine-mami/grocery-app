import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  IsISO8601,
  IsNumber,
  IsString,
  Length,
  Min,
  ValidateNested,
} from 'class-validator';

export class CreateOrderLineDto {
  @ApiProperty({ example: 12, description: 'A product offered by the store.' })
  @IsInt()
  @Min(1)
  storeProductId!: number;

  @ApiProperty({
    example: 500,
    description:
      'In base units (pieces / grams / millilitres). Whether it is allowed is decided by the product’s unit and min/step/max rules: a violation is 400 `INVALID_QUANTITY`.',
  })
  @IsNumber({ allowNaN: false, allowInfinity: false })
  quantity!: number;
}

/** The customer sends what they want; prices, totals, stock and status are the server's. */
export class CreateOrderDto {
  @ApiProperty({ example: 3 })
  @IsInt()
  @Min(1)
  storeId!: number;

  @ApiProperty({ type: CreateOrderLineDto, isArray: true })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => CreateOrderLineDto)
  lines!: CreateOrderLineDto[];

  @ApiProperty({
    example: '2026-10-05T16:30:00.000Z',
    description:
      'Advisory pickup time (ISO 8601): between 30 minutes and 48 hours from now, else 400 `INVALID_PICKUP_TIME`.',
  })
  @IsISO8601({ strict: true })
  requestedPickupAt!: string;

  @ApiProperty({
    example: 'b1f0c2d4-7a55-4e0e-9a3e-3c1f5d2f0a11',
    minLength: 1,
    maxLength: 100,
    description:
      'Chosen by the client for one attempt (a UUID is fine); a retry of that attempt reuses it and gets the original order. Reusing it for a different request is 409 `IDEMPOTENCY_KEY_REUSED`.',
  })
  @IsString()
  @Length(1, 100)
  idempotencyKey!: string;
}
