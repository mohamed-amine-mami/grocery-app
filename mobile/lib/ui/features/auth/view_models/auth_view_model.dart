import 'package:flutter/foundation.dart';

import '../../../../data/models/auth_response.dart';
import '../../../../data/models/user.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../../data/services/token_storage.dart';

enum AuthStatus {
  /// Still checking whether a stored token exists and is valid.
  unknown,
  authenticated,
  unauthenticated,

  /// A token is stored but the backend could not be asked about it (offline,
  /// server error). The session is kept — being offline is not being logged
  /// out — and the app offers a retry.
  unreachable,
}

/// Holds the app's authentication session: the current user, the JWT
/// (persisted via [TokenStorage] and attached to requests via [ApiClient]),
/// and the login/register operations screens call into.
class AuthViewModel extends ChangeNotifier {
  AuthViewModel({
    required this._authRepository,
    required this._tokenStorage,
    required this._apiClient,
  });

  final AuthRepository _authRepository;
  final TokenStorage _tokenStorage;
  final ApiClient _apiClient;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  User? _currentUser;
  User? get currentUser => _currentUser;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  /// Call at app startup (and to retry after [AuthStatus.unreachable]):
  /// restores the session from the stored token, validated against
  /// `GET /auth/me`.
  ///
  /// Only a token the backend *rejects* (401, or 404 for a deleted user) is
  /// discarded. Network and server failures keep it.
  Future<void> bootstrap() async {
    if (_status != AuthStatus.unknown) {
      _status = AuthStatus.unknown;
      notifyListeners();
    }

    final token = await _tokenStorage.readToken();
    if (token == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _apiClient.setAuthToken(token);
    try {
      _currentUser = await _authRepository.me();
      _status = AuthStatus.authenticated;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 404) {
        await _discardSession();
      } else {
        _status = AuthStatus.unreachable;
      }
    } on NetworkException catch (_) {
      _status = AuthStatus.unreachable;
    } catch (_) {
      // e.g. an unexpected response body — treat it like an unreachable
      // backend rather than destroying a possibly valid session.
      _status = AuthStatus.unreachable;
    }
    notifyListeners();
  }

  Future<void> _discardSession() async {
    await _tokenStorage.clearToken();
    _apiClient.setAuthToken(null);
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
  }

  /// Returns a French error message on failure, or `null` on success.
  Future<String?> login({
    required String phoneNumber,
    required String password,
  }) async {
    return _runAuthOperation(
      () => _authRepository.login(phoneNumber: phoneNumber, password: password),
      onApiError: (error) => error.statusCode == 401
          ? 'Numéro de téléphone ou mot de passe incorrect.'
          : 'Une erreur est survenue. Veuillez réessayer.',
    );
  }

  /// Returns a French error message on failure, or `null` on success.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required UserRole role,
    String? whatsappNumber,
    String? photo,
  }) async {
    return _runAuthOperation(
      () => _authRepository.register(
        name: name,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
        role: role,
        whatsappNumber: whatsappNumber,
        photo: photo,
      ),
      onApiError: (error) => error.statusCode == 409
          ? 'Un compte existe déjà avec cet e-mail ou ce numéro de téléphone.'
          : 'Impossible de créer le compte. Vérifiez les informations saisies.',
    );
  }

  Future<void> logout() async {
    await _tokenStorage.clearToken();
    _apiClient.setAuthToken(null);
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<String?> _runAuthOperation(
    Future<AuthResponse> Function() operation, {
    required String Function(ApiException) onApiError,
  }) async {
    _isBusy = true;
    notifyListeners();
    try {
      final response = await operation();
      await _tokenStorage.saveToken(response.accessToken);
      _apiClient.setAuthToken(response.accessToken);
      _currentUser = response.user;
      _status = AuthStatus.authenticated;
      return null;
    } on ApiException catch (error) {
      return onApiError(error);
    } on NetworkException catch (_) {
      return 'Impossible de contacter le serveur. Vérifiez votre connexion.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
