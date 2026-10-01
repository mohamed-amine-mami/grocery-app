#!/usr/bin/env -S node
import type { Contract as Start } from '../../snapshots/5e37fd12947e385c5cbfae22150046277d7430f14bcf943b7318ccb0de024f48/contract';
import startContract from '../../snapshots/5e37fd12947e385c5cbfae22150046277d7430f14bcf943b7318ccb0de024f48/contract.json' with { type: 'json' };
import type { Contract as End } from '../../snapshots/e9669e73c015740f2479e007c4d0ea6101c0007762d2913499a70828ebb3658f/contract';
import endContract from '../../snapshots/e9669e73c015740f2479e007c4d0ea6101c0007762d2913499a70828ebb3658f/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, col, fn, primaryKey } from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.createTable({
        schema: 'public',
        table: 'Category',
        columns: [
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('name', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('storeId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [primaryKey(['id'])],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Category',
        index: 'Category_storeId_idx_c545737d',
        columns: ['storeId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Category',
        index: 'category_store_name_unique_97705512',
        expression: '"storeId", lower("name")',
        extras: { unique: true },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Category',
        foreignKey: {
          name: 'Category_storeId_fkey',
          columns: ['storeId'],
          references: { schema: 'public', table: 'Store', columns: ['id'] },
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
