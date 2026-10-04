import { ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMaxSize, IsArray, IsInt, IsOptional, Min } from 'class-validator';

/** The only thing an owner can adjust when confirming: which lines to drop. */
export class ConfirmOrderDto {
  @ApiPropertyOptional({
    type: Number,
    isArray: true,
    example: [41],
    description:
      'Ids of the order’s items (`items[].id`) the store cannot fulfil. They are removed, not deleted, their stock is given back and the total is recomputed. Removing every line is rejected (cancel the order instead). Ignored when the order is already CONFIRMED.',
  })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsInt({ each: true })
  @Min(1, { each: true })
  removeItemIds?: number[];
}
