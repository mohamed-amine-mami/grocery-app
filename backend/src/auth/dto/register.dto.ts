import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsEmail,
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MinLength,
} from 'class-validator';
import {
  normalizePhoneNumber,
  PHONE_NUMBER_PATTERN,
  trimString,
} from '../../common/transforms.js';
import { UserRole } from '../../users/user-role.enum.js';

export class RegisterDto {
  @ApiProperty({ example: 'Jane Doe' })
  @Transform(trimString)
  @IsString()
  @IsNotEmpty()
  name!: string;

  @ApiProperty({ example: 'jane@example.com' })
  @IsEmail()
  email!: string;

  @ApiProperty({ example: 'changeme123', minLength: 8 })
  @IsString()
  @MinLength(8)
  password!: string;

  @ApiProperty({
    example: '+21612345678',
    description:
      'Required and unique — used to log in. Optional leading +, then 8–15 digits (spaces, dots and dashes are ignored).',
  })
  @Transform(normalizePhoneNumber)
  @IsString()
  @Matches(PHONE_NUMBER_PATTERN, {
    message: 'phoneNumber must be a valid phone number',
  })
  phoneNumber!: string;

  @ApiPropertyOptional({ example: '+21612345678' })
  @IsOptional()
  @Transform(normalizePhoneNumber)
  @IsString()
  @Matches(PHONE_NUMBER_PATTERN, {
    message: 'whatsappNumber must be a valid phone number',
  })
  whatsappNumber?: string;

  @ApiPropertyOptional({ example: 'https://cdn.example.com/users/1/photo.jpg' })
  @IsOptional()
  @IsString()
  photo?: string;

  @ApiProperty({ enum: UserRole, description: 'The role to register as.' })
  @IsEnum(UserRole)
  role!: UserRole;
}
