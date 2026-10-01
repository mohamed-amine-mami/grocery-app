import { ApiProperty } from '@nestjs/swagger';

export class CategoryEntity {
  @ApiProperty() id!: number;
  @ApiProperty() storeId!: number;
  @ApiProperty() name!: string;
  @ApiProperty() createdAt!: string;
  @ApiProperty() updatedAt!: string;
}
