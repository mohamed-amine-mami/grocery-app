import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

export class CancelOrderDto {
  @ApiPropertyOptional({ maxLength: 500, example: 'Je ne peux plus passer.' })
  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(500)
  reason?: string;
}

/** The customer reads this reason, so an owner must give one. */
export class OwnerCancelOrderDto {
  @ApiProperty({
    maxLength: 500,
    example: 'Produit épuisé.',
    description: 'Required and non-empty; shown to the customer.',
  })
  @Transform(trim)
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  reason!: string;
}
