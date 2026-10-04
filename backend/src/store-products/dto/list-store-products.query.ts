import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional } from 'class-validator';

export const STORE_PRODUCT_STATUSES = ['active', 'archived', 'all'] as const;
export type StoreProductStatus = (typeof STORE_PRODUCT_STATUSES)[number];

export class ListStoreProductsQuery {
  @ApiPropertyOptional({
    description: 'Only products in this (global) category.',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  categoryId?: number;

  @ApiPropertyOptional({
    enum: STORE_PRODUCT_STATUSES,
    default: 'active',
    description:
      '`active` (default) hides archived offerings — that is the normal catalogue.',
  })
  @IsOptional()
  @IsIn(STORE_PRODUCT_STATUSES)
  status?: StoreProductStatus;
}
