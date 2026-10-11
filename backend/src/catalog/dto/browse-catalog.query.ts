import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export const CATALOG_PAGE_DEFAULT_LIMIT = 50;
export const CATALOG_PAGE_MAX_LIMIT = 100;
export const CATALOG_SEARCH_MAX_LENGTH = 100;
/** The largest id of a PostgreSQL `integer` column. */
export const INT4_MAX = 2_147_483_647;

export class BrowseCatalogQuery {
  @ApiPropertyOptional({
    description:
      'Search words. Every word must appear in the product name, brand or category name, in any order, ignoring case and accents.',
    maxLength: CATALOG_SEARCH_MAX_LENGTH,
  })
  @IsOptional()
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @MaxLength(CATALOG_SEARCH_MAX_LENGTH)
  // PostgreSQL text cannot hold a NUL byte (the control character is the point).
  // oxlint-disable-next-line no-control-regex
  @Matches(/^[^\u0000]*$/, { message: 'q must not contain a NUL character' })
  q?: string;

  @ApiPropertyOptional({
    description: 'Only products in this category.',
    minimum: 1,
    maximum: INT4_MAX,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(INT4_MAX)
  categoryId?: number;

  @ApiPropertyOptional({
    description: `Page size, at most ${CATALOG_PAGE_MAX_LIMIT}.`,
    default: CATALOG_PAGE_DEFAULT_LIMIT,
    minimum: 1,
    maximum: CATALOG_PAGE_MAX_LIMIT,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(CATALOG_PAGE_MAX_LIMIT)
  limit?: number;

  @ApiPropertyOptional({
    description:
      'The `nextCursor` of the previous page. Omit it for the first page.',
    maxLength: 400,
  })
  @IsOptional()
  @IsString()
  @MaxLength(400)
  cursor?: string;
}
