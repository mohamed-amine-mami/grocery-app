import '../models/store.dart';
import '../services/api_client.dart';

/// Talks to the backend's `/owner/store` endpoints. The owner is identified
/// by the bearer token alone — no owner id is ever sent.
class StoreRepository {
  StoreRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The authenticated owner's store, or `null` when they haven't created one
  /// yet (the backend answers `404` in that case).
  Future<Store?> getMine() async {
    try {
      final json = await _apiClient.get('/owner/store');
      return Store.fromJson(json as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<Store> create({
    required String name,
    required String address,
    String? description,
    String? photo,
    double? latitude,
    double? longitude,
  }) async {
    final json = await _apiClient.post(
      '/owner/store',
      body: {
        'name': name,
        'address': address,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (photo != null && photo.isNotEmpty) 'photo': photo,
        'latitude': ?latitude,
        'longitude': ?longitude,
      },
    );
    return Store.fromJson(json as Map<String, dynamic>);
  }

  /// Saves the store's editable details. Sends every field: an empty
  /// description/photo or a null coordinate pair clears it. Latitude and
  /// longitude must both be set or both be null.
  Future<Store> update({
    required String name,
    required String address,
    String? description,
    String? photo,
    double? latitude,
    double? longitude,
  }) async {
    final json = await _apiClient.patch(
      '/owner/store',
      body: {
        'name': name,
        'address': address,
        'description': _nullIfEmpty(description),
        'photo': _nullIfEmpty(photo),
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return Store.fromJson(json as Map<String, dynamic>);
  }

  /// The manual open/closed switch: whether the store accepts orders.
  Future<Store> setOpen({required bool isOpen}) async {
    final json = await _apiClient.patch(
      '/owner/store',
      body: {'isOpen': isOpen},
    );
    return Store.fromJson(json as Map<String, dynamic>);
  }

  static String? _nullIfEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
