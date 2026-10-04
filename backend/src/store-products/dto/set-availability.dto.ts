import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class SetAvailabilityDto {
  @ApiProperty({
    description:
      'The owner’s manual switch. false = temporarily unavailable. Not a deletion, and independent of stock.',
  })
  @IsBoolean()
  isAvailable!: boolean;
}
