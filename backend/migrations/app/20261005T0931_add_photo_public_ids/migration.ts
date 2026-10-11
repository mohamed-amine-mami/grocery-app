#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/68f0d36c1b49464620095d9ab4cb893baec9e5d4e07456dc47b561ff42e5d716/contract';
import endContract from '../../snapshots/68f0d36c1b49464620095d9ab4cb893baec9e5d4e07456dc47b561ff42e5d716/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/730b67859727db3afde3dabade2382ad31f564fc87503acbab849fccb306f7a3/contract';
import startContract from '../../snapshots/730b67859727db3afde3dabade2382ad31f564fc87503acbab849fccb306f7a3/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, col } from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.addColumn({
        schema: 'public',
        table: 'Store',
        column: col('photoPublicId', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'User',
        column: col('photoPublicId', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addCheckConstraint({
        schema: 'public',
        table: 'Store',
        constraint: 'store_photo_public_id_needs_photo_88abf07f',
        expression: '"photoPublicId" IS NULL OR "photo" IS NOT NULL',
      }),
      this.addCheckConstraint({
        schema: 'public',
        table: 'User',
        constraint: 'user_photo_public_id_needs_photo_88abf07f',
        expression: '"photoPublicId" IS NULL OR "photo" IS NOT NULL',
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
