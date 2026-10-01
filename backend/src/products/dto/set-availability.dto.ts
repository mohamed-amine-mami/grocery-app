import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class SetAvailabilityDto {
  @ApiProperty({
    description:
      'false = temporarily unavailable (e.g. out of stock today). Not a deletion.',
  })
  @IsBoolean()
  isAvailable!: boolean;
}
