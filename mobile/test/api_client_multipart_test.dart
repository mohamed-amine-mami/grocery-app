import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:grocery_mobile/data/services/api_client.dart';

import 'api_test_support.dart';

/// What a multipart request carried, as the backend would read it.
class _Upload {
  _Upload(http.Request request)
    : method = request.method,
      url = request.url,
      headers = request.headers,
      body = latin1.decode(request.bodyBytes);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

ApiClient _client(
  http.Response Function(_Upload upload) respond, {
  List<_Upload>? seen,
  Duration? timeout,
  String? token = 'owner-token',
}) {
  final client = ApiClient(
    baseUrl: 'http://backend.test',
    uploadTimeout: timeout ?? ApiClient.defaultUploadTimeout,
    httpClient: MockClient((request) async {
      final upload = _Upload(request);
      seen?.add(upload);
      return respond(upload);
    }),
  );
  client.setAuthToken(token);
  return client;
}

Future<dynamic> _put(ApiClient client) => client.putMultipart(
  '/users/me/photo',
  field: 'file',
  bytes: [0xff, 0xd8, 0xff, 0x41, 0x42],
  filename: 'me.jpg',
  contentType: 'image/jpeg',
);

void main() {
  group('ApiClient.putMultipart', () {
    test('sends a PUT with the file as multipart/form-data', () async {
      final seen = <_Upload>[];
      final client = _client((_) => jsonResponse({'id': 1}), seen: seen);

      final result = await _put(client);

      final upload = seen.single;
      expect(upload.method, 'PUT');
      expect(upload.url.toString(), 'http://backend.test/users/me/photo');
      expect(upload.headers['content-type'], startsWith('multipart/form-data'));
      expect(upload.body, contains('name="file"'));
      expect(upload.body, contains('filename="me.jpg"'));
      expect(upload.body, contains('content-type: image/jpeg'));
      expect(upload.body, contains('ÿØÿAB')); // the bytes, untouched
      expect(result, {'id': 1});
    });

    test('works for any path and field (the store photo too)', () async {
      final seen = <_Upload>[];
      final client = _client((_) => jsonResponse({'id': 2}), seen: seen);
      await client.putMultipart(
        '/owner/store/photo',
        field: 'picture',
        bytes: [1, 2, 3],
        filename: 'shop.png',
        contentType: 'image/png',
      );
      expect(seen.single.url.path, '/owner/store/photo');
      expect(seen.single.body, contains('name="picture"'));
      expect(seen.single.body, contains('content-type: image/png'));
    });

    test('keeps the bearer token, and sends none when signed out', () async {
      final seen = <_Upload>[];
      final signedIn = _client((_) => jsonResponse({}), seen: seen);
      await _put(signedIn);
      expect(seen.single.headers['authorization'], 'Bearer owner-token');

      seen.clear();
      final signedOut = _client(
        (_) => jsonResponse({}),
        seen: seen,
        token: null,
      );
      await _put(signedOut);
      expect(seen.single.headers.containsKey('authorization'), isFalse);
    });

    test('does not change what the JSON calls send', () async {
      final api = MockedApi.json({'ok': true});
      await api.client.post('/x', body: {'a': 1});
      expect(api.single.headers['content-type'], contains('application/json'));
      expect(api.single.headers['authorization'], 'Bearer owner-token');
      expect(api.single.body, {'a': 1});
    });

    test(
      'maps an error response to an ApiException with status, message and code',
      () async {
        final client = _client(
          (_) => jsonResponse({
            'statusCode': 413,
            'message': 'The image must not exceed 5 MB',
            'code': 'TOO_BIG',
          }, 413),
        );
        await expectLater(
          _put(client),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 413)
                .having(
                  (e) => e.message,
                  'message',
                  'The image must not exceed 5 MB',
                )
                .having((e) => e.code, 'code', 'TOO_BIG'),
          ),
        );
      },
    );

    test('maps a list of validation messages like the JSON calls do', () async {
      final client = _client(
        (_) => jsonResponse({
          'message': ['first problem', 'second problem'],
        }, 400),
      );
      await expectLater(
        _put(client),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'first problem',
          ),
        ),
      );
    });

    test('maps 401 and 503 too', () async {
      for (final status in [401, 503]) {
        final client = _client((_) => jsonResponse({'message': 'x'}, status));
        await expectLater(
          _put(client),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', status),
          ),
        );
      }
    });

    test('maps a dead connection to a NetworkException', () async {
      final client = ApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
      );
      await expectLater(_put(client), throwsA(isA<NetworkException>()));
    });

    test('gives up after the upload timeout with a NetworkException', () async {
      final never = Completer<http.Response>();
      final client = ApiClient(
        baseUrl: 'http://backend.test',
        uploadTimeout: const Duration(milliseconds: 50),
        httpClient: MockClient((_) => never.future),
      );
      await expectLater(
        _put(client),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        ),
      );
    });

    test('allows 30 seconds by default', () {
      expect(ApiClient.defaultUploadTimeout, const Duration(seconds: 30));
      expect(ApiClient().uploadTimeout, const Duration(seconds: 30));
    });
  });
}
