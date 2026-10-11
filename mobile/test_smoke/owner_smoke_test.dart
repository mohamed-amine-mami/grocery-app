// End-to-end smoke test of the whole Owner lifecycle: the real app UI against a
// REAL backend over HTTP (only the secure token store is in-memory).
//
// Not part of `flutter test` (which only runs `test/`). Run it against a
// throwaway backend — see "Smoke test" in docs/owner-domain.md:
//
//   flutter test test_smoke --dart-define=API_BASE_URL=http://localhost:3001
//
// The backend's database must hold the global catalog (`npm run catalog:import`
// in `backend/`, pointed at the same database): owners add products from it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/repositories/catalog_repository.dart';
import 'package:grocery_mobile/data/repositories/customer_orders_repository.dart';
import 'package:grocery_mobile/data/repositories/customer_stores_repository.dart';
import 'package:grocery_mobile/data/repositories/orders_repository.dart';
import 'package:grocery_mobile/data/repositories/store_products_repository.dart';
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
      catalogRepository: CatalogRepository(api),
      storeProductsRepository: StoreProductsRepository(api),
      ordersRepository: OrdersRepository(api),
      customerStoresRepository: CustomerStoresRepository(api),
      customerOrdersRepository: CustomerOrdersRepository(api),
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

/// Types into the picker's search and waits out the debounce and the request.
Future<void> _pickerSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
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

/// The data layer on its own, over real HTTP, as the signed-in owner.
({CatalogRepository catalog, StoreProductsRepository storeProducts}) _repos() {
  final api = ApiClient(baseUrl: _baseUrl)..setAuthToken(_tokens.token);
  return (
    catalog: CatalogRepository(api),
    storeProducts: StoreProductsRepository(api),
  );
}

/// Runs [action] over real I/O and returns what it threw (or null). Capturing
/// it inside `runAsync` keeps the failure out of the test zone's uncaught-error
/// handler, so it can be asserted on.
Future<Object?> _thrownBy(
  WidgetTester tester,
  Future<Object?> Function() action,
) => tester.runAsync<Object?>(() async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
});

