import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:grocery_mobile/data/services/api_client.dart';

/// A request the backend would have received.
class SentRequest {
  SentRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Object? body;

  String get path => url.path;
  String get pathAndQuery =>
      url.hasQuery ? '${url.path}?${url.query}' : url.path;
}

/// An [ApiClient] wired to a mock HTTP client, so the repositories are tested
/// against real request/response handling without a network.
///
/// [respond] decides the response for each request; every request is recorded
/// in [requests].
class MockedApi {
  MockedApi(http.Response Function(SentRequest request) respond) {
    client = ApiClient(
      baseUrl: 'http://backend.test',
      httpClient: MockClient((request) async {
        final sent = SentRequest(
          request.method,
          request.url,
          request.headers,
          request.body.isEmpty ? null : jsonDecode(request.body),
        );
        requests.add(sent);
        return respond(sent);
      }),
    )..setAuthToken('owner-token');
  }

  /// Answers every request with [json] and [status].
  MockedApi.json(Object? json, {int status = 200})
    : this((_) => jsonResponse(json, status));

  /// Fails every request the way a dead connection does.
  MockedApi.offline() {
    client = ApiClient(
      baseUrl: 'http://backend.test',
      httpClient: MockClient((request) async {
        requests.add(
          SentRequest(request.method, request.url, request.headers, null),
        );
        throw http.ClientException('connection refused');
      }),
    );
  }

  late final ApiClient client;
  final requests = <SentRequest>[];

  SentRequest get single => requests.single;
}

http.Response jsonResponse(Object? json, [int status = 200]) => http.Response(
  json == null ? '' : jsonEncode(json),
  status,
  headers: {'content-type': 'application/json'},
);
