import '../models/product.dart';
import '../services/api_client.dart';

/// Talks to the backend's `/owner/products` endpoints. The store is resolved
/// by the backend from the bearer token — no store id is sent.
class ProductRepository {
  ProductRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Active (non-archived) products, sorted by name by the backend.
  Future<List<Product>> listActive() async {
    final json = await _apiClient.get('/owner/products?status=active');
    return (json as List<dynamic>)
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Product> create(ProductInput input) async {
    final json = await _apiClient.post('/owner/products', body: input.toJson());
    return Product.fromJson(json as Map<String, dynamic>);
  }

  Future<Product> update(int id, ProductInput input) async {
    final json = await _apiClient.patch(
      '/owner/products/$id',
      body: input.toJson(),
    );
    return Product.fromJson(json as Map<String, dynamic>);
  }

  Future<Product> setAvailability(int id, {required bool isAvailable}) async {
    final json = await _apiClient.patch(
      '/owner/products/$id/availability',
      body: {'isAvailable': isAvailable},
    );
    return Product.fromJson(json as Map<String, dynamic>);
  }

  /// "Delete" from the owner's point of view: the backend archives the
  /// product (hidden from the catalog, kept for history).
  Future<void> archive(int id) => _apiClient.delete('/owner/products/$id');
}
