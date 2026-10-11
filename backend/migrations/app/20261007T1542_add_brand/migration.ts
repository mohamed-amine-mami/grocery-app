#!/usr/bin/env -S node
import type { Contract as Start } from '../../snapshots/68f0d36c1b49464620095d9ab4cb893baec9e5d4e07456dc47b561ff42e5d716/contract';
import startContract from '../../snapshots/68f0d36c1b49464620095d9ab4cb893baec9e5d4e07456dc47b561ff42e5d716/contract.json' with { type: 'json' };
import type { Contract as End } from '../../snapshots/b86c51ff3dbae33a9c1cf5448bd9f0b8d30d92a2c53cfac297e3b73c07f53cee/contract';
import endContract from '../../snapshots/b86c51ff3dbae33a9c1cf5448bd9f0b8d30d92a2c53cfac297e3b73c07f53cee/contract.json' with { type: 'json' };
import {
  Migration,
  MigrationCLI,
  checkExpression,
  col,
  fn,
  primaryKey,
} from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.dropIndex({
        schema: 'public',
        table: 'Product',
        index: 'product_active_name_unique_5e7c3ad3',
      }),
      this.createTable({
        schema: 'public',
        table: 'Brand',
        columns: [
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('name', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('slug', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression('brand_name_not_blank_8e77c20d', 'length(btrim("name")) > 0'),
          checkExpression('brand_slug_format_a1584675', '"slug" ~ \'^[a-z0-9]+(-[a-z0-9]+)*$\''),
        ],
      }),
      this.addColumn({
        schema: 'public',
        table: 'Product',
        column: col('brandId', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
      }),
      this.addUnique({
        schema: 'public',
        table: 'Brand',
        constraint: 'Brand_slug_key',
        columns: ['slug'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Brand',
        index: 'brand_name_unique_79c07e41',
        expression: 'lower("name")',
        extras: { unique: true },
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'Product_brandId_idx_02e95397',
        columns: ['brandId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'product_active_name_brand_unique_d7de78c7',
        expression: 'lower("name"), "brandId"',
        extras: { where: '("archivedAt" IS NULL AND "brandId" IS NOT NULL)', unique: true },
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'product_active_name_brandless_unique_c9016a84',
        expression: 'lower("name")',
        extras: { where: '("archivedAt" IS NULL AND "brandId" IS NULL)', unique: true },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Product',
        foreignKey: {
          name: 'Product_brandId_fkey',
          columns: ['brandId'],
          references: { schema: 'public', table: 'Brand', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
