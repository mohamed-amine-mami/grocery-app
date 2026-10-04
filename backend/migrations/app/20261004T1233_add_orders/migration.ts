#!/usr/bin/env -S node
import type { Contract as Start } from '../../snapshots/111aadcb153b84f9282fde53068672afc82149edeb6ef8bb7990b7179771f1c7/contract';
import startContract from '../../snapshots/111aadcb153b84f9282fde53068672afc82149edeb6ef8bb7990b7179771f1c7/contract.json' with { type: 'json' };
import type { Contract as End } from '../../snapshots/730b67859727db3afde3dabade2382ad31f564fc87503acbab849fccb306f7a3/contract';
import endContract from '../../snapshots/730b67859727db3afde3dabade2382ad31f564fc87503acbab849fccb306f7a3/contract.json' with { type: 'json' };
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
        table: 'Order',
        columns: [
          col('code', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('customerId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('idempotencyKey', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('requestedPickupAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('status', 'text', {
            notNull: true,
            default: lit('PENDING'),
            codecRef: { codecId: 'pg/text@1' },
          }),
          col('storeId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('totalMillimes', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('updatedAt', 'timestamptz', {
            notNull: true,
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression(
            'Order_status_check_9100ae0a',
            "\"status\" IN ('PENDING', 'CONFIRMED', 'READY_FOR_PICKUP', 'COMPLETED', 'CANCELLED', 'NO_SHOW')",
          ),
          checkExpression('order_code_format_e5fae505', '"code" ~ \'^[A-Z0-9]{4,12}$\''),
          checkExpression(
            'order_idempotency_key_valid_da0a9e05',
            'length(btrim("idempotencyKey")) > 0 AND length("idempotencyKey") <= 100',
          ),
          checkExpression(
            'order_pickup_after_creation_ac6233ab',
            '"requestedPickupAt" > "createdAt"',
          ),
          checkExpression('order_total_positive_0d00e7d4', '"totalMillimes" > 0'),
        ],
      }),
      this.createTable({
        schema: 'public',
        table: 'OrderItem',
        columns: [
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('lineTotalMillimes', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('orderId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('productNameSnapshot', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('quantity', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('removedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('saleUnitSnapshot', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('stockDecrementedQuantity', 'int4', {
            notNull: true,
            default: lit(0),
            codecRef: { codecId: 'pg/int4@1' },
          }),
          col('storeProductId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('unitPriceMillimes', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression(
            'OrderItem_saleUnitSnapshot_check_3cb18f4a',
            "\"saleUnitSnapshot\" IN ('PIECE', 'KG', 'L')",
          ),
          checkExpression(
            'order_item_line_total_not_negative_33f581ad',
            '"lineTotalMillimes" >= 0',
          ),
          checkExpression(
            'order_item_name_not_blank_13cd1dc1',
            'length(btrim("productNameSnapshot")) > 0',
          ),
          checkExpression('order_item_price_positive_e97b883a', '"unitPriceMillimes" > 0'),
          checkExpression('order_item_quantity_positive_fc510296', '"quantity" > 0'),
          checkExpression(
            'order_item_stock_decrement_within_quantity_a5360ece',
            '"stockDecrementedQuantity" >= 0 AND "stockDecrementedQuantity" <= "quantity"',
          ),
        ],
      }),
      this.createTable({
        schema: 'public',
        table: 'OrderStatusEvent',
        columns: [
          col('actorId', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
          col('actorType', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('fromStatus', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('orderId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('reason', 'text', { codecRef: { codecId: 'pg/text@1' } }),
          col('toStatus', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
        ],
        constraints: [
          primaryKey(['id']),
          checkExpression(
            'OrderStatusEvent_actorType_check_a9954e09',
            "\"actorType\" IN ('CLIENT', 'OWNER', 'SYSTEM', 'CHANNEL')",
          ),
          checkExpression(
            'OrderStatusEvent_fromStatus_check_7276900f',
            "\"fromStatus\" IN ('PENDING', 'CONFIRMED', 'READY_FOR_PICKUP', 'COMPLETED', 'CANCELLED', 'NO_SHOW')",
          ),
          checkExpression(
            'OrderStatusEvent_toStatus_check_f1443096',
            "\"toStatus\" IN ('PENDING', 'CONFIRMED', 'READY_FOR_PICKUP', 'COMPLETED', 'CANCELLED', 'NO_SHOW')",
          ),
          checkExpression(
            'order_event_creation_is_pending_2abbe34f',
            '"fromStatus" IS NOT NULL OR "toStatus" = \'PENDING\'',
          ),
          checkExpression(
            'order_event_reason_valid_21080fa7',
            '"reason" IS NULL OR (length(btrim("reason")) > 0 AND length("reason") <= 500)',
          ),
          checkExpression(
            'order_event_status_changes_408c2336',
            '"fromStatus" IS NULL OR "fromStatus" <> "toStatus"',
          ),
          checkExpression(
            'order_event_system_has_no_actor_4b73ef4b',
            '"actorType" <> \'SYSTEM\' OR "actorId" IS NULL',
          ),
          checkExpression(
            'order_event_user_actor_has_id_026e3432',
            '"actorType" NOT IN (\'CLIENT\', \'OWNER\') OR "actorId" IS NOT NULL',
          ),
        ],
      }),
      this.addUnique({
        schema: 'public',
        table: 'Order',
        constraint: 'Order_code_key',
        columns: ['code'],
      }),
      this.addUnique({
        schema: 'public',
        table: 'Order',
        constraint: 'Order_customerId_idempotencyKey_key',
        columns: ['customerId', 'idempotencyKey'],
      }),
      this.addUnique({
        schema: 'public',
        table: 'OrderItem',
        constraint: 'OrderItem_orderId_storeProductId_key',
        columns: ['orderId', 'storeProductId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Order',
        index: 'Order_customerId_createdAt_idx_f10a1fb1',
        columns: ['customerId', 'createdAt'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Order',
        index: 'Order_customerId_idx_b2a8a46c',
        columns: ['customerId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Order',
        index: 'Order_storeId_idx_c545737d',
        columns: ['storeId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'Order',
        index: 'Order_storeId_status_idx_81db0ee8',
        columns: ['storeId', 'status'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'OrderItem',
        index: 'OrderItem_orderId_idx_d284871b',
        columns: ['orderId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'OrderItem',
        index: 'OrderItem_storeProductId_idx_117e89a7',
        columns: ['storeProductId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'OrderStatusEvent',
        index: 'OrderStatusEvent_actorId_idx_a58f6b4b',
        columns: ['actorId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'OrderStatusEvent',
        index: 'OrderStatusEvent_orderId_createdAt_idx_cf5e070a',
        columns: ['orderId', 'createdAt'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'OrderStatusEvent',
        index: 'OrderStatusEvent_orderId_idx_d284871b',
        columns: ['orderId'],
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Order',
        foreignKey: {
          name: 'Order_customerId_fkey',
          columns: ['customerId'],
          references: { schema: 'public', table: 'User', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'Order',
        foreignKey: {
          name: 'Order_storeId_fkey',
          columns: ['storeId'],
          references: { schema: 'public', table: 'Store', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'OrderItem',
        foreignKey: {
          name: 'OrderItem_orderId_fkey',
          columns: ['orderId'],
          references: { schema: 'public', table: 'Order', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'OrderItem',
        foreignKey: {
          name: 'OrderItem_storeProductId_fkey',
          columns: ['storeProductId'],
          references: { schema: 'public', table: 'StoreProduct', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'OrderStatusEvent',
        foreignKey: {
          name: 'OrderStatusEvent_orderId_fkey',
          columns: ['orderId'],
          references: { schema: 'public', table: 'Order', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'OrderStatusEvent',
        foreignKey: {
          name: 'OrderStatusEvent_actorId_fkey',
          columns: ['actorId'],
          references: { schema: 'public', table: 'User', columns: ['id'] },
          onDelete: 'restrict',
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
