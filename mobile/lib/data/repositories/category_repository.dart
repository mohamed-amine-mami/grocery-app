import '../models/store_category.dart';
import '../services/api_client.dart';

/// Talks to the backend's `/owner/categories` endpoints. The store is
/// resolved by the backend from the bearer token — no store id is sent.
class CategoryRepository {
  CategoryRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Sorted by name by the backend.
  Future<List<StoreCategory>> list() async {
    final json = await _apiClient.get('/owner/categories');
    return (json as List<dynamic>)
        .map((item) => StoreCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<StoreCategory> create(String name) async {
    final json = await _apiClient.post(
      '/owner/categories',
      body: {'name': name},
    );
    return StoreCategory.fromJson(json as Map<String, dynamic>);
  }

  Future<StoreCategory> rename(int id, String name) async {
    final json = await _apiClient.patch(
      '/owner/categories/$id',
      body: {'name': name},
    );
    return StoreCategory.fromJson(json as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _apiClient.delete('/owner/categories/$id');
}
