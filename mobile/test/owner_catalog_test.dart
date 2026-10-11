import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/brand.dart';
import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/store_product.dart';

import 'fakes.dart';

late FakeStoreProductsRepository _products;
late FakeCatalogRepository _catalog;

Future<void> _pumpCatalog(
  WidgetTester tester, {
  List<StoreProduct> Function()? products,
  List<CatalogItem>? catalogItems,
  bool fails = false,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
    catalogRepository: (api) => _catalog = FakeCatalogRepository(
      api,
      items: catalogItems ?? fakeCatalogItems(),
    ),
    storeProductsRepository: (api) => _products = FakeStoreProductsRepository(
      api,
      products: products?.call() ?? [],
      fails: fails,
      catalog: catalogItems ?? fakeCatalogItems(),
      onCreated: (created) => _catalog.markAdded(created.productId, created.id),
    ),
  );
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Catalogue'),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Catalogue tab lists what the store sells, grouped by the products'
/// (global) categories, and opens the catalog picker to add more. Quick-add and
/// the store-product editor come with the next UI steps.
void main() {
  group('catalogue list', () {
    testWidgets('has a clean empty state that leads to the catalog', (
      tester,
    ) async {
      await _pumpCatalog(tester);

      expect(find.text('Aucun produit'), findsOneWidget);
      expect(find.text('Ajouter depuis le catalogue'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      // Owners cannot create categories or products: only pick from the catalog.
      expect(find.byTooltip('Gérer les catégories'), findsNothing);
      expect(find.text('Ajouter des produits'), findsNothing);
    });

    testWidgets('groups products by their catalog category and shows price '
        'and step', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes(), fakeEggs()]);

      expect(find.text('Fruits et légumes · 1'), findsOneWidget);
      expect(find.text('Produits laitiers · 1'), findsOneWidget);
      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('1,800 DT / kg'), findsOneWidget);
      expect(find.text('Par tranche de 500 g'), findsOneWidget);
      expect(find.text('Œufs'), findsOneWidget);
      expect(find.text('0,350 DT / pièce'), findsOneWidget);
    });

    testWidgets('filter chips narrow the list by category', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes(), fakeEggs()]);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Produits laitiers'));
      await tester.pumpAndSettle();
      expect(find.text('Œufs'), findsOneWidget);
      expect(find.text('Tomate'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Œufs'), findsOneWidget);
    });

    testWidgets('the chips are the categories the store sells in — no more', (
      tester,
    ) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);

      expect(
        find.widgetWithText(ChoiceChip, 'Fruits et légumes'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ChoiceChip, 'Produits laitiers'),
        findsNothing,
      );
      expect(find.widgetWithText(ChoiceChip, 'Sans catégorie'), findsNothing);
    });

    testWidgets('never lists archived products', (tester) async {
      await _pumpCatalog(
        tester,
        products: () => [
          fakeTomatoes(),
          fakeStoreProduct(id: 5, isArchived: true),
        ],
      );

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('the switch makes a product unavailable — with text, not just '
        'color', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);
      expect(find.text('Indisponible'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Indisponible'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
      expect(_products.byName('Tomate').isAvailable, isFalse);
    });

    testWidgets('a product the owner switched off shows as unavailable', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        products: () => [fakeTomatoes(isAvailable: false)],
      );

      expect(find.text('Indisponible'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('zero stock shows as unavailable on its own, with the switch '
        'still on', (tester) async {
      await _pumpCatalog(
        tester,
        products: () => [fakeTomatoes(trackStock: true, stockQuantity: 0)],
      );

      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsOneWidget);
      // One clear message, not two: the stock state says it all.
      expect(find.text('Indisponible'), findsNothing);
      // The owner never switched it off: the switch is theirs, stock is derived.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('an owner-disabled product with zero stock still shows the '
        'stock fact, and the switch off', (tester) async {
      await _pumpCatalog(
        tester,
        products: () => [
          fakeTomatoes(isAvailable: false, trackStock: true, stockQuantity: 0),
        ],
      );

      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('tracked stock is shown with its unit; untracked shows none', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        products: () => [
          fakeTomatoes(trackStock: true, stockQuantity: 20000),
          fakeEggs(),
        ],
      );

      expect(find.text('Stock : 20 kg'), findsOneWidget);
      expect(find.textContaining('Stock :'), findsOneWidget); // not the eggs
      expect(find.text('Rupture de stock'), findsNothing);
    });

    testWidgets('stock below the minimum order shows the stock and the '
        'backend-derived unavailability', (tester) async {
      await _pumpCatalog(
        tester,
        products: () => [fakeTomatoes(trackStock: true, stockQuantity: 100)],
      );

      expect(find.text('Stock : 100 g'), findsOneWidget);
      expect(find.text('Indisponible'), findsOneWidget);
      expect(find.text('Rupture de stock'), findsNothing);
    });

    testWidgets('each row shows the product image, with the placeholder when '
        'there is none', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes(), fakeEggs()]);

      expect(find.byIcon(Icons.shopping_basket_rounded), findsNWidgets(2));
    });

    testWidgets('stock above the minimum leaves a tracked product available', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        products: () => [fakeTomatoes(trackStock: true, stockQuantity: 5000)],
      );

      expect(find.text('Indisponible'), findsNothing);
    });

    testWidgets('says so, with a retry, when the catalogue cannot load', (
      tester,
    ) async {
      await _pumpCatalog(tester, fails: true);

      expect(find.text('Impossible de charger le catalogue.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });

  group('adding from the catalog', () {
    testWidgets('the empty state button opens the picker', (tester) async {
      await _pumpCatalog(tester);

      await tester.tap(find.text('Ajouter depuis le catalogue'));
      await tester.pumpAndSettle();

      expect(find.text('Rechercher un produit'), findsOneWidget);
      expect(find.text('Pomme'), findsOneWidget);
    });

    testWidgets('a button on the list opens the picker too', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Rechercher un produit'), findsOneWidget);
    });

    testWidgets('has no add button while the list is loading or failed', (
      tester,
    ) async {
      await _pumpCatalog(tester, fails: true);

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Ajouter depuis le catalogue'), findsNothing);
    });

    testWidgets('the picker marks what the store already sells', (
      tester,
    ) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Banane is the fixture's product already in the store.
      expect(find.text('Ajouté'), findsOneWidget);
    });

    testWidgets('going back returns to the catalogue unchanged', (
      tester,
    ) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // The app runs in French: the back button's tooltip is "Retour".
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      expect(find.text('Rechercher un produit'), findsNothing);
      expect(find.text('Tomate'), findsOneWidget);
      expect(_products.names, ['Tomate']);
    });

    testWidgets('choosing a product opens quick-add; nothing is added until '
        'it is confirmed', (tester) async {
      await _pumpCatalog(tester);
      await tester.tap(find.text('Ajouter depuis le catalogue'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pomme'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsOneWidget);
      expect(_products.names, isEmpty);
      expect(_products.createCalls, 0);
    });

    testWidgets('a product added in the picker shows up in the catalogue when '
        'the owner comes back', (tester) async {
      await _pumpCatalog(tester);
      await tester.tap(find.text('Ajouter depuis le catalogue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pomme'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Prix au kilo (DT)'),
        '2,5',
      );
      await tester.tap(find.text('Ajouter à mon magasin'));
      await tester.pumpAndSettle();
      expect(find.text('Ajouté'), findsNWidgets(2)); // Banane + Pomme

      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      expect(find.text('Rechercher un produit'), findsNothing);
      expect(find.text('Pomme'), findsOneWidget);
      expect(find.text('2,500 DT / kg'), findsOneWidget);
      expect(find.text('Aucun produit'), findsNothing);
      expect(_products.names, ['Pomme']);
    });
  });

  group('brand', () {
    testWidgets('is shown under the name, only for branded products', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        products: () => [
          fakeStoreProduct(
            id: 1,
            product: fakeCatalogProduct(
              id: 1,
              name: 'Yaourt nature',
              brand: const Brand(
                id: 1,
                slug: 'delice-danone',
                name: 'DÉLICE DANONE',
              ),
            ),
          ),
          fakeTomatoes(id: 2),
        ],
      );

      expect(find.text('DÉLICE DANONE'), findsOneWidget);
      expect(find.text('Tomate'), findsOneWidget);
    });
  });
}
