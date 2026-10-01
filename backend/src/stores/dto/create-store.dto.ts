import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsLatitude,
  IsLongitude,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
  ValidateIf,
} from 'class-validator';
import {
  ADDRESS_MAX_LENGTH,
  DESCRIPTION_MAX_LENGTH,
  NAME_MAX_LENGTH,
  PHOTO_URL_OPTIONS,
  URL_MAX_LENGTH,
} from '../../common/limits.js';
import { trimString } from '../../common/transforms.js';

/** True when either coordinate is present, so the other becomes mandatory. */
const hasAnyCoordinate = (store: CreateStoreDto) =>
  store.latitude !== undefined || store.longitude !== undefined;

/**
 * The owner is never part of the payload — it comes from the JWT. A new store
 * always starts closed, so `isOpen` is not accepted here either.
 */
export class CreateStoreDto {
  @ApiProperty({ example: 'Downtown Grocery' })
  @Transform(trimString)
  @IsString()
  @IsNotEmpty()
  @MaxLength(NAME_MAX_LENGTH)
  name!: string;

  @ApiPropertyOptional({
    example: 'Fresh produce and pantry staples, open daily.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(DESCRIPTION_MAX_LENGTH)
  description?: string;

  @ApiPropertyOptional({
    example: 'https://cdn.example.com/stores/1/photo.jpg',
  })
  @IsOptional()
  @IsUrl(PHOTO_URL_OPTIONS)
  @MaxLength(URL_MAX_LENGTH)
  photo?: string;

  @ApiProperty({
    example: '12 Rue de la Liberté, Menzah 5, Tunis',
    description: 'Readable pickup address shown to customers.',
  })
  @Transform(trimString)
  @IsString()
  @IsNotEmpty()
  @MaxLength(ADDRESS_MAX_LENGTH)
  address!: string;

  @ApiPropertyOptional({
    example: 36.8065,
    description: 'Must be sent together with longitude, or not at all.',
  })
  @ValidateIf(hasAnyCoordinate)
  @IsLatitude()
  latitude?: number;

  @ApiPropertyOptional({
    example: 10.1815,
    description: 'Must be sent together with latitude, or not at all.',
  })
  @ValidateIf(hasAnyCoordinate)
  @IsLongitude()
  longitude?: number;
}
