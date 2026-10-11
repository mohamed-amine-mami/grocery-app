import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/brand.dart';
import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/app_services.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/core/widgets/product_image.dart';
import 'package:grocery_mobile/ui/features/catalog/views/catalog_picker_view.dart';

import 'fakes.dart';

FakeCatalogRepository _catalog({
  List<CatalogItem>? items,
  bool fails = false,
  Completer<void>? gate,
}) => FakeCatalogRepository(
  ApiClient(),
  items: items ?? fakeCatalogItems(),
  fails: fails,
  gate: gate,
);

/// Opens the picker the way the Catalogue tab does: pushed on a route.
/// Returns the store's side, to assert on what was sent.
Future<FakeStoreProductsRepository> _openPicker(
  WidgetTester tester,
  FakeCatalogRepository catalog, {
  bool settle = true,
  List<StoreProduct> existing = const [],
  double height = 2600,
}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = ApiClient();
  final storeProducts = FakeStoreProductsRepository(
    api,
    products: existing,
    catalog: catalog.items,
    onCreated: (created) => catalog.markAdded(created.productId, created.id),
  );
  await tester.pumpWidget(
    AppServices(
      storeRepository: FakeStoreRepository(api, store: closedStore),
      catalogRepository: catalog,
      storeProductsRepository: storeProducts,
      ordersRepository: FakeOrdersRepository(api),
      customerStoresRepository: FakeCustomerStoresRepository(api),
      customerOrdersRepository: FakeCustomerOrdersRepository(api),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const CatalogPickerView()),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Let the route build, without waiting for a spinner that never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  return storeProducts;
}

Finder get _search => find.byType(TextField);

/// Types [text] and waits out the search debounce and the request.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_search, text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Picks [name], types [price] and confirms — the owner's quick path.
Future<void> _quickAdd(
  WidgetTester tester,
  String name,
  String price, {
  String priceLabel = 'Prix au kilo (DT)',
}) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, priceLabel), price);
  await tester.pump();
  await tester.tap(find.text('Ajouter à mon magasin'));
  await tester.pumpAndSettle();
}

