import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/app_services.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/features/catalog/views/store_product_editor_view.dart';

import 'fakes.dart';

/// Tomate, with a description: sold by the kilo, 500 g minimum, by 500 g.
final _tomato = CatalogProduct(
  id: 1,
  slug: 'tomate',
  name: 'Tomate',
  description: 'Tomates rondes de saison.',
  category: fakeFruits,
  defaultSaleUnit: SaleUnit.kg,
  allowedSaleUnits: const [SaleUnit.kg, SaleUnit.piece],
  defaultMinQuantity: 500,
  defaultQuantityStep: 100,
  defaultMaxQuantity: 10000,
);

StoreProduct _tomatoes({
  bool trackStock = false,
  int? stockQuantity,
  bool isAvailable = true,
  bool isArchived = false,
}) => fakeStoreProduct(
  id: 1,
  product: _tomato,
  trackStock: trackStock,
  stockQuantity: stockQuantity,
  isAvailable: isAvailable,
  isArchived: isArchived,
);

class _Opened {
  String? message;
  bool closed = false;
}

late FakeStoreProductsRepository _store;

/// Opens the editor the way the Catalogue tab does: pushed on a route.
Future<_Opened> _openEditor(WidgetTester tester, StoreProduct product) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = ApiClient();
  final opened = _Opened();
  _store = FakeStoreProductsRepository(api, products: [product]);
  await tester.pumpWidget(
    AppServices(
      storeRepository: FakeStoreRepository(api, store: closedStore),
      catalogRepository: FakeCatalogRepository(api),
      storeProductsRepository: _store,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  opened.message = await openStoreProductEditor(
                    context,
                    product,
                  );
                  opened.closed = true;
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return opened;
}

/// The Catalogue tab, signed in as an owner whose store sells [products].
Future<void> _pumpCatalog(
  WidgetTester tester,
  List<StoreProduct> products,
) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
    catalogRepository: (api) => FakeCatalogRepository(api),
    storeProductsRepository: (api) =>
        _store = FakeStoreProductsRepository(api, products: products),
  );
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Catalogue'),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);
Finder get _priceField => _field('Prix au kilo (DT)');
Finder get _saveButton => find.widgetWithText(ElevatedButton, 'Enregistrer');

String _textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) => _tap(tester, _saveButton);

Finder _switch(String title) => find.widgetWithText(SwitchListTile, title);

