import '../models/customer_order.dart';
import '../services/api_client.dart';
import 'orders_repository.dart';

/// Talks to the backend's `/orders` endpoints: the signed-in customer's own
/// orders. The customer comes from the bearer token; errors (409
/// `STORE_CLOSED`, `ORDER_STATE_CHANGED`, …) come back as an [ApiException]
/// for the caller to translate.
class CustomerOrdersRepository {
  CustomerOrdersRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Places an order. The backend answers 201 for a new order and 200 with the
  /// original order when [NewOrderRequest.idempotencyKey] was already used for
  /// the same request — both are the created order.
  Future<CustomerOrder> create(NewOrderRequest request) async {
    final json = await _apiClient.post('/orders', body: request.toJson());
    return CustomerOrder.fromJson(json as Map<String, dynamic>);
  }

  /// One page of the customer's orders, newest first.
  Future<CustomerOrderPage> list({int page = 1, int limit = 20}) async {
    assert(
      limit >= 1 && limit <= OrdersRepository.maxPageSize,
      'limit must be 1–${OrdersRepository.maxPageSize}',
    );
    final json = await _apiClient.get('/orders?page=$page&limit=$limit');
    return CustomerOrderPage.fromJson(json as Map<String, dynamic>);
  }

  Future<CustomerOrder> get(int id) async {
    final json = await _apiClient.get('/orders/$id');
    return CustomerOrder.fromJson(json as Map<String, dynamic>);
  }

  /// Cancels a `PENDING` or `CONFIRMED` order.
  Future<CustomerOrderTransition> cancel(int id) async {
    final json = await _apiClient.post(
      '/orders/$id/cancel',
      body: const <String, dynamic>{},
    );
    return CustomerOrderTransition.fromJson(json as Map<String, dynamic>);
  }
}
