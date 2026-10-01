import '../models/auth_response.dart';
import '../models/user.dart';
import '../services/api_client.dart';

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
    String? photo,
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
        if (photo != null && photo.isNotEmpty) 'photo': photo,
        'role': role.toJson(),
      },
    );
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<User> me() async {
    final json = await _apiClient.get('/auth/me');
    return User.fromJson(json as Map<String, dynamic>);
  }
}
