import '../models/catalog_category.dart';
import '../models/catalog_product.dart';
import '../services/api_client.dart';

/// Talks to the backend's read-only `/owner/catalog` endpoints: the global
/// catalog an owner browses to choose what their store sells. Nothing here
/// can change the catalog — only the backend's importer does.
class CatalogRepository {
  CatalogRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Active catalog categories, sorted by name by the backend.
  Future<List<CatalogCategory>> categories() async {
    final json = await _apiClient.get('/owner/catalog/categories');
    return (json as List<dynamic>)
        .map((item) => CatalogCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Active catalog products for the picker, sorted by name by the backend,
  /// each flagged with whether the owner's store already sells it. The store
  /// is resolved from the bearer token. The whole catalog is returned, so the
  /// app can search it locally.
  Future<List<CatalogItem>> products({int? categoryId}) async {
    final query = categoryId == null ? '' : '?categoryId=$categoryId';
    final json = await _apiClient.get('/owner/catalog/products$query');
    return (json as List<dynamic>)
        .map((item) => CatalogItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
