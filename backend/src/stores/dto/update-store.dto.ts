import { ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { IsBoolean, IsOptional } from 'class-validator';
import { CreateStoreDto } from './create-store.dto.js';

/**
 * Every field is optional. The latitude/longitude pairing rule is enforced in
 * `StoresService.updateForOwner` (PartialType strips the DTO-level check).
 */
export class UpdateStoreDto extends PartialType(CreateStoreDto) {
  @ApiPropertyOptional({
    description: 'Whether the store currently accepts orders.',
  })
  @IsOptional()
  @IsBoolean()
  isOpen?: boolean;
}
