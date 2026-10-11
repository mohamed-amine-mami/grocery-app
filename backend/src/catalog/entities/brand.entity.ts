import { ApiProperty } from '@nestjs/swagger';

/** A brand as every catalog read shows it. Brands are importer-managed. */
export class BrandSummaryEntity {
  @ApiProperty() id!: number;
  @ApiProperty({ description: 'Stable catalog identifier.' }) slug!: string;
  @ApiProperty() name!: string;
}
