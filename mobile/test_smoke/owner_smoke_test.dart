// End-to-end smoke test of the whole Owner lifecycle: the real app UI against a
// REAL backend over HTTP (only the secure token store is in-memory).
//
// Not part of `flutter test` (which only runs `test/`). Run it against a
// throwaway backend — see "Smoke test" in docs/owner-domain.md:
//
//   flutter test test_smoke --dart-define=API_BASE_URL=http://localhost:3001
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/repositories/category_repository.dart';
import 'package:grocery_mobile/data/repositories/product_repository.dart';
import 'package:grocery_mobile/data/repositories/store_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/data/services/token_storage.dart';
import 'package:grocery_mobile/ui/app.dart';
import 'package:grocery_mobile/ui/features/auth/view_models/auth_view_model.dart';

const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3001',
);

/// Stands in for the platform Keychain, which isn't available in tests.
class _MemoryTokens extends TokenStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

late _MemoryTokens _tokens;

/// "Launching the app": a brand-new app instance (new HTTP client, new view
/// models) over whatever session is stored — exactly what a restart is.
Future<void> _launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  final api = ApiClient(baseUrl: _baseUrl);
  await tester.pumpWidget(
    GroceryApp(
      authViewModel: AuthViewModel(
        authRepository: AuthRepository(api),
        tokenStorage: _tokens,
        apiClient: api,
      ),
      storeRepository: StoreRepository(api),
      categoryRepository: CategoryRepository(api),
      productRepository: ProductRepository(api),
    ),
  );
  await _settle(tester);
}

/// Real network I/O doesn't advance in the test's fake clock, so give it real
/// time between frames.
Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  // A spinner animates forever, so `pumpAndSettle` would never return while a
  // request is still in flight: wait (in real time) until none is showing,
  // including tabs kept alive off-screen.
  for (var i = 0; i < 100; i++) {
    if (find
        .byType(CircularProgressIndicator, skipOffstage: false)
        .evaluate()
        .isEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  try {
    await tester.pumpAndSettle();
  } catch (_) {
    fail(
      'The UI never settled. Spinners (incl. offstage): '
      '${find.byType(CircularProgressIndicator, skipOffstage: false).evaluate().length}. '
      'On screen: ${_screenTexts()}',
    );
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  String? reason,
}) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('Timed out waiting for ${reason ?? finder.toString()}');
}

/// Lists the texts currently on screen — makes a failed step diagnosable.
String _screenTexts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .join(' | ');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    fail(
      'Nothing to tap for ${finder.toString()}. On screen: ${_screenTexts()}',
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await _settle(tester);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

Finder _nav(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_nav(label));
  await _settle(tester);
}

/// Takes the app from a cold start with no session to the login screen.
Future<void> _passSplash(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pumpAndSettle();
}

Future<List<dynamic>> _apiProducts(String status) async {
  final response = await http.get(
    Uri.parse('$_baseUrl/owner/products?status=$status'),
    headers: {'Authorization': 'Bearer ${_tokens.token}'},
  );
  return jsonDecode(response.body) as List<dynamic>;
}

