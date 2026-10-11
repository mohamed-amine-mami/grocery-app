import 'dart:convert';

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Thrown when the backend responds with a non-2xx status code.
///
/// Carries the raw [statusCode] and, when present, the backend's own
/// `message`, its machine-readable [code] (e.g. `STOCK_CHANGED`) and the whole
/// error [body]. Callers (view models) decide how to translate this into a
/// French, user-facing message — this layer never invents wording.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    this.message,
    this.code,
    this.body,
  });

  final int statusCode;
  final String? message;

  /// The backend's stable error code, when the response carries one.
  final String? code;

  /// The decoded error response, for the few errors that carry data
  /// (`STOCK_CHANGED` says what the stock is now).
  final Map<String, dynamic>? body;

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
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    this.uploadTimeout = defaultUploadTimeout,
  }) : _httpClient = httpClient ?? http.Client(),
       baseUrl = baseUrl ?? defaultBaseUrl;

  /// The backend has no path prefix — routes live at the root
  /// (`/auth/login`, `/stores`, ...); only Swagger's own UI is under `/api`.
  static const defaultBaseUrl = 'http://localhost:3000';

  /// How long a file upload may take, request and response together.
  static const defaultUploadTimeout = Duration(seconds: 30);

  final http.Client _httpClient;
  final String baseUrl;
  final Duration uploadTimeout;

  String? _authToken;

  /// Set once after a successful login/registration, cleared on logout.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  Map<String, String> get _authHeaders => {
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    ..._authHeaders,
  };

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// `PUT` with one file as `multipart/form-data` — what the photo endpoints
  /// take. Sends the same bearer token, answers with the same decoded JSON,
  /// and fails the same way ([ApiException] / [NetworkException]); a request
  /// still running after [uploadTimeout] is a [NetworkException].
  Future<dynamic> putMultipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final request = http.MultipartRequest('PUT', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_authHeaders)
      ..files.add(
        http.MultipartFile.fromBytes(
          field,
          bytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );

    http.Response response;
    try {
      response = await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(uploadTimeout);
    } catch (error) {
      throw NetworkException(error);
    }
    return _decode(response);
  }

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

    return _decode(response);
  }

  /// The success body decoded, or the failure as an [ApiException].
  dynamic _decode(http.Response response) {
    final dynamic decoded = response.body.isEmpty
        ? null
        : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: _extractMessage(decoded),
      code: decoded is Map<String, dynamic> && decoded['code'] is String
          ? decoded['code'] as String
          : null,
      body: decoded is Map<String, dynamic> ? decoded : null,
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
