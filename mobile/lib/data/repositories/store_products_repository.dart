import '../models/store_product.dart';
import '../services/api_client.dart';

/// Which of the store's products a listing returns.
enum StoreProductStatus {
  /// The normal catalogue: archived offerings are hidden.
  active,
  archived,
  all,
}

/// Thrown when a stock edit was refused because the stock changed since the
/// screen loaded it — an order was placed, or another device edited it.
/// Nothing from the request was applied.
class StockChangedException implements Exception {
  const StockChangedException({this.currentStockQuantity});

  /// The stock right now, in base units; `null` if tracking was switched off
  /// in the meantime.
  final int? currentStockQuantity;

  @override
  String toString() =>
      'StockChangedException(currentStockQuantity: $currentStockQuantity)';
}

/// Talks to the backend's `/owner/store-products` endpoints: the owner's
/// offerings of global catalog products. The store is resolved by the backend
/// from the bearer token — no store id is sent.
class StoreProductsRepository {
  StoreProductsRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The store's products, sorted by name by the backend. Active ones by
  /// default.
  Future<List<StoreProduct>> list({
    StoreProductStatus status = StoreProductStatus.active,
    int? categoryId,
  }) async {
    final query = [
      'status=${status.name}',
      if (categoryId != null) 'categoryId=$categoryId',
    ].join('&');
    final json = await _apiClient.get('/owner/store-products?$query');
    return (json as List<dynamic>)
        .map((item) => StoreProduct.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Active (non-archived) offerings only.
  Future<List<StoreProduct>> listActive() => list();

  /// One offering, archived or not.
  Future<StoreProduct> get(int id) async {
    final json = await _apiClient.get('/owner/store-products/$id');
    return StoreProduct.fromJson(json as Map<String, dynamic>);
  }

  /// Adds a catalog product to the store. Creation only: the backend answers
  /// `409` for a product the store already has, archived or not.
  Future<StoreProduct> create(NewStoreProduct input) async {
    final json = await _apiClient.post(
      '/owner/store-products',
      body: input.toJson(),
    );
    return StoreProduct.fromJson(json as Map<String, dynamic>);
  }

  /// Edits price, unit, quantity rules and stock. Throws
  /// [StockChangedException] when the stock changed since it was loaded.
  Future<StoreProduct> update(int id, StoreProductUpdate input) async {
    try {
      final json = await _apiClient.patch(
        '/owner/store-products/$id',
        body: input.toJson(),
      );
      return StoreProduct.fromJson(json as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.statusCode == 409 && error.code == 'STOCK_CHANGED') {
        throw StockChangedException(
          currentStockQuantity: error.body?['currentStockQuantity'] as int?,
        );
      }
      rethrow;
    }
  }

  /// The owner's manual on/off switch, independent of stock.
  Future<StoreProduct> setAvailability(
    int id, {
    required bool isAvailable,
  }) async {
    final json = await _apiClient.patch(
      '/owner/store-products/$id/availability',
      body: {'isAvailable': isAvailable},
    );
    return StoreProduct.fromJson(json as Map<String, dynamic>);
  }

  /// "Delete" from the owner's point of view: the backend archives the
  /// offering (hidden, kept for history).
  Future<void> archive(int id) =>
      _apiClient.delete('/owner/store-products/$id');

  /// Brings an archived offering back exactly as it was left.
  Future<StoreProduct> restore(int id) async {
    final json = await _apiClient.post('/owner/store-products/$id/restore');
    return StoreProduct.fromJson(json as Map<String, dynamic>);
  }
}
