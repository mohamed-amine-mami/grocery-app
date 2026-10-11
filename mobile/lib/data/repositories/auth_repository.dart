import '../models/auth_response.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/image_picker_service.dart';

/// Talks to the backend's `/auth/*` endpoints. Returns typed models only —
/// no UI concerns (French copy, loading state) live here.
class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthResponse> login({
    required String phoneNumber,
    required String password,
  }) async {
    final json = await _apiClient.post(
      '/auth/login',
      body: {'phoneNumber': phoneNumber, 'password': password},
    );
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required UserRole role,
    String? whatsappNumber,
  }) async {
    final json = await _apiClient.post(
      '/auth/register',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'phoneNumber': phoneNumber,
        if (whatsappNumber != null && whatsappNumber.isNotEmpty)
          'whatsappNumber': whatsappNumber,
        'role': role.toJson(),
      },
    );
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<User> me() async {
    final json = await _apiClient.get('/auth/me');
    return User.fromJson(json as Map<String, dynamic>);
  }

  /// Sets or replaces the signed-in user's own photo. Returns the user as the
  /// backend now has it; its `photo` is the only thing to display.
  Future<User> setPhoto(PickedImage image) async {
    final json = await _apiClient.putMultipart(
      '/users/me/photo',
      field: 'file',
      bytes: image.bytes,
      filename: image.filename,
      contentType: image.contentType,
    );
    return User.fromJson(json as Map<String, dynamic>);
  }

  /// Removes the signed-in user's photo (also fine when there is none).
  Future<User> removePhoto() async {
    final json = await _apiClient.delete('/users/me/photo');
    return User.fromJson(json as Map<String, dynamic>);
  }
}
