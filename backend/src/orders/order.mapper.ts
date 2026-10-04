import type { OrderView } from './order-queries.service.js';
import type {
  CustomerOrderEntity,
  OrderEventEntity,
  OrderItemEntity,
  OwnerOrderEntity,
} from './entities/order.entity.js';

/**
 * Domain order → response. Fields are copied one by one: nothing the client
 * should not see (stock accounting, the idempotency key, user ids) is picked up.
 */

function toBase({ order, events }: OrderView) {
  const items: OrderItemEntity[] = order.items.map((item) => ({
    id: item.id,
    storeProductId: item.storeProductId,
    productName: item.productNameSnapshot,
    saleUnit: item.saleUnitSnapshot,
    quantity: item.quantity,
    unitPriceMillimes: item.unitPriceMillimes,
    lineTotalMillimes: item.lineTotalMillimes,
    removedAt: item.removedAt,
  }));
  const history: OrderEventEntity[] = events.map((event) => ({
    fromStatus: event.fromStatus,
    toStatus: event.toStatus,
    actorType: event.actorType,
    reason: event.reason,
    createdAt: event.createdAt,
  }));
  return {
    id: order.id,
    code: order.code,
    status: order.status,
    requestedPickupAt: order.requestedPickupAt,
    totalMillimes: order.totalMillimes,
    storeAdjusted: items.some((item) => item.removedAt !== null),
    items,
    events: history,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
  };
}

export function toCustomerOrder(view: OrderView): CustomerOrderEntity {
  return {
    ...toBase(view),
    store: {
      id: view.store.id,
      name: view.store.name,
      address: view.store.address,
    },
  };
}

export function toOwnerOrder(view: OrderView): OwnerOrderEntity {
  return {
    ...toBase(view),
    customer: {
      name: view.customer.name,
      phoneNumber: view.customer.phoneNumber,
    },
  };
}
