import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsString } from 'class-validator';
import { normalizePhoneNumber } from '../../common/transforms.js';

export class LoginDto {
  @ApiProperty({ example: '+21612345678' })
  @Transform(normalizePhoneNumber)
  @IsString()
  phoneNumber!: string;

  @ApiProperty({ example: 'changeme123' })
  @IsString()
  password!: string;
}
