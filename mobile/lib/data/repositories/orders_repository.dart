import '../models/order.dart';
import '../services/api_client.dart';

/// Talks to the backend's `/owner/orders` endpoints. The store is resolved by
/// the backend from the bearer token — no store id is sent — and every rule
/// (which transitions exist, stock, totals) stays in the backend: errors such
/// as 409 `ORDER_STATE_CHANGED` come back as an [ApiException] for the caller
/// to translate.
class OrdersRepository {
  OrdersRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The backend's largest page.
  static const maxPageSize = 50;

  /// One page of the store's orders, newest first, optionally of one status.
  Future<OrderPage> list({
    OrderStatus? status,
    int page = 1,
    int limit = 20,
  }) async {
    assert(limit >= 1 && limit <= maxPageSize, 'limit must be 1–$maxPageSize');
    final query = [
      'page=$page',
      'limit=$limit',
      if (status != null) 'status=${status.apiValue}',
    ].join('&');
    final json = await _apiClient.get('/owner/orders?$query');
    return OrderPage.fromJson(json as Map<String, dynamic>);
  }

  Future<Order> get(int id) async {
    final json = await _apiClient.get('/owner/orders/$id');
    return Order.fromJson(json as Map<String, dynamic>);
  }

  /// `PENDING → CONFIRMED`, optionally removing lines the store cannot
  /// fulfil. Only item ids are sent; the backend recomputes everything else.
  Future<OrderTransition> confirm(
    int id, {
    List<int> removeItemIds = const [],
  }) => _transition(
    id,
    'confirm',
    body: removeItemIds.isEmpty ? null : {'removeItemIds': removeItemIds},
  );

  /// `CONFIRMED → READY_FOR_PICKUP`.
  Future<OrderTransition> markReady(int id) => _transition(id, 'ready');

  /// `READY_FOR_PICKUP → COMPLETED` (handed over and paid).
  Future<OrderTransition> complete(int id) => _transition(id, 'complete');

  /// Cancels a `PENDING` or `CONFIRMED` order. The customer reads [reason].
  Future<OrderTransition> cancel(int id, {required String reason}) =>
      _transition(id, 'cancel', body: {'reason': reason});

  /// `READY_FOR_PICKUP → NO_SHOW`.
  Future<OrderTransition> markNoShow(int id) => _transition(id, 'no-show');

  Future<OrderTransition> _transition(
    int id,
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final json = await _apiClient.post(
      '/owner/orders/$id/$action',
      body: body ?? const {},
    );
    return OrderTransition.fromJson(json as Map<String, dynamic>);
  }
}
