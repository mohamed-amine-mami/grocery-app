import 'order.dart';

/// An order as its customer sees it (`/orders`): the store it is at, the
/// lines with the prices they were ordered at, the server's total, and the
/// status history. The server's response is the only source of every value.
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.code,
    required this.status,
    required this.requestedPickupAt,
    required this.totalMillimes,
    required this.storeAdjusted,
    required this.storeName,
    required this.storeAddress,
    required this.items,
    required this.events,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerOrder.fromJson(Map<String, dynamic> json) {
    final store = json['store'] as Map<String, dynamic>;
    return CustomerOrder(
      id: json['id'] as int,
      code: json['code'] as String,
      status: OrderStatus.fromJson(json['status'] as String),
      requestedPickupAt: parseApiTimestamp(json['requestedPickupAt'] as String),
      totalMillimes: json['totalMillimes'] as int,
      storeAdjusted: json['storeAdjusted'] as bool,
      storeName: store['name'] as String,
      storeAddress: store['address'] as String,
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

  /// The store removed at least one line while confirming.
  final bool storeAdjusted;
  final String storeName;
  final String storeAddress;
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

  /// Nothing more will happen to the order.
  bool get isFinished =>
      status == OrderStatus.completed ||
      status == OrderStatus.cancelled ||
      status == OrderStatus.noShow;

  /// The status the customer may cancel from. Display only: the backend
  /// decides.
  bool get canCancel =>
      status == OrderStatus.pending || status == OrderStatus.confirmed;
}

/// One page of the customer's orders, newest first.
class CustomerOrderPage {
  const CustomerOrderPage({
    required this.orders,
    required this.page,
    required this.limit,
    required this.total,
  });

  factory CustomerOrderPage.fromJson(Map<String, dynamic> json) =>
      CustomerOrderPage(
        orders: [
          for (final order in json['items'] as List<dynamic>)
            CustomerOrder.fromJson(order as Map<String, dynamic>),
        ],
        page: json['page'] as int,
        limit: json['limit'] as int,
        total: json['total'] as int,
      );

  final List<CustomerOrder> orders;
  final int page;
  final int limit;
  final int total;
}

/// The outcome of a cancellation. [changed] is `false` when the order was
/// already cancelled and nothing was done.
class CustomerOrderTransition {
  const CustomerOrderTransition({required this.changed, required this.order});

  factory CustomerOrderTransition.fromJson(Map<String, dynamic> json) =>
      CustomerOrderTransition(
        changed: json['changed'] as bool,
        order: CustomerOrder.fromJson(json['order'] as Map<String, dynamic>),
      );

  final bool changed;
  final CustomerOrder order;
}

/// What the customer sends to place an order: the store, the lines, the
/// pickup time and the idempotency key — and nothing else. Prices, totals,
/// names, units, stock and status are the server's.
class NewOrderRequest {
  const NewOrderRequest({
    required this.storeId,
    required this.lines,
    required this.requestedPickupAt,
    required this.idempotencyKey,
  });

  final int storeId;
  final List<NewOrderLine> lines;
  final DateTime requestedPickupAt;
  final String idempotencyKey;

  Map<String, dynamic> toJson() => {
    'storeId': storeId,
    'lines': [for (final line in lines) line.toJson()],
    'requestedPickupAt': requestedPickupAt.toUtc().toIso8601String(),
    'idempotencyKey': idempotencyKey,
  };
}

class NewOrderLine {
  const NewOrderLine({required this.storeProductId, required this.quantity});

  final int storeProductId;

  /// In base units.
  final int quantity;

  Map<String, dynamic> toJson() => {
    'storeProductId': storeProductId,
    'quantity': quantity,
  };
}
