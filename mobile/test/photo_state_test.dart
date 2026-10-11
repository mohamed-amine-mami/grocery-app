import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:grocery_mobile/ui/features/store/view_models/store_edit_view_model.dart';

import 'fakes.dart';

void main() {
  group('the signed-in user follows a photo change', () {
    late AuthViewModel auth;

    setUp(() async {
      final api = ApiClient();
      auth = AuthViewModel(
        authRepository: FakeAuthRepository(api, testClient),
        tokenStorage: StoredToken(),
        apiClient: api,
      );
      await auth.bootstrap();
    });

    test('adopts the user the backend returned, and tells listeners', () {
      var notified = 0;
      auth.addListener(() => notified++);

      auth.updateCurrentUser(
        const User(
          id: 2,
          name: 'Client',
          email: 'client@example.com',
          role: UserRole.client,
          photo: 'https://res.example/users/2/profile-ab.jpg',
        ),
      );
      expect(
        auth.currentUser!.photo,
        'https://res.example/users/2/profile-ab.jpg',
      );
      expect(notified, 1);

      auth.updateCurrentUser(
        const User(
          id: 2,
          name: 'Client',
          email: 'client@example.com',
          role: UserRole.client,
        ),
      );
      expect(auth.currentUser!.photo, isNull);
    });

    test('ignores a late result once signed out', () async {
      await auth.logout();
      auth.updateCurrentUser(testClient);
      expect(auth.currentUser, isNull);
    });
  });

  test('the owner’s store follows a photo change', () {
    final viewModel = StoreEditViewModel(
      storeRepository: FakeStoreRepository(ApiClient(), store: closedStore),
      initialStore: closedStore,
    );
    var notified = 0;
    viewModel.addListener(() => notified++);

    viewModel.updateStore(
      const Store(
        id: 10,
        name: 'Menzah Market',
        address: '12 Rue de la Liberté, Tunis',
        isOpen: false,
        ownerId: 1,
        photo: 'https://res.example/stores/10/photo-ab.jpg',
      ),
    );
    expect(viewModel.store.photo, 'https://res.example/stores/10/photo-ab.jpg');
    expect(notified, 1);
  });
}
