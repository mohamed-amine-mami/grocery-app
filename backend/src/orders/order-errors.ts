import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import type { InvalidQuantityLine, UnavailableLine } from './order.types.js';

/**
 * Stable error `code`s for order creation (`docs/orders.md`). They are plain
 * Nest exceptions, so a controller needs no translation; line-level errors name
 * the offending store products and never reveal a stock quantity.
 */
export const OrderErrorCode = {
  STORE_CLOSED: 'STORE_CLOSED',
  PRODUCT_UNAVAILABLE: 'PRODUCT_UNAVAILABLE',
  INSUFFICIENT_STOCK: 'INSUFFICIENT_STOCK',
  INVALID_QUANTITY: 'INVALID_QUANTITY',
  INVALID_PICKUP_TIME: 'INVALID_PICKUP_TIME',
  IDEMPOTENCY_KEY_REUSED: 'IDEMPOTENCY_KEY_REUSED',
} as const;

export const storeClosed = () =>
  new ConflictException({
    statusCode: 409,
    error: 'Conflict',
    code: OrderErrorCode.STORE_CLOSED,
    message: 'This store is not accepting orders right now',
  });

export const productUnavailable = (lines: UnavailableLine[]) =>
  new ConflictException({
    statusCode: 409,
    error: 'Conflict',
    code: OrderErrorCode.PRODUCT_UNAVAILABLE,
    message: 'Some products cannot be ordered right now',
    lines,
  });

export const insufficientStock = (storeProductId: number) =>
  new ConflictException({
    statusCode: 409,
    error: 'Conflict',
    code: OrderErrorCode.INSUFFICIENT_STOCK,
    message: 'There is not enough stock for this product',
    storeProductId,
  });

export const invalidQuantity = (lines: InvalidQuantityLine[]) =>
  new BadRequestException({
    statusCode: 400,
    error: 'Bad Request',
    code: OrderErrorCode.INVALID_QUANTITY,
    message: 'Some quantities are not allowed for these products',
    lines,
  });

export const invalidPickupTime = (message: string) =>
  new BadRequestException({
    statusCode: 400,
    error: 'Bad Request',
    code: OrderErrorCode.INVALID_PICKUP_TIME,
    message,
  });

/** The same key was already used for a different order (see `OrdersService`). */
export const idempotencyKeyReused = () =>
  new ConflictException({
    statusCode: 409,
    error: 'Conflict',
    code: OrderErrorCode.IDEMPOTENCY_KEY_REUSED,
    message: 'This idempotency key was already used for a different order',
  });

/** Lines naming store products that are not in the requested store. */
export const storeProductsNotFound = (storeProductIds: number[]) =>
  new NotFoundException({
    statusCode: 404,
    error: 'Not Found',
    message: 'Some products are not sold by this store',
    storeProductIds,
  });

export const duplicateLines = (storeProductIds: number[]) =>
  new BadRequestException({
    statusCode: 400,
    error: 'Bad Request',
    message: 'Each product may appear in only one line',
    storeProductIds,
  });
