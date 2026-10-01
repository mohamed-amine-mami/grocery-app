import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/services/api_client.dart';

import 'fakes.dart';

FakeStoreRepository _storeRepo(ApiClient api) =>
    FakeStoreRepository(api, store: closedStore);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('logout', () {
    testWidgets('after a restored session goes straight to login — no splash '
        'replay, no dead navigation', (tester) async {
      await pumpAppSignedInAs(tester, testOwner, storeRepository: _storeRepo);
      await _openTab(tester, 'Magasin');
      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle(); // deliberately no extra time: no timers

      expect(find.text('Connexion'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('a logged-out session does not come back on its own', (
      tester,
    ) async {
      final tokens = StoredToken();
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: _storeRepo,
        tokenStorage: tokens,
      );
      await _openTab(tester, 'Magasin');
      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();

      expect(tokens.token, isNull);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('session restore', () {
    testWidgets('keeps the session and offers a retry when the server cannot '
        'be reached (being offline is not being logged out)', (tester) async {
      final tokens = StoredToken();
      late FakeAuthRepository auth;
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: _storeRepo,
        tokenStorage: tokens,
        authRepository: (api) => auth = FakeAuthRepository(
          api,
          testOwner,
          meError: const NetworkException('offline'),
        ),
      );

      expect(find.text('Impossible de joindre le serveur.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Connexion'), findsNothing);
      expect(tokens.clearCalls, 0);
      expect(tokens.token, 'stored-token');

      auth.meError = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Impossible de joindre le serveur.'), findsNothing);
    });

    testWidgets('an invalid or expired token (401) clears the session and '
        'lands on login', (tester) async {
      final tokens = StoredToken();
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: _storeRepo,
        tokenStorage: tokens,
        authRepository: (api) => FakeAuthRepository(
          api,
          testOwner,
          meError: const ApiException(statusCode: 401),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(tokens.clearCalls, 1);
      expect(find.text('Connexion'), findsOneWidget);
    });

    testWidgets('no stored token shows the splash, then login', (tester) async {
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: _storeRepo,
        tokenStorage: StoredToken(token: null),
      );
      expect(find.text('Connexion'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Connexion'), findsOneWidget);
    });

    testWidgets('a restored client lands on the client home, not the owner '
        'shell', (tester) async {
      await pumpAppSignedInAs(
        tester,
        testClient,
        storeRepository: FakeStoreRepository.new,
      );
      expect(
        find.textContaining('Vous êtes connecté en tant que client'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('owner registration', () {
    Future<void> registerOwner(WidgetTester tester) async {
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: FakeStoreRepository.new, // no store yet
        tokenStorage: StoredToken(token: null),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nouveau ici ? Créer un compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propriétaire'));
      await tester.pumpAndSettle();

      Finder field(String label) => find.widgetWithText(TextFormField, label);
      await tester.enterText(field('Nom'), 'Karim');
      await tester.enterText(field('Adresse e-mail'), 'karim@example.com');
      await tester.enterText(field('Numéro de téléphone'), '20123456');
      await tester.enterText(field('Mot de passe'), 'fortunes');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
    }

    testWidgets('continues to store creation with nothing to go back to', (
      tester,
    ) async {
      await registerOwner(tester);

      expect(find.text('Créer votre magasin'), findsOneWidget);
      // Going back would land on the account-type screen while logged in.
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Vous êtes...'), findsNothing);
    });

    testWidgets('store creation has a sign-out action', (tester) async {
      await registerOwner(tester);

      await tester.tap(find.byTooltip('Se déconnecter'));
      await tester.pumpAndSettle();

      expect(find.text('Connexion'), findsOneWidget);
    });
  });
}
