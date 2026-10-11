import 'sale_unit.dart';

/// Mirrors the backend's `OrderStatus` (`backend/src/orders/order-status.enum.ts`).
/// There is no preparing, rejected or expired status.
enum OrderStatus {
  pending('PENDING'),
  confirmed('CONFIRMED'),
  readyForPickup('READY_FOR_PICKUP'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  noShow('NO_SHOW');

  const OrderStatus(this.apiValue);

  /// The value the API sends and accepts (`?status=PENDING`).
  final String apiValue;

  static OrderStatus fromJson(String value) => values.firstWhere(
    (status) => status.apiValue == value,
    orElse: () => throw FormatException('Unknown order status: $value'),
  );
}

/// Who caused a status change, as recorded by the backend.
enum OrderActorType {
  client,
  owner,
  system,
  channel;

  static OrderActorType fromJson(String value) => switch (value) {
    'CLIENT' => OrderActorType.client,
    'OWNER' => OrderActorType.owner,
    'SYSTEM' => OrderActorType.system,
    'CHANNEL' => OrderActorType.channel,
    _ => throw FormatException('Unknown order actor type: $value'),
  };
}

/// Parses a backend timestamp into a [DateTime] (UTC). The backend sends
/// PostgreSQL-style text such as `2026-10-04 14:48:02.454645+00`; it is parsed
/// into an instant, never compared as a string.
DateTime parseApiTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Invalid timestamp: $value');
  }
  return parsed.toUtc();
}

/// One line of an order. Name, unit and price are the snapshots taken when
/// the order was placed; a removed line keeps them and carries [removedAt].
class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.saleUnit,
    required this.quantity,
    required this.unitPriceMillimes,
    required this.lineTotalMillimes,
    this.removedAt,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'] as int,
    productName: json['productName'] as String,
    saleUnit: SaleUnit.fromJson(json['saleUnit'] as String),
    quantity: json['quantity'] as int,
    unitPriceMillimes: json['unitPriceMillimes'] as int,
    lineTotalMillimes: json['lineTotalMillimes'] as int,
    removedAt: json['removedAt'] == null
        ? null
        : parseApiTimestamp(json['removedAt'] as String),
  );

  final int id;
  final String productName;
  final SaleUnit saleUnit;

  /// In base units: pieces / grams / millilitres.
  final int quantity;

  /// Price of one sale unit when ordered, in millimes.
  final int unitPriceMillimes;
  final int lineTotalMillimes;

  /// Set when the store removed the line while confirming.
  final DateTime? removedAt;

  bool get isRemoved => removedAt != null;
}

/// One entry of an order's status history.
class OrderEvent {
  const OrderEvent({
    required this.toStatus,
    required this.actorType,
    required this.createdAt,
    this.fromStatus,
    this.reason,
  });

  factory OrderEvent.fromJson(Map<String, dynamic> json) => OrderEvent(
    fromStatus: json['fromStatus'] == null
        ? null
        : OrderStatus.fromJson(json['fromStatus'] as String),
    toStatus: OrderStatus.fromJson(json['toStatus'] as String),
    actorType: OrderActorType.fromJson(json['actorType'] as String),
    reason: json['reason'] as String?,
    createdAt: parseApiTimestamp(json['createdAt'] as String),
  );

  /// `null` for the creation event.
  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final OrderActorType actorType;
  final String? reason;
  final DateTime createdAt;
}

/// An order as the owner sees it (`/owner/orders`): the customer's name and
/// phone, the lines, the server's total, and the status history.
class Order {
  const Order({
    required this.id,
    required this.code,
    required this.status,
    required this.requestedPickupAt,
    required this.totalMillimes,
    required this.storeAdjusted,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.events,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>;
    return Order(
      id: json['id'] as int,
      code: json['code'] as String,
      status: OrderStatus.fromJson(json['status'] as String),
      requestedPickupAt: parseApiTimestamp(json['requestedPickupAt'] as String),
      totalMillimes: json['totalMillimes'] as int,
      storeAdjusted: json['storeAdjusted'] as bool,
      customerName: customer['name'] as String,
      customerPhone: customer['phoneNumber'] as String,
      items: [
        for (final item in json['items'] as List<dynamic>)
          OrderItem.fromJson(item as Map<String, dynamic>),
      ],
      events: [
        for (final event in json['events'] as List<dynamic>)
          OrderEvent.fromJson(event as Map<String, dynamic>),
      ],
      createdAt: parseApiTimestamp(json['createdAt'] as String),
      updatedAt: parseApiTimestamp(json['updatedAt'] as String),
    );
  }

  final int id;

  /// The reference the customer shows at pickup.
  final String code;
  final OrderStatus status;

  /// Advisory time, not a reserved slot.
  final DateTime requestedPickupAt;

  /// The server's total of the lines that are not removed, in millimes.
  final int totalMillimes;
  final bool storeAdjusted;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final List<OrderEvent> events;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<OrderItem> get activeItems => [
    for (final item in items)
      if (!item.isRemoved) item,
  ];

  List<OrderItem> get removedItems => [
    for (final item in items)
      if (item.isRemoved) item,
  ];
}

/// One page of the owner's order list, newest first.
class OrderPage {
  const OrderPage({
    required this.orders,
    required this.page,
    required this.limit,
    required this.total,
  });

  factory OrderPage.fromJson(Map<String, dynamic> json) => OrderPage(
    orders: [
      for (final order in json['items'] as List<dynamic>)
        Order.fromJson(order as Map<String, dynamic>),
    ],
    page: json['page'] as int,
    limit: json['limit'] as int,
    total: json['total'] as int,
  );

  final List<Order> orders;
  final int page;
  final int limit;

  /// All orders matching the request, across pages.
  final int total;
}

/// The outcome of a transition request. [changed] is `false` when the order
/// was already in the requested status and nothing was done.
class OrderTransition {
  const OrderTransition({required this.changed, required this.order});

  factory OrderTransition.fromJson(Map<String, dynamic> json) =>
      OrderTransition(
        changed: json['changed'] as bool,
        order: Order.fromJson(json['order'] as Map<String, dynamic>),
      );

  final bool changed;
  final Order order;
}
