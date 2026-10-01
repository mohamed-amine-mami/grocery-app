import 'user.dart';

/// The payload returned by `POST /auth/login` and `POST /auth/register`.
class AuthResponse {
  const AuthResponse({required this.accessToken, required this.user});

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String accessToken;
  final User user;
}
