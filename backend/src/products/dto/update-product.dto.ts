import { PartialType } from '@nestjs/swagger';
import { CreateProductDto } from './create-product.dto.js';

/**
 * Every field is optional, but changing `saleUnit` also requires `priceMillimes`,
 * `minQuantity` and `quantityStep` (and `maxQuantity` when one is set) so the old
 * price and quantity rules are never silently reinterpreted in another unit.
 * That cross-field rule lives in `ProductsService.update`.
 *
 * `description`, `photo`, `categoryId` and `maxQuantity` accept `null` to clear them.
 */
export class UpdateProductDto extends PartialType(CreateProductDto) {}