void main() {
  setUpAll(() {
    // `flutter test` blocks real HTTP by default; this test needs it.
    HttpOverrides.global = null;
  });

  testWidgets(
    'Owner lifecycle: register → store → catalogue → restart → logout',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
      final phone = stamp.toString().padLeft(8, '2');
      const password = 'fortunes';
      _tokens = _MemoryTokens();

      // ── First launch → authentication ─────────────────────────────────
      await _launchApp(tester);
      expect(find.text('Connexion'), findsNothing); // splash first
      await _passSplash(tester);
      expect(find.text('Connexion'), findsOneWidget);

      // ── 1. Register an owner → OWNER + no store → StoreCreate ─────────
      await _tap(tester, find.text('Nouveau ici ? Créer un compte'));
      await _tap(tester, find.text('Propriétaire'));
      await _type(tester, 'Nom', 'Karim Smoke');
      await _type(tester, 'Adresse e-mail', 'smoke-$stamp@example.com');
      await _type(tester, 'Numéro de téléphone', phone);
      await _type(tester, 'Mot de passe', password);
      await _tap(tester, find.text('Continuer'));
      await _waitFor(tester, find.text('Créer votre magasin'));
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      // ── App restart: still OWNER + no store → StoreCreate ─────────────
      await _launchApp(tester);
      await _waitFor(tester, find.text('Créer votre magasin'));

      // ── Logout → authentication ───────────────────────────────────────
      await tester.tap(find.byTooltip('Se déconnecter'));
      await _settle(tester);
      expect(find.text('Connexion'), findsOneWidget);
      expect(_tokens.token, isNull);

      // ── 2. Login → OWNER + no store → StoreCreate ─────────────────────
      await _type(tester, 'Numéro de téléphone', phone);
      await _type(tester, 'Mot de passe', password);
      await _tap(tester, find.text('Se connecter'));
      await _waitFor(tester, find.text('Créer votre magasin'));

      // ── 3. Create the store → OwnerShell ──────────────────────────────
      await _type(tester, 'Nom du magasin', 'Épicerie Smoke');
      await _type(tester, 'Adresse du magasin', '12 Rue de la Liberté, Tunis');
      await _tap(tester, find.text('Créer mon magasin'));
      await _waitFor(tester, find.byType(NavigationBar));
      expect(
        find.text('Magasin fermé'),
        findsOneWidget,
      ); // new stores start closed
      expect(find.text('Démarrer votre magasin · 0/3'), findsOneWidget);
      expect(_nav('Commandes'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(3));

      // ── 4. Edit the store ─────────────────────────────────────────────
      await _openTab(tester, 'Magasin');
      await _type(tester, 'Nom du magasin', 'Épicerie Smoke Bio');
      await _type(tester, 'Description', 'Produits frais.');
      await _tap(tester, find.text('Enregistrer'));
      await _waitFor(tester, find.text('Modifications enregistrées.'));
      await _openTab(tester, 'Accueil');
      expect(find.text('Épicerie Smoke Bio'), findsOneWidget);

      // ── 5. Create a category ──────────────────────────────────────────
      await _openTab(tester, 'Catalogue');
      expect(find.text('Aucun produit'), findsOneWidget);
      await _tap(tester, find.byTooltip('Gérer les catégories'));
      expect(find.text('Aucune catégorie'), findsOneWidget);
      await _tap(tester, find.text('Ajouter une catégorie'));
      await _type(tester, 'Nom de la catégorie', 'Fruits et légumes');
      await _tap(tester, find.text('Ajouter'));
      await _waitFor(tester, find.text('Fruits et légumes'));

      // A duplicate (any case) is refused, in French, and the dialog stays.
      await _tap(tester, find.text('Ajouter une catégorie'));
      await _type(tester, 'Nom de la catégorie', 'FRUITS ET LÉGUMES');
      await _tap(tester, find.text('Ajouter'));
      await _waitFor(
        tester,
        find.text('Une catégorie avec ce nom existe déjà.'),
      );
      await _tap(tester, find.text('Annuler'));

      // ── 6. Rename the category ────────────────────────────────────────
      await _tap(tester, find.byTooltip('Renommer « Fruits et légumes »'));
      await _type(tester, 'Nom de la catégorie', 'Fruits & légumes');
      await _tap(tester, find.text('Enregistrer'));
      await _waitFor(tester, find.text('Fruits & légumes'));
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);

      // ── 7. Product sold by PIECE: 1, 2, 3 ─────────────────────────────
      await _waitFor(tester, find.text('Ajouter un produit'));
      await _tap(tester, find.text('Ajouter un produit'));
      expect(find.text('1, 2, 3 pièces…'), findsOneWidget);
      await _type(tester, 'Nom du produit', 'Œufs');
      await _type(tester, 'Prix à la pièce (DT)', '0,350');
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fruits & légumes').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Ajouter le produit'));
      await _waitFor(tester, find.text('0,350 DT / pièce'));
      expect(find.text('Par tranche de 1 pièce'), findsOneWidget);

      // ── 8. Product sold by KG: 500 g, 1 kg, 1,5 kg ────────────────────
      await _tap(tester, find.byType(FloatingActionButton));
      await _tap(tester, find.text('Au kilo'));
      expect(find.text('100 g, 200 g, 300 g…'), findsOneWidget);
      await _tap(tester, find.widgetWithText(ChoiceChip, '500 g'));
      expect(find.text('500 g, 1 kg, 1,5 kg…'), findsOneWidget);
      await _type(tester, 'Nom du produit', 'Tomates');
      await _type(tester, 'Prix au kilo (DT)', '1,8');
      expect(find.text('500 g = 0,900 DT · 1,800 DT / kg'), findsOneWidget);
      await _tap(tester, find.text('Ajouter le produit'));
      await _waitFor(tester, find.text('1,800 DT / kg'));
      expect(find.text('Par tranche de 500 g'), findsOneWidget);
      // Products sit under their category; the tomatoes have none.
      expect(find.text('Fruits & légumes · 1'), findsOneWidget);
      expect(find.text('Sans catégorie · 1'), findsOneWidget);

      // ── 9. Toggle a product unavailable ───────────────────────────────
      expect(find.text('Indisponible'), findsNothing);
      final tomatoSwitch = find.descendant(
        of: find
            .ancestor(of: find.text('Tomates'), matching: find.byType(InkWell))
            .first,
        matching: find.byType(Switch),
      );
      await _tap(tester, tomatoSwitch);
      await _waitFor(tester, find.text('Indisponible'));
      expect(find.text('Tomates'), findsOneWidget); // unavailable ≠ removed

      // ── 10. Edit a product ────────────────────────────────────────────
      await _tap(tester, find.text('Tomates'));
      expect(find.text('Modifier le produit'), findsOneWidget);
      await _type(tester, 'Prix au kilo (DT)', '2');
      expect(find.text('500 g = 1,000 DT · 2,000 DT / kg'), findsOneWidget);
      await _tap(tester, find.text('Enregistrer'));
      await _waitFor(tester, find.text('2,000 DT / kg'));
      expect(
        find.text('Indisponible'),
        findsOneWidget,
      ); // edit kept availability

      // ── 11. Archive a product ─────────────────────────────────────────
      await _tap(tester, find.text('Tomates'));
      await _tap(tester, find.text('Supprimer du catalogue'));
      await _tap(tester, find.text('Supprimer'));
      await _waitFor(tester, find.text('Produit supprimé du catalogue.'));
      expect(find.text('Tomates'), findsNothing);
      expect(find.text('Œufs'), findsOneWidget);
      // Archived, not deleted: hidden from the active catalogue, kept in the DB.
      final active = await tester.runAsync(() => _apiProducts('active'));
      final archived = await tester.runAsync(() => _apiProducts('archived'));
      expect(active!.map((p) => (p as Map)['name']), ['Œufs']);
      expect(archived!.map((p) => (p as Map)['name']), ['Tomates']);

      // ── Dashboard follows: category + product done, store still closed ─
      await _openTab(tester, 'Accueil');
      expect(find.text('Démarrer votre magasin · 2/3'), findsOneWidget);
      await _tap(tester, find.text('Ouvrir le magasin'));
      expect(find.byType(Switch), findsOneWidget); // Magasin tab
      await _tap(tester, find.byType(Switch));
      await _waitFor(tester, find.text('Magasin ouvert'));
      await _openTab(tester, 'Accueil');
      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsOneWidget);

      // ── 12–13. Restart app → OWNER + store → OwnerShell ───────────────
      await _launchApp(tester);
      await _waitFor(tester, find.byType(NavigationBar));
      expect(find.text('Créer votre magasin'), findsNothing);
      expect(find.text('Connexion'), findsNothing);
      expect(find.text('Magasin ouvert'), findsOneWidget);
      await _openTab(tester, 'Catalogue');
      await _waitFor(tester, find.text('Œufs'));
      expect(find.text('Tomates'), findsNothing); // archived stays hidden
      expect(find.text('Fruits & légumes · 1'), findsOneWidget);

      // ── 14. Logout ────────────────────────────────────────────────────
      await _openTab(tester, 'Magasin');
      await _tap(tester, find.text('Se déconnecter'));
      expect(find.text('Connexion'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // ── 15. Restart → unauthenticated ─────────────────────────────────
      expect(_tokens.token, isNull);
      await _launchApp(tester);
      await _passSplash(tester);
      expect(find.text('Connexion'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Let the HTTP client's 15 s keep-alive timers (created in fake time)
      // fire, so the framework doesn't report them as leaked.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
    },
  );
}
