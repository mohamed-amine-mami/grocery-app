import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { MAX_ORDERS_PAGE_LIMIT } from '../order-queries.service.js';
import { OrderStatus } from '../order-status.enum.js';

export class ListOrdersQuery {
  @ApiPropertyOptional({ default: 1, minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1_000_000)
  page?: number;

  @ApiPropertyOptional({
    default: 20,
    minimum: 1,
    maximum: MAX_ORDERS_PAGE_LIMIT,
    description: 'Page size; newest orders first.',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_ORDERS_PAGE_LIMIT)
  limit?: number;
}

export class ListOwnerOrdersQuery extends ListOrdersQuery {
  @ApiPropertyOptional({
    enum: OrderStatus,
    description: 'Only orders in this status.',
  })
  @IsOptional()
  @IsEnum(OrderStatus)
  status?: OrderStatus;
}
