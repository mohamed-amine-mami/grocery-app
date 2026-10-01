import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional } from 'class-validator';

export const PRODUCT_STATUSES = ['active', 'archived', 'all'] as const;
export type ProductStatus = (typeof PRODUCT_STATUSES)[number];

export class ListProductsQuery {
  @ApiPropertyOptional({ description: 'Only products in this category.' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  categoryId?: number;

  @ApiPropertyOptional({
    enum: PRODUCT_STATUSES,
    default: 'active',
    description:
      '`active` (default) hides archived products — that is the normal catalog.',
  })
  @IsOptional()
  @IsIn(PRODUCT_STATUSES)
  status?: ProductStatus;
}
