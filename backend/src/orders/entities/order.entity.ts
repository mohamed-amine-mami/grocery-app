import { ApiProperty } from '@nestjs/swagger';
import { SaleUnit } from '../../products/sale-unit.enum.js';
import { OrderActorType } from '../order-actor-type.enum.js';
import { OrderStatus } from '../order-status.enum.js';

/**
 * Response shapes for orders. They are written out here, not derived from the
 * database rows, so a column added later is never exposed by accident. In
 * particular `stockDecrementedQuantity` (internal stock accounting) and the
 * idempotency key appear in no response.
 */

export class OrderItemEntity {
  @ApiProperty({
    description: 'Use this id in `removeItemIds` when confirming.',
  })
  id!: number;
  @ApiProperty() storeProductId!: number;
  @ApiProperty({ description: 'The name when the order was placed.' })
  productName!: string;
  @ApiProperty({
    enum: SaleUnit,
    description: 'The unit when the order was placed.',
  })
  saleUnit!: SaleUnit;
  @ApiProperty({ description: 'In base units: pieces / grams / millilitres.' })
  quantity!: number;
  @ApiProperty({
    description: 'Price of one sale unit when ordered, in millimes.',
  })
  unitPriceMillimes!: number;
  @ApiProperty({ description: 'In millimes.' }) lineTotalMillimes!: number;
  @ApiProperty({
    nullable: true,
    type: String,
    description:
      'Set when the store removed this line while confirming; it no longer counts toward the total.',
  })
  removedAt!: string | null;
}

export class OrderEventEntity {
  @ApiProperty({
    enum: OrderStatus,
    nullable: true,
    description: 'null for the creation event.',
  })
  fromStatus!: OrderStatus | null;
  @ApiProperty({ enum: OrderStatus }) toStatus!: OrderStatus;
  @ApiProperty({
    enum: OrderActorType,
    description:
      'Who did it: CLIENT (the customer) or OWNER (the store). A cancellation by OWNER is a store cancellation.',
  })
  actorType!: OrderActorType;
  @ApiProperty({
    nullable: true,
    type: String,
    description: 'The cancellation reason, when there is one.',
  })
  reason!: string | null;
  @ApiProperty() createdAt!: string;
}

export class OrderStoreEntity {
  @ApiProperty() id!: number;
  @ApiProperty() name!: string;
  @ApiProperty() address!: string;
}

export class OrderCustomerEntity {
  @ApiProperty() name!: string;
  @ApiProperty() phoneNumber!: string;
}

class OrderBaseEntity {
  @ApiProperty() id!: number;
  @ApiProperty({
    example: 'K7M2QX',
    description: 'The order reference and pickup code.',
  })
  code!: string;
  @ApiProperty({ enum: OrderStatus }) status!: OrderStatus;
  @ApiProperty({ description: 'Advisory pickup time, not a reserved slot.' })
  requestedPickupAt!: string;
  @ApiProperty({
    description:
      'Sum of the lines that are not removed, in millimes. Estimated for weighed products.',
  })
  totalMillimes!: number;
  @ApiProperty({
    description: 'True when the store removed at least one line.',
  })
  storeAdjusted!: boolean;
  @ApiProperty({
    type: OrderItemEntity,
    isArray: true,
    description: 'Removed lines included (see `removedAt`).',
  })
  items!: OrderItemEntity[];
  @ApiProperty({
    type: OrderEventEntity,
    isArray: true,
    description: 'Status history, oldest first.',
  })
  events!: OrderEventEntity[];
  @ApiProperty() createdAt!: string;
  @ApiProperty() updatedAt!: string;
}

/** What a customer sees of their own order. */
export class CustomerOrderEntity extends OrderBaseEntity {
  @ApiProperty({ type: OrderStoreEntity }) store!: OrderStoreEntity;
}

/** What an owner sees of an order of their store. */
export class OwnerOrderEntity extends OrderBaseEntity {
  @ApiProperty({ type: OrderCustomerEntity }) customer!: OrderCustomerEntity;
}

export class CustomerOrderPageEntity {
  @ApiProperty({ type: CustomerOrderEntity, isArray: true })
  items!: CustomerOrderEntity[];
  @ApiProperty() page!: number;
  @ApiProperty() limit!: number;
  @ApiProperty({ description: 'All matching orders, across pages.' })
  total!: number;
}

export class OwnerOrderPageEntity {
  @ApiProperty({ type: OwnerOrderEntity, isArray: true })
  items!: OwnerOrderEntity[];
  @ApiProperty() page!: number;
  @ApiProperty() limit!: number;
  @ApiProperty({ description: 'All matching orders, across pages.' })
  total!: number;
}

export class CustomerOrderTransitionEntity {
  @ApiProperty({
    description:
      '`false` when the order was already in the requested status: nothing was done.',
  })
  changed!: boolean;
  @ApiProperty({ type: CustomerOrderEntity }) order!: CustomerOrderEntity;
}

export class OwnerOrderTransitionEntity {
  @ApiProperty({
    description:
      '`false` when the order was already in the requested status: nothing was done (a removal list sent to a confirm is then ignored).',
  })
  changed!: boolean;
  @ApiProperty({ type: OwnerOrderEntity }) order!: OwnerOrderEntity;
}

/** The body of every business error: stable `code` plus the details that apply. */
export class OrderErrorEntity {
  @ApiProperty() statusCode!: number;
  @ApiProperty() error!: string;
  @ApiProperty({
    example: 'ORDER_STATE_CHANGED',
    description:
      'STORE_CLOSED, PRODUCT_UNAVAILABLE, INSUFFICIENT_STOCK, INVALID_QUANTITY, INVALID_PICKUP_TIME, IDEMPOTENCY_KEY_REUSED or ORDER_STATE_CHANGED.',
  })
  code!: string;
  @ApiProperty() message!: string;
  @ApiProperty({
    required: false,
    enum: OrderStatus,
    description: 'ORDER_STATE_CHANGED: where the order is now.',
  })
  currentStatus?: OrderStatus;
  @ApiProperty({
    required: false,
    enum: OrderStatus,
    description: 'ORDER_STATE_CHANGED: the status that was asked for.',
  })
  requestedStatus?: OrderStatus;
  @ApiProperty({
    required: false,
    description: 'INSUFFICIENT_STOCK: the offending line. Never a quantity.',
  })
  storeProductId?: number;
  @ApiProperty({
    required: false,
    type: 'array',
    items: { type: 'object' },
    description:
      'PRODUCT_UNAVAILABLE: `{ storeProductId, reason }`; INVALID_QUANTITY: `{ storeProductId, errors }`.',
  })
  lines?: object[];
}