bool _isOn(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(_switch(title)).value;

void main() {
  group('global product — read-only', () {
    testWidgets('shows the catalog name, category and description as text', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      expect(find.text('Catalogue — lecture seule'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Fruits et légumes'), findsOneWidget);
      expect(find.text('Tomates rondes de saison.'), findsOneWidget);
      expect(find.byType(Image), findsNothing); // no photo: the placeholder
      expect(find.byIcon(Icons.shopping_basket_rounded), findsOneWidget);
    });

    testWidgets('offers no way to edit it: only store fields are inputs', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      // price, minimum, step, maximum — nothing for name, category, etc.
      expect(find.byType(TextField), findsNWidgets(4));
      for (final label in [
        'Nom',
        'Catégorie',
        'Description',
        'Photo',
        'Image',
        'Identifiant',
      ]) {
        expect(find.widgetWithText(TextField, label), findsNothing);
      }
      expect(find.text('Votre magasin'), findsOneWidget);
    });

    testWidgets('saving never sends a global field', (tester) async {
      await _openEditor(tester, _tomatoes());

      await _type(tester, _priceField, '2');
      await _save(tester);

      final keys = _store.lastUpdate!.toJson().keys;
      expect(keys, ['priceMillimes']);
    });
  });

  group('switch hints', () {
    testWidgets('are secondary text, not the theme\'s strong body style', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      for (final hint in [
        'Désactivé : le stock ne décide pas de la disponibilité.',
        'Votre interrupteur, indépendant du stock.',
      ]) {
        final style = tester.widget<Text>(find.text(hint)).style!;
        expect(style.fontWeight, FontWeight.w400, reason: hint);
      }
    });
  });

  group('price', () {
    testWidgets('starts from the saved price and saves the new one', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes());
      expect(_textOf(tester, _priceField), '1,800');

      await _type(tester, _priceField, '2,5');
      await _save(tester);

      expect(_store.lastUpdate!.toJson(), {'priceMillimes': 2500});
      expect(opened.closed, isTrue);
      expect(opened.message, 'Modifications enregistrées.');
    });

    testWidgets('Enregistrer is disabled until something changes', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());
      ElevatedButton button() => tester.widget<ElevatedButton>(_saveButton);

      expect(button().onPressed, isNull);

      await _type(tester, _priceField, '2');
      expect(button().onPressed, isNotNull);

      await _type(tester, _priceField, '1,8'); // back to what it was
      expect(button().onPressed, isNull);
    });

    testWidgets('an invalid price is explained and nothing is sent', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes());

      await _type(tester, _priceField, '');
      await _save(tester);
      expect(find.text('Le prix est requis.'), findsOneWidget);

      await _type(tester, _priceField, '0');
      await _save(tester);
      expect(find.text('Le prix doit être supérieur à 0.'), findsOneWidget);

      await _type(tester, _priceField, 'abc');
      await _save(tester);
      expect(find.text('Prix invalide (ex. 1,800).'), findsOneWidget);

      expect(_store.updateCalls, 0);
      expect(opened.closed, isFalse);
    });
  });

  group('sale unit', () {
    testWidgets('a weighed product can switch between kilo and piece', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      expect(find.byType(SegmentedButton<SaleUnit>), findsOneWidget);
      expect(find.text('Au kilo'), findsOneWidget);
      expect(find.text('À la pièce'), findsOneWidget);
      expect(find.text('Au litre'), findsNothing); // arbitrary units: never
    });

    testWidgets('a piece-only product has no unit selector', (tester) async {
      await _openEditor(tester, fakeEggs());

      expect(find.byType(SegmentedButton<SaleUnit>), findsNothing);
      expect(find.text('Vendu à la pièce'), findsOneWidget);
    });

    testWidgets('switching unit resets rules and price, then saves them', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes());

      await _tap(tester, find.text('À la pièce'));

      expect(_textOf(tester, _field('Prix à la pièce (DT)')), isEmpty);
      expect(_textOf(tester, _field('Quantité minimale (pièces)')), '1');
      expect(_textOf(tester, _field('Par tranche de (pièces)')), '1');
      expect(
        _textOf(tester, _field('Quantité maximale (pièces) — facultatif')),
        isEmpty,
      );

      // The new unit needs its own price first.
      await _save(tester);
      expect(find.text('Le prix est requis.'), findsOneWidget);
      expect(_store.updateCalls, 0);

      await _type(tester, _field('Prix à la pièce (DT)'), '0,4');
      await _save(tester);

      expect(_store.lastUpdate!.toJson(), {
        'priceMillimes': 400,
        'saleUnit': 'PIECE',
        'minQuantity': 1,
        'quantityStep': 1,
        'maxQuantity': null,
      });
      expect(opened.closed, isTrue);
    });
  });

  group('quantity rules', () {
    testWidgets('minimum, step and maximum can be edited', (tester) async {
      await _openEditor(tester, _tomatoes());
      expect(_textOf(tester, _field('Quantité minimale (g)')), '500');
      expect(_textOf(tester, _field('Par tranche de (g)')), '500');
      expect(
        _textOf(tester, _field('Quantité maximale (g) — facultatif')),
        '10000',
      );

      await _type(tester, _field('Quantité minimale (g)'), '200');
      await _type(tester, _field('Par tranche de (g)'), '100');
      await _type(tester, _field('Quantité maximale (g) — facultatif'), '5000');
      await _save(tester);

      expect(_store.lastUpdate!.toJson(), {
        'minQuantity': 200,
        'quantityStep': 100,
        'maxQuantity': 5000,
      });
    });

    testWidgets('a blank maximum means none, sent as an explicit null', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      await _type(tester, _field('Quantité maximale (g) — facultatif'), '');
      await _save(tester);

      final json = _store.lastUpdate!.toJson();
      expect(json.containsKey('maxQuantity'), isTrue);
      expect(json['maxQuantity'], isNull);
    });

    testWidgets('invalid rules are explained, with the shared messages', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      await _type(tester, _field('Par tranche de (g)'), '155');
      await _save(tester);
      expect(find.text('Utilisez un multiple de 10 g.'), findsOneWidget);

      await _type(tester, _field('Par tranche de (g)'), '300');
      await _save(tester);
      expect(
        find.text('Doit être un multiple de la tranche (300 g).'),
        findsWidgets, // the minimum and the maximum
      );
      expect(_store.updateCalls, 0);
    });
  });

  group('stock', () {
    testWidgets('tracking is off by default and hides the stock field', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      expect(_isOn(tester, 'Suivre le stock'), isFalse);
      expect(find.textContaining('Stock actuel'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(4));
      expect(
        find.text('Désactivé : le stock ne décide pas de la disponibilité.'),
        findsOneWidget,
      );
    });

    testWidgets('tracked stock shows "Stock actuel" with quantity and unit', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      expect(_isOn(tester, 'Suivre le stock'), isTrue);
      expect(find.text('Stock actuel : 20 kg'), findsOneWidget);
      expect(_textOf(tester, _field('Modifier le stock (g)')), '20000');
    });

    testWidgets('turning tracking on asks for a stock and saves both', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes());

      await _tap(tester, _switch('Suivre le stock'));
      expect(_field('Stock actuel (g)'), findsOneWidget);

      await _save(tester);
      expect(
        find.text('Indiquez le stock actuel (0 si épuisé).'),
        findsOneWidget,
      );
      expect(_store.updateCalls, 0);

      await _type(tester, _field('Stock actuel (g)'), '8000');
      await _save(tester);

      expect(_store.lastUpdate!.toJson(), {
        'trackStock': true,
        'stockQuantity': 8000,
        'expectedStockQuantity': null,
      });
    });

    testWidgets('turning tracking off hides the field and drops the stock', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      await _tap(tester, _switch('Suivre le stock'));
      expect(find.textContaining('Modifier le stock'), findsNothing);
      await _save(tester);

      expect(_store.lastUpdate!.toJson(), {
        'trackStock': false,
        'expectedStockQuantity': 20000,
      });
    });

    testWidgets('the stock is validated for its unit', (tester) async {
      await _openEditor(
        tester,
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      await _type(tester, _field('Modifier le stock (g)'), '125');
      await _save(tester);
      expect(find.text('Utilisez un multiple de 10 g.'), findsOneWidget);

      await _type(tester, _field('Modifier le stock (g)'), '-3');
      await _save(tester);
      expect(find.text('Entrez un nombre entier (0 ou plus).'), findsOneWidget);
      expect(_store.updateCalls, 0);
    });

    testWidgets('a new count is sent with the stock the screen loaded', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      await _type(tester, _field('Modifier le stock (g)'), '12000');
      await _save(tester);

      expect(_store.lastUpdate!.toJson(), {
        'stockQuantity': 12000,
        'expectedStockQuantity': 20000,
      });
    });
  });

  group('zero stock', () {
    testWidgets('a backend out-of-stock product says "Rupture de stock" and '
        'why, with the owner switch untouched', (tester) async {
      await _openEditor(tester, _tomatoes(trackStock: true, stockQuantity: 0));

      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(find.textContaining('tant que le stock est à 0'), findsOneWidget);
      expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsOneWidget);
      expect(find.text('Stock actuel : 0 g'), findsOneWidget);
      // The owner's own setting is exactly what it was.
      expect(_isOn(tester, 'Disponible à la vente'), isTrue);
    });

    testWidgets('typing 0 explains it; after saving the backend says so', (
      tester,
    ) async {
      await _pumpCatalog(tester, [
        _tomatoes(trackStock: true, stockQuantity: 20000),
      ]);
      await _tap(tester, find.text('Tomate'));
      expect(find.text('Disponible pour les clients'), findsOneWidget);

      await _type(tester, _field('Modifier le stock (g)'), '0');
      expect(
        find.textContaining('Stock à 0 : le produit sera indisponible'),
        findsOneWidget,
      );
      await _save(tester);

      // Back on the list: unorderable, but the owner switch is still on.
      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(_store.availabilityCalls, 0);
      expect(_store.byName('Tomate').isAvailable, isTrue);

      await _tap(tester, find.text('Tomate'));
      expect(find.text('Rupture de stock'), findsOneWidget);
      expect(_isOn(tester, 'Disponible à la vente'), isTrue);
    });

    testWidgets('adding stock again lets the backend make it orderable', (
      tester,
    ) async {
      await _pumpCatalog(tester, [
        _tomatoes(trackStock: true, stockQuantity: 0),
      ]);
      await _tap(tester, find.text('Tomate'));

      await _type(tester, _field('Modifier le stock (g)'), '5000');
      await _save(tester);

      expect(find.text('Indisponible'), findsNothing);
      await _tap(tester, find.text('Tomate'));
      expect(find.text('Disponible pour les clients'), findsOneWidget);
      expect(find.text('Rupture de stock'), findsNothing);
    });

    testWidgets('without stock tracking, zero is not a thing', (tester) async {
      await _openEditor(tester, _tomatoes());

      expect(find.text('Rupture de stock'), findsNothing);
      expect(find.text('Disponible pour les clients'), findsOneWidget);
    });
  });

  group('availability', () {
    testWidgets('the owner switch is saved and told apart from stock', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes());

      await _tap(tester, _switch('Disponible à la vente'));
      await _save(tester);

      expect(_store.availabilityCalls, 1);
      expect(_store.updateCalls, 0);
      expect(_store.byName('Tomate').isAvailable, isFalse);
      expect(opened.closed, isTrue);
    });

    testWidgets('a product the owner disabled says so, in words', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes(isAvailable: false));

      expect(find.text('Désactivé par vous'), findsOneWidget);
      expect(find.byIcon(Icons.toggle_off_outlined), findsOneWidget);
      expect(find.text('Rupture de stock'), findsNothing);
      expect(_isOn(tester, 'Disponible à la vente'), isFalse);
    });

    testWidgets('stock below the minimum is its own explained state', (
      tester,
    ) async {
      await _openEditor(
        tester,
        _tomatoes(trackStock: true, stockQuantity: 100),
      );

      expect(find.text('Stock insuffisant'), findsOneWidget);
      expect(find.text('Rupture de stock'), findsNothing);
    });
  });

  group('archive', () {
    testWidgets('asks first, and cancelling changes nothing', (tester) async {
      final opened = await _openEditor(tester, _tomatoes());

      await _tap(tester, find.text('Archiver ce produit'));
      expect(find.text('Archiver ce produit ?'), findsOneWidget);
      expect(find.textContaining('Vous pourrez le restaurer'), findsOneWidget);

      await _tap(tester, find.text('Annuler'));

      expect(_store.archiveCalls, 0);
      expect(opened.closed, isFalse);
    });

    testWidgets('confirming archives it and closes the editor', (tester) async {
      final opened = await _openEditor(tester, _tomatoes());

      await _tap(tester, find.text('Archiver ce produit'));
      await _tap(tester, find.widgetWithText(TextButton, 'Archiver'));

      expect(_store.archiveCalls, 1);
      expect(_store.byName('Tomate').isArchived, isTrue);
      expect(opened.closed, isTrue);
      expect(opened.message, 'Tomate archivé.');
    });

    testWidgets('an archive failure keeps the editor open with a message', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes());
      _store.archiveError = const NetworkException('offline');

      await _tap(tester, find.text('Archiver ce produit'));
      await _tap(tester, find.widgetWithText(TextButton, 'Archiver'));

      expect(opened.closed, isFalse);
      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('from the Catalogue, the archived product leaves the list', (
      tester,
    ) async {
      await _pumpCatalog(tester, [_tomatoes(), fakeEggs()]);

      await _tap(tester, find.text('Tomate'));
      await _tap(tester, find.text('Archiver ce produit'));
      await _tap(tester, find.widgetWithText(TextButton, 'Archiver'));

      expect(find.text('Tomate archivé.'), findsOneWidget);
      expect(find.text('Tomate'), findsNothing);
      expect(find.text('Œufs'), findsOneWidget);
    });
  });

  group('restore', () {
    testWidgets('an archived product is shown as archived and read-only', (
      tester,
    ) async {
      await _openEditor(tester, _tomatoes(isArchived: true));

      expect(find.text('Produit archivé'), findsOneWidget);
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('Restaurer ce produit'), findsOneWidget);
      expect(find.text('Enregistrer'), findsNothing);
      expect(find.text('Archiver ce produit'), findsNothing);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
      expect(
        tester.widget<SwitchListTile>(_switch('Suivre le stock')).onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(_switch('Disponible à la vente'))
            .onChanged,
        isNull,
      );
    });

    testWidgets('restoring brings back the same product and unlocks it', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes(isArchived: true));

      await _tap(tester, find.text('Restaurer ce produit'));

      expect(_store.restoreCalls, 1);
      expect(_store.createCalls, 0); // never a new store product
      expect(_store.byName('Tomate').id, 1);
      expect(_store.byName('Tomate').isArchived, isFalse);
      expect(find.text('Tomate restauré.'), findsOneWidget);
      expect(find.text('Produit archivé'), findsNothing);
      expect(find.text('Enregistrer'), findsOneWidget);
      expect(find.text('Archiver ce produit'), findsOneWidget);
      expect(_textOf(tester, _priceField), '1,800'); // as it was left
      expect(opened.closed, isFalse); // stays open, now editable
    });

    testWidgets('a restore failure keeps it archived', (tester) async {
      await _openEditor(tester, _tomatoes(isArchived: true));
      _store.restoreError = const ApiException(statusCode: 500, message: 'x');

      await _tap(tester, find.text('Restaurer ce produit'));

      expect(
        find.text('Impossible de restaurer ce produit. Veuillez réessayer.'),
        findsOneWidget,
      );
      expect(find.text('Produit archivé'), findsOneWidget);

      _store.restoreError = null;
      await _tap(tester, find.text('Restaurer ce produit'));
      expect(find.text('Produit archivé'), findsNothing);
    });
  });

  group('API errors keep the form', () {
    testWidgets('a refusal keeps what was typed, and retrying works', (
      tester,
    ) async {
      final opened = await _openEditor(tester, _tomatoes());
      _store.updateError = const ApiException(statusCode: 400, message: 'bad');

      await _type(tester, _priceField, '2,5');
      await _type(tester, _field('Par tranche de (g)'), '100');
      await _save(tester);

      expect(
        find.textContaining('Le serveur a refusé ces valeurs'),
        findsOneWidget,
      );
      expect(_textOf(tester, _priceField), '2,5');
      expect(_textOf(tester, _field('Par tranche de (g)')), '100');
      expect(opened.closed, isFalse);

      _store.updateError = null;
      await _save(tester);
      expect(opened.closed, isTrue);
      expect(_store.lastUpdate!.priceMillimes, 2500);
    });

    testWidgets('offline and server errors are told apart', (tester) async {
      await _openEditor(tester, _tomatoes());
      await _type(tester, _priceField, '2');

      _store.updateError = const NetworkException('offline');
      await _save(tester);
      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion.',
        ),
        findsOneWidget,
      );

      _store.updateError = const ApiException(statusCode: 500, message: 'x');
      await _save(tester);
      expect(
        find.text(
          'Impossible d’enregistrer les modifications. Veuillez réessayer.',
        ),
        findsOneWidget,
      );
      expect(_textOf(tester, _priceField), '2');
    });

    testWidgets('editing clears the error', (tester) async {
      await _openEditor(tester, _tomatoes());
      _store.updateError = const NetworkException('offline');
      await _type(tester, _priceField, '2');
      await _save(tester);

      await _type(tester, _priceField, '2,2');

      expect(find.textContaining('Impossible de contacter'), findsNothing);
    });
  });

  group('stock changed concurrently', () {
    Future<_Opened> openWithConflict(WidgetTester tester) async {
      final opened = await _openEditor(
        tester,
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );
      await _type(tester, _priceField, '2');
      await _type(tester, _field('Modifier le stock (g)'), '15000');
      _store.changeStockExternally(1, 17000); // an order came in
      await _save(tester);
      return opened;
    }

    testWidgets('explains it and keeps everything the owner typed', (
      tester,
    ) async {
      final opened = await openWithConflict(tester);

      expect(
        find.textContaining(
          'Le stock a changé entre-temps : il est maintenant de 17 kg.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('n’ont pas été enregistrées'), findsOneWidget);
      expect(find.text('Stock actuel : 17 kg'), findsOneWidget);
      expect(_textOf(tester, _priceField), '2');
      expect(_textOf(tester, _field('Modifier le stock (g)')), '15000');
      expect(opened.closed, isFalse);
      expect(_store.byName('Tomate').priceMillimes, 1800); // nothing applied
    });

    testWidgets('lets the owner take the current stock', (tester) async {
      await openWithConflict(tester);

      await _tap(tester, find.text('Utiliser le stock actuel (17 kg)'));

      expect(_textOf(tester, _field('Modifier le stock (g)')), '17000');
      expect(_textOf(tester, _priceField), '2'); // the rest is kept
    });

    testWidgets('saving again then succeeds', (tester) async {
      final opened = await openWithConflict(tester);

      await _save(tester);

      expect(opened.closed, isTrue);
      expect(opened.message, 'Modifications enregistrées.');
      expect(_store.lastUpdate!.stock!.expectedStockQuantity, 17000);
      expect(_store.byName('Tomate').stockQuantity, 15000);
      expect(_store.byName('Tomate').priceMillimes, 2000);
    });

    testWidgets('the banner goes away on the next attempt', (tester) async {
      await openWithConflict(tester);
      _store.updateError = const NetworkException('offline');

      await _save(tester);

      expect(find.textContaining('Le stock a changé'), findsNothing);
      expect(find.textContaining('Impossible de contacter'), findsOneWidget);
    });
  });

  group('integration with the Catalogue', () {
    testWidgets('tapping a row opens its editor; the switch does not', (
      tester,
    ) async {
      await _pumpCatalog(tester, [_tomatoes()]);

      await _tap(tester, find.byType(Switch));
      expect(find.text('Votre magasin'), findsNothing);
      expect(_store.availabilityCalls, 1);

      await _tap(tester, find.text('Tomate'));
      expect(find.text('Votre magasin'), findsOneWidget);
    });

    testWidgets('a saved change shows in the list, with a confirmation', (
      tester,
    ) async {
      await _pumpCatalog(tester, [_tomatoes()]);
      expect(find.text('1,800 DT / kg'), findsOneWidget);

      await _tap(tester, find.text('Tomate'));
      await _type(tester, _priceField, '2,5');
      await _type(tester, _field('Par tranche de (g)'), '100');
      await _save(tester);

      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      expect(find.text('2,500 DT / kg'), findsOneWidget);
      expect(find.text('Par tranche de 100 g'), findsOneWidget);
      expect(find.text('1,800 DT / kg'), findsNothing);
    });

    testWidgets('leaving the editor without saving changes nothing', (
      tester,
    ) async {
      await _pumpCatalog(tester, [_tomatoes()]);

      await _tap(tester, find.text('Tomate'));
      await _type(tester, _priceField, '9');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('1,800 DT / kg'), findsOneWidget);
      expect(_store.updateCalls, 0);
    });
  });
}
