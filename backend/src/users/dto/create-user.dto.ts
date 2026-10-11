import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsEmail,
  IsEnum,
  IsOptional,
  IsString,
  MinLength,
} from 'class-validator';
import { UserRole } from '../user-role.enum.js';

export class CreateUserDto {
  @ApiProperty({ example: 'Jane Doe' })
  @IsString()
  name!: string;

  @ApiProperty({ example: 'jane@example.com' })
  @IsEmail()
  email!: string;

  @ApiProperty({
    example: 'changeme123',
    minLength: 8,
    description: 'Hashed before storage; never returned by the API.',
  })
  @IsString()
  @MinLength(8)
  password!: string;

  @ApiProperty({
    example: '+21612345678',
    description: 'Required and unique — used to log in.',
  })
  @IsString()
  phoneNumber!: string;

  @ApiPropertyOptional({ example: '+21612345678' })
  @IsOptional()
  @IsString()
  whatsappNumber?: string;

  @ApiPropertyOptional({ enum: UserRole, default: UserRole.CLIENT })
  @IsOptional()
  @IsEnum(UserRole)
  role?: UserRole;
}
