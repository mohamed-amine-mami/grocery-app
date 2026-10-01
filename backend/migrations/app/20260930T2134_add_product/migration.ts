#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/54abcc0bd3e3d7a10ba82cfd92b9c750ca92321b0140e6e6afc5713eb0ad2b46/contract';
import endContract from '../../snapshots/54abcc0bd3e3d7a10ba82cfd92b9c750ca92321b0140e6e6afc5713eb0ad2b46/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/e9669e73c015740f2479e007c4d0ea6101c0007762d2913499a70828ebb3658f/contract';
import startContract from '../../snapshots/e9669e73c015740f2479e007c4d0ea6101c0007762d2913499a70828ebb3658f/contract.json' with { type: 'json' };
import {
  Migration,
  MigrationCLI,
  checkExpression,
  col,
  fn,
  lit,
  primaryKey,
} from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.createTable({
        schema: 'public',
        table: 'Product',
        columns: [
          col('archivedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('categoryId', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('description', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('isAvailable', 'bool', {
            notNull: true,
            default: lit(true),
            codecRef: { codecId: 'pg/bool@1' },
          }),
          col('maxQuantity', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
          col('minQuantity', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('name', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('photo', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('priceMillimes', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('quantityStep', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('saleUnit', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('storeId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression(
            'Product_saleUnit_check_e4ec9d4d',
            "\"saleUnit\" IN ('PIECE', 'KG', 'L')",
          ),
          checkExpression(
            'product_max_aligned_to_step_7a1e96ae',
            '"maxQuantity" IS NULL OR "maxQuantity" % NULLIF("quantityStep", 0) = 0',
          ),
          checkExpression(
            'product_max_not_below_min_d677fabe',
            '"maxQuantity" IS NULL OR "maxQuantity" >= "minQuantity"',
          ),
          checkExpression(
            'product_min_aligned_to_step_6feb37a8',
            '"minQuantity" % NULLIF("quantityStep", 0) = 0',
          ),
          checkExpression('product_min_quantity_positive_b981200f', '"minQuantity" > 0'),
          checkExpression('product_name_not_blank_8e77c20d', 'length(btrim("name")) > 0'),
          checkExpression('product_price_positive_a55c5a5a', '"priceMillimes" > 0'),
          checkExpression('product_quantity_step_positive_904d0517', '"quantityStep" > 0'),
        ],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'Product_categoryId_idx_15c304f2',
        columns: ['categoryId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'Product_storeId_categoryId_idx_048064b5',
        columns: ['storeId', 'categoryId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'Product_storeId_idx_c545737d',
        columns: ['storeId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Product',
        index: 'product_store_active_name_unique_571c2e2d',
        expression: '"storeId", lower("name")',
        extras: { where: '("archivedAt" IS NULL)', unique: true },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Product',
        foreignKey: {
          name: 'Product_storeId_fkey',
          columns: ['storeId'],
          references: { schema: 'public', table: 'Store', columns: ['id'] },
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Product',
        foreignKey: {
          name: 'Product_categoryId_fkey',
          columns: ['categoryId'],
          references: { schema: 'public', table: 'Category', columns: ['id'] },
          onDelete: 'setNull',
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
