import { ApiProperty } from '@nestjs/swagger';

export class StoreEntity {
  @ApiProperty() id!: number;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) description!: string | null;
  @ApiProperty({ nullable: true, type: String }) photo!: string | null;
  @ApiProperty() address!: string;
  @ApiProperty({ nullable: true, type: Number }) latitude!: number | null;
  @ApiProperty({ nullable: true, type: Number }) longitude!: number | null;
  @ApiProperty({ description: 'New stores start closed.' }) isOpen!: boolean;
  @ApiProperty() ownerId!: number;
  @ApiProperty() createdAt!: string;
  @ApiProperty() updatedAt!: string;
}
