import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the backend responds with a non-2xx status code.
///
/// Carries the raw [statusCode] and, when present, the backend's own
/// `message`. Callers (view models) decide how to translate this into a
/// French, user-facing message — this layer never invents wording.
class ApiException implements Exception {
  const ApiException({required this.statusCode, this.message});

  final int statusCode;
  final String? message;

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}

/// Thrown when the request never reached the backend (no connectivity,
/// DNS failure, connection refused, timeout, ...).
class NetworkException implements Exception {
  const NetworkException(this.cause);

  final Object cause;

  @override
  String toString() => 'NetworkException($cause)';
}

/// Thin HTTP client wrapper: builds requests against the backend's base URL,
/// attaches the bearer token when one is set, and turns non-2xx responses
/// into [ApiException].
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? http.Client(),
      baseUrl = baseUrl ?? defaultBaseUrl;

  /// The backend has no path prefix — routes live at the root
  /// (`/auth/login`, `/stores`, ...); only Swagger's own UI is under `/api`.
  static const defaultBaseUrl = 'http://localhost:3000';

  final http.Client _httpClient;
  final String baseUrl;

  String? _authToken;

  /// Set once after a successful login/registration, cleared on logout.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final encodedBody = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      response = switch (method) {
        'GET' => await _httpClient.get(uri, headers: _headers),
        'POST' => await _httpClient.post(
          uri,
          headers: _headers,
          body: encodedBody,
        ),
        'PATCH' => await _httpClient.patch(
          uri,
          headers: _headers,
          body: encodedBody,
        ),
        'DELETE' => await _httpClient.delete(uri, headers: _headers),
        _ => throw UnsupportedError('Unsupported HTTP method: $method'),
      };
    } on UnsupportedError {
      rethrow;
    } catch (error) {
      throw NetworkException(error);
    }

    final dynamic decoded = response.body.isEmpty
        ? null
        : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: _extractMessage(decoded),
    );
  }

  String? _extractMessage(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final message = decoded['message'];
    if (message is String) {
      return message;
    }
    if (message is List && message.isNotEmpty) {
      return message.first.toString();
    }
    return null;
  }
}
