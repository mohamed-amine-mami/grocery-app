import '../models/store.dart';
import '../services/api_client.dart';
import '../services/image_picker_service.dart';

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
        'latitude': ?latitude,
        'longitude': ?longitude,
      },
    );
    return Store.fromJson(json as Map<String, dynamic>);
  }

  /// Saves the store's editable details. Sends every field: an empty
  /// description or a null coordinate pair clears it. The photo is not part of
  /// it: it has its own endpoints ([setPhoto], [removePhoto]). Latitude and
  /// longitude must both be set or both be null.
  Future<Store> update({
    required String name,
    required String address,
    String? description,
    double? latitude,
    double? longitude,
  }) async {
    final json = await _apiClient.patch(
      '/owner/store',
      body: {
        'name': name,
        'address': address,
        'description': _nullIfEmpty(description),
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

  /// Sets or replaces the owner's store photo. Returns the store as the
  /// backend now has it; its `photo` is the only thing to display.
  Future<Store> setPhoto(PickedImage image) async {
    final json = await _apiClient.putMultipart(
      '/owner/store/photo',
      field: 'file',
      bytes: image.bytes,
      filename: image.filename,
      contentType: image.contentType,
    );
    return Store.fromJson(json as Map<String, dynamic>);
  }

  /// Removes the store photo (also fine when there is none).
  Future<Store> removePhoto() async {
    final json = await _apiClient.delete('/owner/store/photo');
    return Store.fromJson(json as Map<String, dynamic>);
  }

  static String? _nullIfEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
