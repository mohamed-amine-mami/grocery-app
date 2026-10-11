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

  /// One page of the active catalog, searched (`query`) and filtered
  /// (`categoryId`) by the backend, in a stable order. Pass the previous
  /// page's [CatalogPage.nextCursor] as [cursor] to continue. Each product is
  /// flagged with whether the owner's store already sells it.
  Future<CatalogPage> browse({
    String? query,
    int? categoryId,
    String? cursor,
    int? limit,
  }) async {
    final parameters = <String, String>{
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (categoryId != null) 'categoryId': '$categoryId',
      'cursor': ?cursor,
      if (limit != null) 'limit': '$limit',
    };
    final queryString = parameters.isEmpty
        ? ''
        : '?${Uri(queryParameters: parameters).query}';
    final json = await _apiClient.get('/owner/catalog/browse$queryString');
    return CatalogPage.fromJson(json as Map<String, dynamic>);
  }

  /// One catalog product with the store's flags, or `null` when the catalog no
  /// longer has it (unknown or archived).
  Future<CatalogItem?> product(int productId) async {
    try {
      final json = await _apiClient.get('/owner/catalog/products/$productId');
      return CatalogItem.fromJson(json as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// Every active catalog product in one response, sorted by name. Kept for
  /// the whole-catalog `GET /owner/catalog/products`; the picker pages through
  /// [browse] instead, because the full list does not scale.
  Future<List<CatalogItem>> products({int? categoryId}) async {
    final query = categoryId == null ? '' : '?categoryId=$categoryId';
    final json = await _apiClient.get('/owner/catalog/products$query');
    return (json as List<dynamic>)
        .map((item) => CatalogItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