Future<void> _chip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void main() {
  group('loading', () {
    testWidgets('shows a spinner while the catalog loads, then the products', (
      tester,
    ) async {
      final gate = Completer<void>();
      await _openPicker(tester, _catalog(gate: gate), settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Pomme'), findsNothing);
      expect(_search, findsNothing); // nothing to search yet

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Pomme'), findsOneWidget);
    });

    testWidgets('fetches one page, not the whole catalog', (tester) async {
      final catalog = _catalog();
      await _openPicker(tester, catalog);

      expect(catalog.browseCalls, hasLength(1));
      expect(catalog.browseCalls.single.limit, 40);
      expect(catalog.browseCalls.single.cursor, isNull);
    });

    testWidgets('searching and filtering ask the backend, once each', (
      tester,
    ) async {
      final catalog = _catalog();
      await _openPicker(tester, catalog);

      await _type(tester, 'pom');
      expect(catalog.browseCalls, hasLength(2));
      expect(catalog.browseCalls.last.query, 'pom');

      await _chip(tester, 'Légumes');
      expect(catalog.browseCalls, hasLength(3));
      expect(catalog.browseCalls.last.categoryId, fakeVegetables.id);
      expect(catalog.browseCalls.last.query, 'pom');

      await _chip(tester, 'Tous');
      expect(catalog.browseCalls, hasLength(4));
      expect(catalog.browseCalls.last.categoryId, isNull);
    });
  });

  group('the list', () {
    testWidgets('shows each product with its category and how it is sold', (
      tester,
    ) async {
      await _openPicker(tester, _catalog());

      expect(find.text('Pomme'), findsOneWidget);
      expect(find.text('Fruits · Au kilo'), findsNWidgets(2)); // Banane, Pomme
      expect(find.text('Légumes · Au kilo'), findsNWidgets(2));
      expect(find.text('Produits laitiers · À la pièce'), findsNWidgets(2));
      expect(find.text('6 produits'), findsOneWidget);
    });

    testWidgets('has the title and a prominent search bar', (tester) async {
      await _openPicker(tester, _catalog());

      expect(find.text('Ajouter depuis le catalogue'), findsOneWidget);
      expect(find.text('Rechercher un produit'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('narrows the list as you type', (tester) async {
      await _openPicker(tester, _catalog());

      await _type(tester, 'pomme');

      expect(find.text('Pomme'), findsOneWidget);
      expect(find.text('Pomme de terre'), findsOneWidget);
      expect(find.text('Tomate'), findsNothing);
      expect(find.text('2 produits'), findsOneWidget);
    });

    testWidgets('matches every word, in any order', (tester) async {
      await _openPicker(tester, _catalog());

      await _type(tester, 'terre pomme');

      expect(find.text('Pomme de terre'), findsOneWidget);
      expect(find.text('Pomme'), findsNothing);
      expect(find.text('1 produit'), findsOneWidget);
    });

    testWidgets('ignores case and accents: "oeuf" finds Œufs', (tester) async {
      await _openPicker(tester, _catalog());

      await _type(tester, 'OEUF');

      expect(find.text('Œufs'), findsOneWidget);
      expect(find.text('Pomme'), findsNothing);
    });

    testWidgets('also finds products by their category name', (tester) async {
      await _openPicker(tester, _catalog());

      await _type(tester, 'legumes');

      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Pomme de terre'), findsOneWidget);
      expect(find.text('Pomme'), findsNothing);
    });

    testWidgets('the clear button empties the search and restores the list', (
      tester,
    ) async {
      await _openPicker(tester, _catalog());
      expect(find.byTooltip('Effacer la recherche'), findsNothing);

      await _type(tester, 'tomate');
      expect(find.text('1 produit'), findsOneWidget);

      await tester.tap(find.byTooltip('Effacer la recherche'));
      await tester.pumpAndSettle();

      expect(find.text('6 produits'), findsOneWidget);
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    });

    testWidgets('says so when nothing matches, and "Effacer les filtres" '
        'brings everything back', (tester) async {
      await _openPicker(tester, _catalog());

      await _type(tester, 'zzz');

      expect(find.text('Aucun produit trouvé'), findsOneWidget);
      expect(find.text('0 produit'), findsOneWidget);

      await tester.tap(find.text('Effacer les filtres'));
      await tester.pumpAndSettle();

      expect(find.text('Aucun produit trouvé'), findsNothing);
      expect(find.text('6 produits'), findsOneWidget);
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    });
  });

  group('category filtering', () {
    testWidgets('offers "Tous" and only the categories that have products', (
      tester,
    ) async {
      await _openPicker(tester, _catalog());

      final labels = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data);

      // Alphabetical, accents ignored.
      expect(labels, ['Tous', 'Fruits', 'Légumes', 'Produits laitiers']);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Tous'))
            .selected,
        isTrue,
      );
    });

    testWidgets('a category narrows the list and shows as selected', (
      tester,
    ) async {
      await _openPicker(tester, _catalog());

      await _chip(tester, 'Légumes');

      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Pomme de terre'), findsOneWidget);
      expect(find.text('Pomme'), findsNothing);
      expect(find.text('Œufs'), findsNothing);
      expect(find.text('2 produits'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Légumes'))
            .selected,
        isTrue,
      );
    });

    testWidgets('"Tous" lifts the filter', (tester) async {
      await _openPicker(tester, _catalog());
      await _chip(tester, 'Légumes');

      await _chip(tester, 'Tous');

      expect(find.text('6 produits'), findsOneWidget);
    });

    testWidgets('combines with the search', (tester) async {
      await _openPicker(tester, _catalog());

      await _chip(tester, 'Fruits');
      await _type(tester, 'pomme');

      expect(find.text('Pomme'), findsOneWidget);
      expect(find.text('Pomme de terre'), findsNothing); // a vegetable
      expect(find.text('1 produit'), findsOneWidget);
    });

    testWidgets('a category with no match for the search shows the empty '
        'result, and clearing resets both', (tester) async {
      await _openPicker(tester, _catalog());

      await _chip(tester, 'Produits laitiers');
      await _type(tester, 'tomate');
      expect(find.text('Aucun produit trouvé'), findsOneWidget);

      await tester.tap(find.text('Effacer les filtres'));
      await tester.pumpAndSettle();

      expect(find.text('6 produits'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Tous'))
            .selected,
        isTrue,
      );
    });
  });

  group('already in the store', () {
    testWidgets('a product the store sells says "Ajouté" — with an icon, not '
        'just color', (tester) async {
      await _openPicker(tester, _catalog());

      expect(find.text('Ajouté'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      // The label sits on Banane's row, and only there.
      final bananeRow = find.ancestor(
        of: find.text('Banane'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: bananeRow.first, matching: find.text('Ajouté')),
        findsOneWidget,
      );
    });

    testWidgets('an added product cannot be added again', (tester) async {
      await _openPicker(tester, _catalog());

      await tester.tap(find.text('Banane'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsNothing);
      expect(find.text('Ajouter depuis le catalogue'), findsOneWidget);
    });

    testWidgets('stays marked while searching and filtering', (tester) async {
      await _openPicker(tester, _catalog());

      await _chip(tester, 'Fruits');
      await _type(tester, 'banane');

      expect(find.text('Banane'), findsOneWidget);
      expect(find.text('Ajouté'), findsOneWidget);
    });

    testWidgets('a product the store archived is labelled "Archivé" and is not '
        'added again', (tester) async {
      final citron = fakeCatalogItem(
        id: 9,
        name: 'Citron',
        storeProductArchived: true,
      );
      final storeProducts = await _openPicker(
        tester,
        _catalog(items: [citron]),
        existing: [
          fakeStoreProduct(id: 109, product: citron.product, isArchived: true),
        ],
      );

      expect(find.text('Archivé'), findsOneWidget);
      expect(find.text('Ajouté'), findsNothing);

      await tester.tap(find.text('Citron'));
      await tester.pumpAndSettle();

      // It opens the existing store product, never a second quick-add.
      expect(find.text('Ajouter à mon magasin'), findsNothing);
      expect(find.text('Produit archivé'), findsOneWidget);
      expect(storeProducts.createCalls, 0);
    });

    testWidgets('restoring an archived product from there brings the same one '
        'back and the row reads "Ajouté"', (tester) async {
      final citron = fakeCatalogItem(
        id: 9,
        name: 'Citron',
        storeProductArchived: true,
      );
      final catalog = _catalog(items: [citron]);
      final storeProducts = await _openPicker(
        tester,
        catalog,
        existing: [
          fakeStoreProduct(id: 109, product: citron.product, isArchived: true),
        ],
      );

      await tester.tap(find.text('Citron'));
      await tester.pumpAndSettle();
      // The backend's catalog follows the restore.
      catalog.markAdded(9, 109);
      await tester.tap(find.text('Restaurer ce produit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(storeProducts.restoreCalls, 1);
      expect(storeProducts.createCalls, 0);
      expect(find.text('Ajouté'), findsOneWidget);
      expect(find.text('Archivé'), findsNothing);
    });

    testWidgets('an archived product that cannot be opened says so', (
      tester,
    ) async {
      // The catalog says it is archived, but the store has no such product.
      await _openPicker(
        tester,
        _catalog(
          items: [
            fakeCatalogItem(id: 9, name: 'Citron', storeProductArchived: true),
          ],
        ),
      );

      await tester.tap(find.text('Citron'));
      await tester.pumpAndSettle();

      expect(
        find.text('Impossible d’ouvrir ce produit. Veuillez réessayer.'),
        findsOneWidget,
      );
      expect(find.text('Restaurer ce produit'), findsNothing);
    });
  });

  group('search field', () {
    testWidgets('does not autocorrect French product names', (tester) async {
      await _openPicker(tester, _catalog());

      final field = tester.widget<TextField>(_search);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });
  });

  group('selection', () {
    testWidgets('choosing a product opens its quick-add sheet, with the '
        'picker still behind it', (tester) async {
      await _openPicker(tester, _catalog());

      await tester.tap(find.text('Tomate'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsOneWidget);
      expect(find.text('Rechercher un produit'), findsOneWidget);
      expect(find.text('Légumes · Au kilo'), findsWidgets);
    });

    testWidgets('works on a filtered, searched list', (tester) async {
      await _openPicker(tester, _catalog());

      await _chip(tester, 'Produits laitiers');
      await _type(tester, 'oeuf');
      await tester.tap(find.text('Œufs'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsOneWidget);
      // Œufs is a piece product: no unit to choose.
      expect(find.byType(SegmentedButton<SaleUnit>), findsNothing);
    });

    testWidgets('dismissing the sheet adds nothing and keeps the picker', (
      tester,
    ) async {
      await _openPicker(tester, _catalog());
      await tester.tap(find.text('Tomate'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsNothing);
      expect(find.text('Ajouté'), findsOneWidget); // still only Banane
    });

    testWidgets('going back closes the picker', (tester) async {
      await _openPicker(tester, _catalog());

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Rechercher un produit'), findsNothing);
      expect(find.text('ouvrir'), findsOneWidget);
    });
  });

  group('errors', () {
    testWidgets('says so, with a retry, when the catalog cannot load', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(fails: true));

      expect(find.text('Impossible de charger le catalogue.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(_search, findsNothing);
      expect(find.text('Pomme'), findsNothing);
    });

    testWidgets('"Réessayer" loads the catalog once the backend is back', (
      tester,
    ) async {
      final catalog = _catalog(fails: true);
      await _openPicker(tester, catalog);

      catalog.fails = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de charger le catalogue.'), findsNothing);
      expect(find.text('Pomme'), findsOneWidget);
      expect(catalog.productsCalls, 2);
    });

    testWidgets('a failed retry stays on the error', (tester) async {
      final catalog = _catalog(fails: true);
      await _openPicker(tester, catalog);

      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de charger le catalogue.'), findsOneWidget);
    });
  });

  group('empty catalog', () {
    testWidgets('says the catalog is empty — and offers nothing to search', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(items: const []));

      expect(find.text('Le catalogue est vide'), findsOneWidget);
      expect(_search, findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });

  group('the catalog stays read-only', () {
    testWidgets('the only input is the search; nothing edits or creates a '
        'product', (tester) async {
      await _openPicker(tester, _catalog());

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      for (final action in [
        'Modifier',
        'Supprimer',
        'Créer',
        'Nouveau produit',
        'Enregistrer',
      ]) {
        expect(find.textContaining(action), findsNothing);
      }
    });
  });

  group('adding from the picker', () {
    testWidgets('a successful add closes the sheet, marks the product '
        '"Ajouté" and confirms', (tester) async {
      final storeProducts = await _openPicker(tester, _catalog());
      expect(find.text('Ajouté'), findsOneWidget); // Banane

      await _quickAdd(tester, 'Tomate', '1,8');

      expect(find.text('Ajouter à mon magasin'), findsNothing); // sheet closed
      expect(find.text('Ajouté'), findsNWidgets(2));
      expect(find.text('Tomate ajouté à votre magasin.'), findsOneWidget);
      expect(storeProducts.createCalls, 1);
      expect(storeProducts.lastCreate!.productId, 4);
      expect(storeProducts.lastCreate!.priceMillimes, 1800);
    });

    testWidgets('the picker stays open, so the owner can keep adding', (
      tester,
    ) async {
      final storeProducts = await _openPicker(tester, _catalog());

      await _quickAdd(tester, 'Tomate', '1,8');
      expect(find.text('Rechercher un produit'), findsOneWidget);
      await _quickAdd(tester, 'Pomme', '2');

      expect(find.text('Ajouté'), findsNWidgets(3)); // Banane, Tomate, Pomme
      expect(storeProducts.createCalls, 2);
      expect(storeProducts.names, ['Tomate', 'Pomme']);
    });

    testWidgets('updates the state locally — no refetch of the catalog', (
      tester,
    ) async {
      final catalog = _catalog();
      await _openPicker(tester, catalog);

      await _quickAdd(tester, 'Tomate', '1,8');

      expect(catalog.productsCalls, 1);
    });

    testWidgets('an added product cannot be added twice', (tester) async {
      final storeProducts = await _openPicker(tester, _catalog());
      await _quickAdd(tester, 'Tomate', '1,8');

      await tester.tap(find.text('Tomate'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsNothing);
      expect(storeProducts.createCalls, 1);
    });

    testWidgets('the mark survives searching and filtering', (tester) async {
      await _openPicker(tester, _catalog());
      await _quickAdd(tester, 'Tomate', '1,8');

      await _chip(tester, 'Légumes');
      await _type(tester, 'tomate');

      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Ajouté'), findsOneWidget);
    });

    testWidgets('a product with stock tracked at zero is added, and flagged '
        'unavailable by the backend — not by the app', (tester) async {
      final storeProducts = await _openPicker(tester, _catalog());
      await tester.tap(find.text('Tomate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quantités, stock et disponibilité'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Prix au kilo (DT)'),
        '1,8',
      );
      await tester.tap(find.widgetWithText(SwitchListTile, 'Suivre le stock'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Stock actuel (g)'),
        '0',
      );
      await tester.pump();
      await tester.tap(find.text('Ajouter à mon magasin'));
      await tester.pumpAndSettle();

      expect(find.text('Tomate ajouté à votre magasin.'), findsOneWidget);
      expect(storeProducts.lastCreate!.stockQuantity, 0);
      expect(storeProducts.lastCreate!.isAvailable, isTrue);
      final created = storeProducts.byName('Tomate');
      expect(created.isOrderable, isFalse);
      expect(created.unavailabilityReason, UnavailabilityReason.outOfStock);
    });

    testWidgets('a rejected form does not add anything', (tester) async {
      final storeProducts = await _openPicker(tester, _catalog());

      await tester.tap(find.text('Tomate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter à mon magasin'));
      await tester.pumpAndSettle();

      expect(find.text('Le prix est requis.'), findsOneWidget);
      expect(storeProducts.createCalls, 0);
      expect(find.text('Ajouté'), findsOneWidget); // still only Banane
    });
  });

  group('adding when something changed meanwhile', () {
    testWidgets('a product another device just added: the list is reloaded and '
        'the owner is told', (tester) async {
      final catalog = _catalog();
      final tomato = catalog.items.firstWhere((i) => i.product.id == 4).product;
      await _openPicker(
        tester,
        catalog,
        existing: [fakeStoreProduct(id: 104, product: tomato)],
      );
      expect(find.text('Ajouté'), findsOneWidget); // the picker is stale

      catalog.markAdded(4, 104); // what the backend now says
      await _quickAdd(tester, 'Tomate', '1,8');

      expect(find.text('Ajouter à mon magasin'), findsNothing); // sheet closed
      expect(
        find.text('Ce produit est déjà dans votre magasin.'),
        findsOneWidget,
      );
      expect(find.text('Ajouté'), findsNWidgets(2)); // that row is in line
      // Only that product was looked at again: the list was not reloaded.
      expect(catalog.productsCalls, 1);
    });

    testWidgets('a product archived in the store is reported as such', (
      tester,
    ) async {
      final catalog = _catalog();
      final tomato = catalog.items.firstWhere((i) => i.product.id == 4).product;
      await _openPicker(
        tester,
        catalog,
        existing: [
          fakeStoreProduct(id: 104, product: tomato, isArchived: true),
        ],
      );

      catalog.markArchived(4, 104);
      await _quickAdd(tester, 'Tomate', '1,8');

      expect(
        find.text('Ce produit est archivé dans votre magasin.'),
        findsOneWidget,
      );
      expect(find.text('Archivé'), findsOneWidget);
    });

    testWidgets('a product the catalog removed is reported, and disappears', (
      tester,
    ) async {
      final catalog = _catalog();
      final storeProducts = await _openPicker(tester, catalog);
      storeProducts.createError = const ApiException(statusCode: 404);

      catalog.remove(4);
      await _quickAdd(tester, 'Tomate', '1,8');

      expect(
        find.text('Ce produit n’est plus disponible dans le catalogue.'),
        findsOneWidget,
      );
      expect(find.text('Tomate'), findsNothing);
      expect(find.text('5 produits'), findsOneWidget);
    });
  });

  group('API errors while adding', () {
    testWidgets('keep the sheet open with a message, and change nothing', (
      tester,
    ) async {
      final storeProducts = await _openPicker(tester, _catalog());
      storeProducts.createError = const NetworkException('offline');

      await _quickAdd(tester, 'Tomate', '1,8');

      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ajouter à mon magasin'), findsOneWidget); // sheet open
      expect(find.text('Ajouté'), findsOneWidget); // still only Banane
    });

    testWidgets('a retry succeeds once the backend is back', (tester) async {
      final storeProducts = await _openPicker(tester, _catalog());
      storeProducts.createError = const ApiException(statusCode: 500);
      await _quickAdd(tester, 'Tomate', '1,8');
      expect(find.textContaining('Impossible d’ajouter'), findsOneWidget);

      storeProducts.createError = null;
      await tester.tap(find.text('Ajouter à mon magasin'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à mon magasin'), findsNothing);
      expect(find.text('Ajouté'), findsNWidgets(2));
    });
  });

  group('brand', () {
    const danone = Brand(id: 1, slug: 'delice-danone', name: 'DÉLICE DANONE');
    const sodeen = Brand(id: 2, slug: 'sodeen', name: 'Sodeen');
    final items = [
      fakeCatalogItem(id: 1, name: 'Yaourt nature', brand: danone),
      fakeCatalogItem(id: 2, name: 'Yaourt nature', brand: sodeen),
      fakeCatalogItem(id: 3, name: 'Tomate'),
    ];

    testWidgets('shows the brand under the name, and nothing for brandless', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(items: items));

      expect(find.text('DÉLICE DANONE'), findsOneWidget);
      expect(find.text('Sodeen'), findsOneWidget);
      // Only the two branded rows have a brand line: the Tomate row has the
      // name and the category line, no third text.
      expect(
        find.descendant(
          of: find
              .ancestor(of: find.text('Tomate'), matching: find.byType(Column))
              .first,
          matching: find.byType(Text),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('same name, different brands: the rows can be told apart', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(items: items));
      expect(find.text('Yaourt nature'), findsNWidgets(2));

      await _type(tester, 'sodeen');
      expect(find.text('Yaourt nature'), findsOneWidget);
      expect(find.text('Sodeen'), findsOneWidget);
      expect(find.text('DÉLICE DANONE'), findsNothing);
    });
  });

  group('a large catalog', () {
    List<CatalogItem> big(int count) => [
      for (var i = 1; i <= count; i++)
        fakeCatalogItem(id: i, name: 'Produit ${i.toString().padLeft(5, '0')}'),
    ];

    testWidgets('builds only the rows near the screen, not thousands', (
      tester,
    ) async {
      final catalog = _catalog(items: big(5700));
      await _openPicker(tester, catalog, height: 900);

      expect(find.text('5700 produits'), findsOneWidget); // the match count
      final rows = tester.widgetList(find.byType(Card)).length;
      expect(rows, greaterThan(0));
      expect(rows, lessThan(40)); // a screenful (+ cache), of 5,700
      expect(catalog.browseCalls.first.limit, 40);
    });

    testWidgets('scrolling loads the next page, without repeating a row', (
      tester,
    ) async {
      final catalog = _catalog(items: big(120));
      await _openPicker(tester, catalog, height: 900);
      expect(catalog.browseCalls, hasLength(1));
      expect(find.text('Produit 00041'), findsNothing);

      await tester.dragUntilVisible(
        find.text('Produit 00045'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Produit 00045'), findsOneWidget);
      expect(catalog.browseCalls.length, greaterThanOrEqualTo(2));
      expect(catalog.browseCalls[1].cursor, '40');
      expect(catalog.browseCalls[1].limit, 40);
      final cursors = catalog.browseCalls.map((c) => c.cursor).toList();
      expect(cursors.toSet(), hasLength(cursors.length)); // never asked twice
    });

    testWidgets('shows a spinner at the end while the next page loads', (
      tester,
    ) async {
      final catalog = _catalog(items: big(120));
      final gate = Completer<void>();
      catalog.onBrowse = (call) async {
        if (call.cursor != null) {
          await gate.future;
        }
      };
      await _openPicker(tester, catalog, height: 900);

      await tester.dragUntilVisible(
        find.byType(CircularProgressIndicator),
        find.byType(ListView),
        const Offset(0, -400),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a failed page says so and "Réessayer" fetches it again', (
      tester,
    ) async {
      final catalog = _catalog(items: big(120));
      await _openPicker(tester, catalog, height: 900);
      catalog.fails = true;

      await tester.dragUntilVisible(
        find.text('Impossible de charger la suite.'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      expect(find.text('Impossible de charger la suite.'), findsOneWidget);
      expect(find.text('Produit 00001'), findsNothing); // scrolled away
      // The rows already loaded are still there, and so is the search.
      expect(_search, findsOneWidget);

      catalog.fails = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de charger la suite.'), findsNothing);
    });

    testWidgets('typing a search starts again from the first page', (
      tester,
    ) async {
      final catalog = _catalog(items: big(120));
      await _openPicker(tester, catalog, height: 900);
      await tester.dragUntilVisible(
        find.text('Produit 00045'),
        find.byType(ListView),
        const Offset(0, -400),
      );

      await _type(tester, 'Produit 0009');

      expect(catalog.browseCalls.last.cursor, isNull);
      expect(catalog.browseCalls.last.query, 'Produit 0009');
      expect(find.text('11 produits'), findsOneWidget); // 00009, 00090..00099
      expect(find.text('Produit 00090'), findsOneWidget);
      expect(find.text('Produit 00045'), findsNothing);
    });

    testWidgets('keeps the search field while a search is loading', (
      tester,
    ) async {
      final catalog = _catalog(items: big(120));
      await _openPicker(tester, catalog, height: 900);
      final gate = Completer<void>();
      catalog.gate = gate;

      await tester.enterText(_search, 'Produit 0001');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(_search, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Produit 00010'), findsOneWidget);
    });

    testWidgets('a failed search shows an error with a retry, and the field '
        'stays', (tester) async {
      final catalog = _catalog(items: big(120));
      await _openPicker(tester, catalog, height: 900);
      catalog.fails = true;

      await _type(tester, 'Produit 0001');

      expect(find.text('Impossible de charger les produits.'), findsOneWidget);
      expect(_search, findsOneWidget);

      catalog.fails = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(find.text('Impossible de charger les produits.'), findsNothing);
      expect(find.text('Produit 00010'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads the first page', (tester) async {
      final catalog = _catalog(items: big(120));
      await _openPicker(tester, catalog, height: 900);
      final calls = catalog.browseCalls.length;

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(catalog.browseCalls.length, greaterThan(calls));
      expect(find.text('Produit 00001'), findsOneWidget);
    });
  });

  group('thumbnails', () {
    const photo = 'https://res.example/f_auto,q_auto/v1/pomme.jpg';
    final items = [
      fakeCatalogItem(id: 1, name: 'Pomme', photo: photo),
      fakeCatalogItem(id: 2, name: 'Tomate', category: fakeVegetables),
      fakeCatalogItem(id: 3, name: 'Banane', photo: photo, inMyStore: true),
      fakeCatalogItem(
        id: 4,
        name: 'Yaourt nature',
        storeProductArchived: true,
        category: fakeDairy,
        unit: SaleUnit.piece,
      ),
    ];

    Finder row(String name) => find
        .ancestor(of: find.text(name), matching: find.byType(Card))
        .first;

    testWidgets('each row leads with its product’s own picture, small', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(items: items));

      final images = tester.widgetList<ProductImage>(find.byType(ProductImage));
      expect(images.map((i) => i.photo), [photo, null, photo, null]);
      expect(images.every((i) => i.size == 48), isTrue);

      // At the start of the row, before the name, centred on the row.
      for (final name in ['Pomme', 'Tomate', 'Banane', 'Yaourt nature']) {
        final image = tester.getRect(
          find.descendant(of: row(name), matching: find.byType(ProductImage)),
        );
        final card = tester.getRect(row(name));
        expect(image.right, lessThan(tester.getTopLeft(find.text(name)).dx));
        expect(image.center.dy, closeTo(card.center.dy, 1), reason: name);
        // The status stays at the end of the row.
        expect(card.right - image.right, greaterThan(card.width / 2));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('no photo, or one that fails to load, is the placeholder', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(items: items));
      // Two have no photo; the other two cannot be fetched in a test.
      expect(find.byIcon(Icons.shopping_basket_rounded), findsNWidgets(4));
      expect(find.text('Pomme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row is read by name and state, not as a picture', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _openPicker(tester, _catalog(items: items));

      expect(find.bySemanticsLabel('Image du produit'), findsNothing);
      expect(find.bySemanticsLabel('Ajouter Pomme'), findsOneWidget);
      expect(find.bySemanticsLabel('Banane, déjà ajouté'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Yaourt nature, archivé dans votre magasin, ouvrir pour restaurer',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('the picture is part of the row’s tap target, nothing more', (
      tester,
    ) async {
      await _openPicker(tester, _catalog(items: items));

      // Tapping the picture of a product to add opens its quick-add sheet…
      await tester.tap(
        find.descendant(of: row('Pomme'), matching: find.byType(ProductImage)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ajouter à mon magasin'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
      await tester.pumpAndSettle();

      // …and the picture of one already in the store does nothing, like its row.
      await tester.tap(
        find.descendant(of: row('Banane'), matching: find.byType(ProductImage)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ajouter à mon magasin'), findsNothing);
    });

    testWidgets('search, order and selection are as before', (tester) async {
      await _openPicker(tester, _catalog(items: items));
      expect(
        [
          for (final name in ['Pomme', 'Tomate', 'Banane', 'Yaourt nature'])
            tester.getTopLeft(find.text(name)).dy,
        ],
        orderedEquals([
          for (final name in ['Pomme', 'Tomate', 'Banane', 'Yaourt nature'])
            tester.getTopLeft(find.text(name)).dy,
        ]..sort()),
      );

      await _type(tester, 'tomate');
      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Pomme'), findsNothing);
      expect(find.byType(ProductImage), findsOneWidget);
      await _quickAdd(tester, 'Tomate', '3');
      expect(find.text('Ajouté'), findsOneWidget);
    });

    testWidgets('only the rows near the screen build a picture', (
      tester,
    ) async {
      final catalog = _catalog(
        items: [
          for (var i = 1; i <= 5700; i++)
            fakeCatalogItem(
              id: i,
              name: 'Produit ${i.toString().padLeft(5, '0')}',
              photo: 'https://res.example/p/$i.jpg',
            ),
        ],
      );
      await _openPicker(tester, catalog, height: 900);

      final built = find.byType(ProductImage).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40)); // a screenful (+ cache) of 5,700
      // …and each is decoded at its slot's size, not at the source's.
      expect(
        tester
            .widgetList<ProductImage>(find.byType(ProductImage))
            .every((i) => i.size == 48),
        isTrue,
      );
    });

    testWidgets('at 1.3× text the pictures stay; at 2× they give the name its '
        'width', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _openPicker(tester, _catalog(items: items));
      expect(find.byType(ProductImage), findsNWidgets(4));
      expect(tester.takeException(), isNull);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(find.byType(ProductImage), findsNothing);
      expect(find.text('Pomme'), findsOneWidget);
      expect(find.text('Ajouté'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