void main() {
  setUpAll(() {
    // `flutter test` blocks real HTTP by default; this test needs it.
    HttpOverrides.global = null;
  });

  testWidgets(
    'Owner lifecycle: register → store → catalog → store products → restart → logout',
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
      expect(find.text('Démarrer votre magasin · 0/2'), findsOneWidget);
      expect(_nav('Commandes'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));

      // ── 4. Edit the store ─────────────────────────────────────────────
      await _openTab(tester, 'Magasin');
      await _type(tester, 'Nom du magasin', 'Épicerie Smoke Bio');
      await _type(tester, 'Description', 'Produits frais.');
      await _tap(tester, find.text('Enregistrer'));
      await _waitFor(tester, find.text('Modifications enregistrées.'));
      await _openTab(tester, 'Accueil');
      expect(find.text('Épicerie Smoke Bio'), findsOneWidget);

      // ── 5. The catalogue starts empty — and owners cannot create categories
      await _openTab(tester, 'Catalogue');
      expect(find.text('Aucun produit'), findsOneWidget);
      expect(find.byTooltip('Gérer les catégories'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);

      // ── 6. Browse the global catalog through the data layer ───────────
      final repos = _repos();
      final categories = (await tester.runAsync(repos.catalog.categories))!;
      expect(categories, isNotEmpty);
      final vegetables = categories.firstWhere((c) => c.slug == 'legumes');
      expect(vegetables.name, 'Légumes');
      expect(vegetables.productCount, greaterThan(0));

      final picker = (await tester.runAsync(repos.catalog.products))!;
      final tomatoItem = picker.firstWhere((i) => i.product.slug == 'tomate');
      expect(tomatoItem.inMyStore, isFalse);
      expect(tomatoItem.storeProductId, isNull);
      expect(tomatoItem.product.defaultSaleUnit, SaleUnit.kg);
      expect(tomatoItem.product.allowedSaleUnits, [
        SaleUnit.kg,
        SaleUnit.piece,
      ]);
      expect(tomatoItem.product.category.name, 'Légumes');

      // ── 7. Add Tomate to the store: the catalog's rules, the store's price
      var tomatoes = (await tester.runAsync(
        () => repos.storeProducts.create(
          NewStoreProduct(
            productId: tomatoItem.product.id,
            priceMillimes: 1800,
          ),
        ),
      ))!;
      expect(tomatoes.product.slug, 'tomate');
      expect(tomatoes.saleUnit, SaleUnit.kg);
      expect(tomatoes.priceMillimes, 1800);
      expect(tomatoes.minQuantity, 500);
      expect(tomatoes.quantityStep, 100);
      expect(tomatoes.maxQuantity, 10000);
      expect(tomatoes.trackStock, isFalse);
      expect(tomatoes.stockQuantity, isNull);
      expect(tomatoes.isOrderable, isTrue);

      // A duplicate is a 409; the picker now says the store has it.
      final duplicate = await _thrownBy(
        tester,
        () => repos.storeProducts.create(
          NewStoreProduct(productId: tomatoItem.product.id, priceMillimes: 1),
        ),
      );
      expect(duplicate, isA<ApiException>());
      expect((duplicate! as ApiException).statusCode, 409);
      final afterAdd = (await tester.runAsync(repos.catalog.products))!;
      final flagged = afterAdd.firstWhere((i) => i.product.slug == 'tomate');
      expect(flagged.inMyStore, isTrue);
      expect(flagged.storeProductId, tomatoes.id);

      // ── 8. The owner's switch, independent of stock ───────────────────
      tomatoes = (await tester.runAsync(
        () => repos.storeProducts.setAvailability(
          tomatoes.id,
          isAvailable: false,
        ),
      ))!;
      expect(tomatoes.isOrderable, isFalse);
      expect(tomatoes.unavailabilityReason, UnavailabilityReason.ownerDisabled);
      tomatoes = (await tester.runAsync(
        () =>
            repos.storeProducts.setAvailability(tomatoes.id, isAvailable: true),
      ))!;
      expect(tomatoes.isOrderable, isTrue);

      // ── 9. Stock: track, reach zero, stale count refused, restock ─────
      tomatoes = (await tester.runAsync(
        () => repos.storeProducts.update(
          tomatoes.id,
          const StoreProductUpdate(
            stock: StockChange(
              trackStock: true,
              stockQuantity: 5000,
              expectedStockQuantity: null,
            ),
          ),
        ),
      ))!;
      expect(tomatoes.trackStock, isTrue);
      expect(tomatoes.stockQuantity, 5000);
      expect(tomatoes.isOrderable, isTrue);

      tomatoes = (await tester.runAsync(
        () => repos.storeProducts.update(
          tomatoes.id,
          const StoreProductUpdate(
            stock: StockChange(stockQuantity: 0, expectedStockQuantity: 5000),
          ),
        ),
      ))!;
      expect(tomatoes.stockQuantity, 0);
      expect(tomatoes.isAvailable, isTrue); // the owner never switched it off
      expect(tomatoes.isOrderable, isFalse);
      expect(tomatoes.unavailabilityReason, UnavailabilityReason.outOfStock);

      // The UI shows it unavailable on its own, with the switch still on.
      await _launchApp(tester);
      await _waitFor(tester, find.byType(NavigationBar));
      await _openTab(tester, 'Catalogue');
      await _waitFor(tester, find.text('Tomate'));
      expect(find.text('Légumes · 1'), findsOneWidget);
      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // A count made from a stale screen is refused, and says what is there now.
      final stale = await _thrownBy(
        tester,
        () => repos.storeProducts.update(
          tomatoes.id,
          const StoreProductUpdate(
            priceMillimes: 9999, // must not be applied either
            stock: StockChange(
              stockQuantity: 9000,
              expectedStockQuantity: 5000,
            ),
          ),
        ),
      );
      expect(stale, isA<StockChangedException>());
      expect((stale! as StockChangedException).currentStockQuantity, 0);
      expect(
        (await tester.runAsync(() => repos.storeProducts.get(tomatoes.id)))!
            .priceMillimes,
        1800,
      );

      tomatoes = (await tester.runAsync(
        () => repos.storeProducts.update(
          tomatoes.id,
          const StoreProductUpdate(
            stock: StockChange(stockQuantity: 9000, expectedStockQuantity: 0),
          ),
        ),
      ))!;
      expect(tomatoes.isOrderable, isTrue);

      // ── 10. Sell by the piece instead: restate price and rules ────────
      tomatoes = (await tester.runAsync(
        () => repos.storeProducts.update(
          tomatoes.id,
          const StoreProductUpdate(
            saleUnit: SaleUnit.piece,
            priceMillimes: 700,
            minQuantity: 1,
            quantityStep: 1,
            clearMaxQuantity: true,
            stock: StockChange(stockQuantity: 30, expectedStockQuantity: 9000),
          ),
        ),
      ))!;
      expect(tomatoes.saleUnit, SaleUnit.piece);
      expect(tomatoes.priceMillimes, 700);
      expect(tomatoes.maxQuantity, isNull);
      expect(tomatoes.stockQuantity, 30);
      expect(
        tomatoes.product.defaultSaleUnit,
        SaleUnit.kg,
      ); // identity unchanged

      // ── 11. Archive, then restore ─────────────────────────────────────
      await tester.runAsync(() => repos.storeProducts.archive(tomatoes.id));
      final active = (await tester.runAsync(repos.storeProducts.listActive))!;
      final archived = (await tester.runAsync(
        () => repos.storeProducts.list(status: StoreProductStatus.archived),
      ))!;
      expect(active, isEmpty);
      expect(archived.map((p) => p.product.slug), ['tomate']);
      expect(archived.single.isArchived, isTrue);
      expect(
        archived.single.unavailabilityReason,
        UnavailabilityReason.archived,
      );
      final archivedItem = (await tester.runAsync(repos.catalog.products))!
          .firstWhere((i) => i.product.slug == 'tomate');
      expect(archivedItem.inMyStore, isFalse);
      expect(archivedItem.storeProductArchived, isTrue);

      await _launchApp(tester);
      await _waitFor(tester, find.byType(NavigationBar));
      await _openTab(tester, 'Catalogue');
      expect(
        find.text('Aucun produit'),
        findsOneWidget,
      ); // archived stays hidden

      tomatoes = (await tester.runAsync(
        () => repos.storeProducts.restore(tomatoes.id),
      ))!;
      expect(tomatoes.isArchived, isFalse);
      expect(tomatoes.priceMillimes, 700); // exactly as it was left
      expect(tomatoes.stockQuantity, 30);

      // ── 12. The catalogue and dashboard follow ────────────────────────
      await _launchApp(tester);
      await _waitFor(tester, find.byType(NavigationBar));
      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);
      await _openTab(tester, 'Catalogue');
      await _waitFor(tester, find.text('Tomate'));
      expect(find.text('0,700 DT / pièce'), findsOneWidget);
      expect(find.text('Par tranche de 1 pièce'), findsOneWidget);
      expect(find.text('Indisponible'), findsNothing);

      // The owner's switch in the list.
      await _tap(tester, find.byType(Switch));
      await _waitFor(tester, find.text('Indisponible'));
      expect(
        (await tester.runAsync(() => repos.storeProducts.get(tomatoes.id)))!
            .isAvailable,
        isFalse,
      );

      // ── 13. The catalog picker, over the real catalog ─────────────────
      await _tap(tester, find.byType(FloatingActionButton));
      await _waitFor(tester, find.text('Rechercher un produit'));
      expect(find.text('Ajouter depuis le catalogue'), findsOneWidget);
      // The picker pages the catalog (40 a time) and searches it on the
      // server: look each product up.
      await _pickerSearch(tester, 'tomate');
      expect(find.text('Ajouté'), findsOneWidget); // Tomate: the store has it

      // Search is accent- and case-insensitive.
      await _pickerSearch(tester, 'OEUF');
      expect(find.text('Œufs frais'), findsOneWidget); // not yet in the store
      expect(find.text('Tomate'), findsNothing);
      await _tap(tester, find.byTooltip('Effacer la recherche'));

      // Category filter, combined with the search.
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Légumes'));
      await _pickerSearch(tester, 'tomate');
      expect(find.text('Tomate'), findsOneWidget);
      await _pickerSearch(tester, 'oeuf');
      expect(find.text('Œufs frais'), findsNothing); // not a vegetable
      expect(find.text('Aucun produit trouvé'), findsOneWidget);

      // ── 14. Quick-add: a price is enough ──────────────────────────────
      await _pickerSearch(tester, 'poivron');
      await _tap(tester, find.text('Poivron'));
      expect(find.text('Ajouter à mon magasin'), findsOneWidget);
      expect(find.text('Légumes · Au kilo'), findsWidgets); // read-only info
      await tester.enterText(
        find.widgetWithText(TextField, 'Prix au kilo (DT)'),
        '3,2',
      );
      await tester.pump();
      await _tap(tester, find.text('Ajouter à mon magasin'));
      await _waitFor(tester, find.text('Poivron ajouté à votre magasin.'));
      expect(find.text('Ajouter à mon magasin'), findsNothing); // sheet closed
      expect(find.text('Ajouté'), findsOneWidget); // Poivron

      // The picker stays open, and an added product cannot be added again.
      await _tap(tester, find.text('Poivron'));
      expect(find.text('Ajouter à mon magasin'), findsNothing);

      // ── 15. Quick-add with tracked stock at zero ─────────────────────
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Tous'));
      await _pickerSearch(tester, 'oeuf');
      await _tap(tester, find.text('Œufs frais'));
      await _tap(tester, find.text('Quantités, stock et disponibilité'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Prix à la pièce (DT)'),
        '0,35',
      );
      await tester.pump();
      await _tap(
        tester,
        find.widgetWithText(SwitchListTile, 'Suivre le stock'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Stock actuel (pièces)'),
        '0',
      );
      await tester.pump();
      expect(find.textContaining('Stock à 0'), findsOneWidget);
      await _tap(tester, find.text('Ajouter à mon magasin'));
      await _waitFor(tester, find.text('Œufs frais ajouté à votre magasin.'));
      expect(find.text('Ajouté'), findsOneWidget); // Œufs frais

      // What the backend now holds — and what it derived itself.
      final held = (await tester.runAsync(repos.storeProducts.listActive))!;
      expect(held.map((p) => p.product.slug).toSet(), {
        'tomate',
        'poivron',
        'oeufs',
      });
      final peppers = held.firstWhere((p) => p.product.slug == 'poivron');
      expect(peppers.priceMillimes, 3200);
      expect(peppers.saleUnit, SaleUnit.kg);
      expect(peppers.minQuantity, 500); // the catalog's defaults
      expect(peppers.quantityStep, 100);
      expect(peppers.trackStock, isFalse);
      expect(peppers.isOrderable, isTrue);
      final eggs = held.firstWhere((p) => p.product.slug == 'oeufs');
      expect(eggs.saleUnit, SaleUnit.piece);
      expect(eggs.priceMillimes, 350);
      expect(eggs.trackStock, isTrue);
      expect(eggs.stockQuantity, 0);
      expect(eggs.isAvailable, isTrue); // the app never switched it off
      expect(eggs.isOrderable, isFalse); // the backend did
      expect(eggs.unavailabilityReason, UnavailabilityReason.outOfStock);

      // Back in the catalogue, the new products are listed.
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);
      await _waitFor(tester, find.text('Poivron'));
      expect(find.text('Légumes · 2'), findsOneWidget);
      expect(find.text('Produits laitiers · 1'), findsOneWidget);
      expect(find.text('Œufs frais'), findsOneWidget);
      expect(
        find.text('Indisponible'),
        findsOneWidget,
      ); // Tomate (switched off)
      expect(find.text('Rupture de stock'), findsOneWidget); // Œufs frais

      // ── 16. The store-product editor, against the real backend ────────
      // Restock the eggs: the backend makes them orderable again.
      await _tap(tester, find.text('Œufs frais'));
      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(find.text('Catalogue — lecture seule'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Modifier le stock (pièces)'),
        '24',
      );
      await tester.pump();
      await _tap(tester, find.text('Enregistrer'));
      await _waitFor(tester, find.text('Modifications enregistrées.'));
      expect(find.text('Rupture de stock'), findsNothing); // eggs restocked
      expect(find.text('Indisponible'), findsOneWidget); // Tomate: switched off

      // Sell the peppers by the piece: new price and rules, no maximum.
      await _tap(tester, find.text('Poivron'));
      await _tap(tester, find.text('À la pièce'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Prix à la pièce (DT)'),
        '0,6',
      );
      await tester.pump();
      await _tap(tester, find.text('Enregistrer'));
      await _waitFor(tester, find.text('Modifications enregistrées.'));

      var held16 = (await tester.runAsync(repos.storeProducts.listActive))!;
      final eggs16 = held16.firstWhere((p) => p.product.slug == 'oeufs');
      expect(eggs16.stockQuantity, 24);
      expect(eggs16.isOrderable, isTrue); // derived by the backend
      expect(eggs16.isAvailable, isTrue);
      final peppers16 = held16.firstWhere((p) => p.product.slug == 'poivron');
      expect(peppers16.saleUnit, SaleUnit.piece);
      expect(peppers16.priceMillimes, 600);
      expect(peppers16.minQuantity, 1);
      expect(peppers16.quantityStep, 1);
      expect(peppers16.maxQuantity, isNull);

      // An order (here: another client) changes the stock behind the screen.
      await _tap(tester, find.text('Œufs frais'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Modifier le stock (pièces)'),
        '30',
      );
      await tester.pump();
      await tester.runAsync(
        () => repos.storeProducts.update(
          eggs16.id,
          const StoreProductUpdate(
            stock: StockChange(expectedStockQuantity: 24, stockQuantity: 20),
          ),
        ),
      );
      await _tap(tester, find.text('Enregistrer'));
      expect(
        find.textContaining('il est maintenant de 20 pièces'),
        findsOneWidget,
      );
      expect(find.text('Enregistrer'), findsOneWidget); // still editing
      await _tap(tester, find.text('Enregistrer')); // checked against 20 now
      await _waitFor(tester, find.text('Modifications enregistrées.'));
      held16 = (await tester.runAsync(repos.storeProducts.listActive))!;
      expect(
        held16.firstWhere((p) => p.product.slug == 'oeufs').stockQuantity,
        30,
      );

      // Archive the peppers, then restore that same store product.
      await _tap(tester, find.text('Poivron'));
      await _tap(tester, find.text('Archiver ce produit'));
      await _tap(tester, find.widgetWithText(TextButton, 'Archiver'));
      await _waitFor(tester, find.text('Poivron archivé.'));
      expect(find.text('Poivron'), findsNothing);

      await _tap(tester, find.text('Ajouter depuis le catalogue'));
      await _waitFor(tester, find.text('Rechercher un produit'));
      await _pickerSearch(tester, 'poivron');
      await _waitFor(tester, find.text('Archivé'));
      await _tap(tester, find.text('Poivron'));
      expect(find.text('Produit archivé'), findsOneWidget);
      await _tap(tester, find.text('Restaurer ce produit'));
      await _waitFor(tester, find.text('Poivron restauré.'));
      await tester.tap(find.byTooltip('Retour')); // editor → picker
      await _settle(tester);
      await tester.tap(find.byTooltip('Retour')); // picker → catalogue
      await _settle(tester);
      await _waitFor(tester, find.text('Poivron'));

      final all = (await tester.runAsync(
        () => repos.storeProducts.list(status: StoreProductStatus.all),
      ))!;
      expect(all.length, 3); // restored, not duplicated
      expect(
        all.firstWhere((p) => p.product.slug == 'poivron').id,
        peppers16.id,
      );
      expect(all.every((p) => !p.isArchived), isTrue);

      // ── Open the store: setup complete ────────────────────────────────
      await _openTab(tester, 'Accueil');
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
      await _waitFor(tester, find.text('Tomate'));
      expect(find.text('Légumes · 2'), findsOneWidget);

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
