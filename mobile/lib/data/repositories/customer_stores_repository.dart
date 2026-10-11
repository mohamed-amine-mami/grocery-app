import '../models/customer_product.dart';
import '../models/customer_store.dart';
import '../services/api_client.dart';

/// Talks to the backend's read-only customer endpoints: `GET /stores` and
/// `GET /stores/:id/products`. What it returns is for browsing; checkout
/// (`POST /orders`) revalidates everything.
class CustomerStoresRepository {
  CustomerStoresRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Every store, closed ones included, by name.
  Future<List<CustomerStore>> stores() async {
    final json = await _apiClient.get('/stores');
    return [
      for (final store in json as List<dynamic>)
        CustomerStore.fromJson(store as Map<String, dynamic>),
    ];
  }

  /// One store's catalogue, by category then name. Only that store's own
  /// offerings, with its own prices and rules.
  Future<List<CustomerProduct>> products(int storeId) async {
    final json = await _apiClient.get('/stores/$storeId/products');
    return [
      for (final product in json as List<dynamic>)
        CustomerProduct.fromJson(product as Map<String, dynamic>),
    ];
  }
}
