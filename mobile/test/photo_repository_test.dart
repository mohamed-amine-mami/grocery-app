import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/repositories/store_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/data/services/image_picker_service.dart';

import 'api_test_support.dart';

final _image = PickedImage(
  bytes: Uint8List.fromList([9, 8, 7]),
  filename: 'me.jpg',
  contentType: 'image/jpeg',
);

const _photo = 'https://res.example/f_auto,q_auto/v1/users/1/profile-ab.jpg';

Map<String, Object?> _user(String? photo) => {
  'id': 1,
  'name': 'Jane',
  'email': 'jane@example.com',
  'phoneNumber': '+21612345678',
  'whatsappNumber': null,
  'photo': photo,
  'role': 'CLIENT',
};

Map<String, Object?> _store(String? photo) => {
  'id': 3,
  'name': 'Menzah Market',
  'description': null,
  'photo': photo,
  'address': '12 Rue de la Liberté',
  'latitude': null,
  'longitude': null,
  'isOpen': false,
  'ownerId': 2,
};

/// Records the multipart request and answers [json].
({ApiClient client, List<http.Request> sent}) _api(Object json) {
  final sent = <http.Request>[];
  final client = ApiClient(
    baseUrl: 'http://backend.test',
    httpClient: MockClient((request) async {
      sent.add(request);
      return jsonResponse(json);
    }),
  )..setAuthToken('token');
  return (client: client, sent: sent);
}

void main() {
  group('AuthRepository photo', () {
    test(
      'setPhoto PUTs /users/me/photo and returns the user with the new photo',
      () async {
        final api = _api(_user(_photo));
        final user = await AuthRepository(api.client).setPhoto(_image);

        final request = api.sent.single;
        expect(request.method, 'PUT');
        expect(request.url.path, '/users/me/photo');
        expect(request.headers['authorization'], 'Bearer token');
        expect(latin1.decode(request.bodyBytes), contains('name="file"'));
        expect(user.photo, _photo);
      },
    );

    test('removePhoto DELETEs /users/me/photo and returns the user without a photo', () async {
      final mocked = MockedApi.json(_user(null));
      final user = await AuthRepository(mocked.client).removePhoto();
      expect(mocked.single.method, 'DELETE');
      expect(mocked.single.path, '/users/me/photo');
      expect(user.photo, isNull);
    });

    test('register no longer sends a photo', () async {
      final mocked = MockedApi.json({
        'accessToken': 't',
        'user': _user(null),
      }, status: 201);
      await AuthRepository(mocked.client).register(
        name: 'Jane',
        email: 'jane@example.com',
        password: 'changeme123',
        phoneNumber: '+21612345678',
        role: UserRole.client,
      );
      expect((mocked.single.body as Map), isNot(contains('photo')));
    });
  });

  group('StoreRepository photo', () {
    test('setPhoto PUTs /owner/store/photo and returns the store with the new photo', () async {
      final api = _api(_store('https://res.example/stores/3/photo-ab.jpg'));
      final store = await StoreRepository(api.client).setPhoto(_image);

      expect(api.sent.single.method, 'PUT');
      expect(api.sent.single.url.path, '/owner/store/photo');
      expect(store.photo, 'https://res.example/stores/3/photo-ab.jpg');
    });

    test('removePhoto DELETEs /owner/store/photo', () async {
      final mocked = MockedApi.json(_store(null));
      final store = await StoreRepository(mocked.client).removePhoto();
      expect(mocked.single.method, 'DELETE');
      expect(mocked.single.path, '/owner/store/photo');
      expect(store.photo, isNull);
    });

    test('a failed upload surfaces the backend status', () async {
      final mocked = MockedApi.json({
        'message': 'Image storage is not configured',
      }, status: 503);
      await expectLater(
        StoreRepository(mocked.client).removePhoto(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('create and update no longer send a photo', () async {
      final mocked = MockedApi.json(_store(null), status: 200);
      final repository = StoreRepository(mocked.client);
      await repository.create(name: 'A', address: 'B');
      await repository.update(name: 'A', address: 'B');
      for (final request in mocked.requests) {
        expect((request.body as Map), isNot(contains('photo')));
      }
    });
  });
}
