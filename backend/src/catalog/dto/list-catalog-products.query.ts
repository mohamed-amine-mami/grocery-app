import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional } from 'class-validator';

export class ListCatalogProductsQuery {
  @ApiPropertyOptional({ description: 'Only products in this category.' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  categoryId?: number;
}
