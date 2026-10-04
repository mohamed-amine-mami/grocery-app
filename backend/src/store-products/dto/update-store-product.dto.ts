import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  Max,
  Min,
} from 'class-validator';
import { SaleUnit } from '../../products/sale-unit.enum.js';
import { MAX_PRICE_MILLIMES } from './create-store-product.dto.js';

/**
 * Every field is optional. `productId` is not editable, and availability has
 * its own endpoint. Cross-field rules live in `StoreProductsService.update`:
 *
 * - changing `saleUnit` requires `priceMillimes`, `minQuantity`, `quantityStep`
 *   (and `maxQuantity` when one is set, and `stockQuantity` while stock is
 *   tracked) in the same request, so old values are never reinterpreted;
 * - touching stock (`trackStock` or `stockQuantity`) requires
 *   `expectedStockQuantity`, so an owner's count can never silently overwrite
 *   a concurrent order.
 */
export class UpdateStoreProductDto {
  @ApiPropertyOptional({
    example: 4700,
    minimum: 1,
    maximum: MAX_PRICE_MILLIMES,
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(MAX_PRICE_MILLIMES)
  priceMillimes?: number;

  @ApiPropertyOptional({ enum: SaleUnit })
  @IsOptional()
  @IsEnum(SaleUnit)
  saleUnit?: SaleUnit;

  @ApiPropertyOptional({ example: 100 })
  @IsOptional()
  @IsInt()
  minQuantity?: number;

  @ApiPropertyOptional({ example: 100 })
  @IsOptional()
  @IsInt()
  quantityStep?: number;

  @ApiPropertyOptional({
    example: 10000,
    nullable: true,
    description: '`null` clears the maximum.',
  })
  @IsOptional()
  @IsInt()
  maxQuantity?: number | null;

  @ApiPropertyOptional({
    description:
      'Turn stock tracking on or off. Turning it off clears `stockQuantity`.',
  })
  @IsOptional()
  @IsBoolean()
  trackStock?: boolean;

  @ApiPropertyOptional({
    example: 20000,
    nullable: true,
    description:
      'Set the stock to this absolute quantity (base units). Requires `expectedStockQuantity`.',
  })
  @IsOptional()
  @IsInt()
  stockQuantity?: number | null;

  @ApiPropertyOptional({
    example: 7500,
    nullable: true,
    description:
      'The stock the client loaded (`null` if it was not tracked). Required whenever `trackStock` or `stockQuantity` is sent; never stored. If the stock changed meanwhile (an order, another device) nothing is applied and the response is 409 STOCK_CHANGED.',
  })
  @IsOptional()
  @IsInt()
  @Min(0)
  expectedStockQuantity?: number | null;
}
