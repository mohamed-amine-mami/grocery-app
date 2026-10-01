import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';
import { trimString } from '../../common/transforms.js';

export const CATEGORY_NAME_MAX_LENGTH = 50;

export class CreateCategoryDto {
  @ApiProperty({
    example: 'Fruits & Légumes',
    maxLength: CATEGORY_NAME_MAX_LENGTH,
    description:
      'Unique within the store, ignoring letter case. Leading/trailing spaces are trimmed.',
  })
  @Transform(trimString)
  @IsString()
  @IsNotEmpty()
  @MaxLength(CATEGORY_NAME_MAX_LENGTH)
  name!: string;
}
