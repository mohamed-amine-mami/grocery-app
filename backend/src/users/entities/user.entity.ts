import { ApiProperty } from '@nestjs/swagger';
import { UserRole } from '../user-role.enum.js';

/**
 * Public shape of a User row. Never includes `password`.
 */
export class UserEntity {
  @ApiProperty() id!: number;
  @ApiProperty() name!: string;
  @ApiProperty() email!: string;
  @ApiProperty() phoneNumber!: string;
  @ApiProperty({ nullable: true, type: String }) whatsappNumber!: string | null;
  @ApiProperty({ nullable: true, type: String }) photo!: string | null;
  @ApiProperty({ enum: UserRole }) role!: UserRole;
  @ApiProperty() createdAt!: string;
  @ApiProperty() updatedAt!: string;
}
