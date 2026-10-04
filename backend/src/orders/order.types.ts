import type { SaleUnit } from '../products/sale-unit.enum.js';
import type { UnavailabilityReason } from '../products/product-rules.js';
import type { OrderStatus } from './order-status.enum.js';

/** One requested line: a store product and a quantity in base units (pieces / g / mL). */
export interface OrderLineInput {
  storeProductId: number;
  quantity: number;
}

/**
 * Everything needed to place an order, as plain values: no HTTP request, no
 * JWT, no channel. The app's controller and, later, WhatsApp/n8n all build this.
 * The client never sends prices or totals.
 */
export interface CreateOrderCommand {
  customerId: number;
  storeId: number;
  lines: OrderLineInput[];
  requestedPickupAt: Date;
  /** Chosen by the caller for one attempt; a retry of that attempt reuses it. */
  idempotencyKey: string;
}

export interface OrderItemRecord {
  id: number;
  orderId: number;
  storeProductId: number;
  productNameSnapshot: string;
  saleUnitSnapshot: SaleUnit;
  unitPriceMillimes: number;
  quantity: number;
  lineTotalMillimes: number;
  stockDecrementedQuantity: number;
  removedAt: string | null;
  createdAt: string;
}

export interface OrderRecord {
  id: number;
  code: string;
  customerId: number;
  storeId: number;
  status: OrderStatus;
  requestedPickupAt: string;
  totalMillimes: number;
  idempotencyKey: string;
  createdAt: string;
  updatedAt: string;
  items: OrderItemRecord[];
}

export interface CreateOrderResult {
  order: OrderRecord;
  /** `false` when the idempotency key had already created this order. */
  created: boolean;
}

/** A line that cannot be ordered, with why. Customers are never told stock quantities. */
export interface UnavailableLine {
  storeProductId: number;
  reason: UnavailabilityReason;
}

export interface InvalidQuantityLine {
  storeProductId: number;
  errors: string[];
}
