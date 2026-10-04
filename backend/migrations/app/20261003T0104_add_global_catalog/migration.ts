#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/111aadcb153b84f9282fde53068672afc82149edeb6ef8bb7990b7179771f1c7/contract';
import endContract from '../../snapshots/111aadcb153b84f9282fde53068672afc82149edeb6ef8bb7990b7179771f1c7/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/1b3520a9f7b86c00e4e1ebcfec95b5b38d451bf1e90a0933a56f8c091100c8ed/contract';
import startContract from '../../snapshots/1b3520a9f7b86c00e4e1ebcfec95b5b38d451bf1e90a0933a56f8c091100c8ed/contract.json' with { type: 'json' };
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
        table: 'Category',
        columns: [
          col('archivedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('description', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('name', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('photo', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('slug', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression('category_name_not_blank_8e77c20d', 'length(btrim("name")) > 0'),
          checkExpression('category_slug_format_a1584675', '"slug" ~ \'^[a-z0-9]+(-[a-z0-9]+)*$\''),
        ],
      }),
      this.createTable({
        schema: 'public',
        table: 'Product',
        columns: [
          col('archivedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('categoryId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('defaultMaxQuantity', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
          col('defaultMinQuantity', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('defaultQuantityStep', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('defaultSaleUnit', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('description', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('name', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('photo', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('slug', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression(
            'Product_defaultSaleUnit_check_8107ba95',
            "\"defaultSaleUnit\" IN ('PIECE', 'KG', 'L')",
          ),
          checkExpression(
            'product_default_max_aligned_to_step_1d898355',
            '"defaultMaxQuantity" IS NULL OR "defaultMaxQuantity" % NULLIF("defaultQuantityStep", 0) = 0',
          ),
          checkExpression(
            'product_default_max_not_below_min_39cab239',
            '"defaultMaxQuantity" IS NULL OR "defaultMaxQuantity" >= "defaultMinQuantity"',
          ),
          checkExpression(
            'product_default_min_aligned_to_step_b0b13ee5',
            '"defaultMinQuantity" % NULLIF("defaultQuantityStep", 0) = 0',
          ),
          checkExpression('product_default_min_positive_c6cf8f9b', '"defaultMinQuantity" > 0'),
          checkExpression('product_default_step_positive_88ee7a51', '"defaultQuantityStep" > 0'),
          checkExpression('product_name_not_blank_8e77c20d', 'length(btrim("name")) > 0'),
          checkExpression('product_slug_format_a1584675', '"slug" ~ \'^[a-z0-9]+(-[a-z0-9]+)*$\''),
        ],
      }),
      this.createTable({
        schema: 'public',
        table: 'StoreProduct',
        columns: [
          col('archivedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('isAvailable', 'bool', {
            notNull: true,
            default: lit(true),
            codecRef: { codecId: 'pg/bool@1' },
          }),
          col('maxQuantity', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
          col('minQuantity', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('priceMillimes', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('productId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('quantityStep', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('saleUnit', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('stockQuantity', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
          col('storeId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('trackStock', 'bool', {
            notNull: true,
            default: lit(false),
            codecRef: { codecId: 'pg/bool@1' },
          }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression(
            'StoreProduct_saleUnit_check_e4ec9d4d',
            "\"saleUnit\" IN ('PIECE', 'KG', 'L')",
          ),
          checkExpression(
            'store_product_max_aligned_to_step_7a1e96ae',
            '"maxQuantity" IS NULL OR "maxQuantity" % NULLIF("quantityStep", 0) = 0',
          ),
          checkExpression(
            'store_product_max_not_below_min_d677fabe',
            '"maxQuantity" IS NULL OR "maxQuantity" >= "minQuantity"',
          ),
          checkExpression(
            'store_product_min_aligned_to_step_6feb37a8',
            '"minQuantity" % NULLIF("quantityStep", 0) = 0',
          ),
          checkExpression('store_product_min_positive_b981200f', '"minQuantity" > 0'),
          checkExpression('store_product_price_positive_a55c5a5a', '"priceMillimes" > 0'),
          checkExpression('store_product_step_positive_904d0517', '"quantityStep" > 0'),
          checkExpression(
            'store_product_stock_not_negative_4df0751e',
            '"stockQuantity" IS NULL OR "stockQuantity" >= 0',
          ),
          checkExpression(
            'store_product_stock_tracking_pairing_108fadc4',
            '"trackStock" = ("stockQuantity" IS NOT NULL)',
          ),
        ],
      }),
      this.addUnique({
        schema: 'public',
        table: 'Category',
        constraint: 'Category_slug_key',
        columns: ['slug'],
      }),
      this.addUnique({
        schema: 'public',
        table: 'Product',
        constraint: 'Product_slug_key',
        columns: ['slug'],
      }),
      this.addUnique({
        schema: 'public',
        table: 'StoreProduct',
        constraint: 'StoreProduct_storeId_productId_key',
        columns: ['storeId', 'productId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Category',
        index: 'category_active_name_unique_5e7c3ad3',
        expression: 'lower("name")',
        extras: { where: '("archivedAt" IS NULL)', unique: true },
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
        index: 'product_active_name_unique_5e7c3ad3',
        expression: 'lower("name")',
        extras: { where: '("archivedAt" IS NULL)', unique: true },
      }),
      this.createIndex({
        schema: 'public',
        table: 'StoreProduct',
        index: 'StoreProduct_productId_idx_5858600a',
        columns: ['productId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'StoreProduct',
        index: 'StoreProduct_storeId_idx_c545737d',
        columns: ['storeId'],
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Product',
        foreignKey: {
          name: 'Product_categoryId_fkey',
          columns: ['categoryId'],
          references: { schema: 'public', table: 'Category', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'StoreProduct',
        foreignKey: {
          name: 'StoreProduct_storeId_fkey',
          columns: ['storeId'],
          references: { schema: 'public', table: 'Store', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'StoreProduct',
        foreignKey: {
          name: 'StoreProduct_productId_fkey',
          columns: ['productId'],
          references: { schema: 'public', table: 'Product', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
