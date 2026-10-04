import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/app_services.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/quick_add_view_model.dart';
import 'package:grocery_mobile/ui/features/catalog/views/quick_add_sheet.dart';

import 'fakes.dart';

/// Tomate: by the kilo, 500 g minimum, by 100 g, up to 10 kg.
final _weighed = fakeCatalogProduct();

/// Œufs: pieces only.
final _pieces = fakeCatalogProduct(
  id: 5,
  slug: 'oeufs',
  name: 'Œufs',
  category: fakeDairy,
  unit: SaleUnit.piece,
  min: 1,
  step: 1,
  max: null,
);

class _Opened {
  QuickAddOutcome? outcome;
  bool closed = false;
}

FakeStoreProductsRepository _repository({
  List<StoreProduct> existing = const [],
}) => FakeStoreProductsRepository(
  ApiClient(),
  products: existing,
  catalog: [
    for (final p in [_weighed, _pieces])
      CatalogItem(product: p, inMyStore: false, storeProductArchived: false),
  ],
);

/// Opens the quick-add sheet the way the picker does.
Future<_Opened> _openSheet(
  WidgetTester tester,
  FakeStoreProductsRepository repository, {
  CatalogProduct? product,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = ApiClient();
  final opened = _Opened();
  final item = CatalogItem(
    product: product ?? _weighed,
    inMyStore: false,
    storeProductArchived: false,
  );
  await tester.pumpWidget(
    AppServices(
      storeRepository: FakeStoreRepository(api, store: closedStore),
      catalogRepository: FakeCatalogRepository(api),
      storeProductsRepository: repository,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  opened.outcome = await showQuickAddSheet(context, item);
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

Finder _field(String label) => find.widgetWithText(TextField, label);
Finder get _priceField => _field('Prix au kilo (DT)');
Finder get _addButton => find.text('Ajouter à mon magasin');

String _textOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _expandRules(WidgetTester tester) async {
  await tester.tap(find.text('Quantités, stock et disponibilité'));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String title) async {
  await tester.tap(find.widgetWithText(SwitchListTile, title));
  await tester.pumpAndSettle();
}

Future<void> _add(WidgetTester tester) async {
  await tester.tap(_addButton);
  await tester.pumpAndSettle();
}

void main() {
  group('the catalog product is read-only', () {
    testWidgets('shows its name, category, default unit and default rules', (
      tester,
    ) async {
      await _openSheet(tester, _repository());

      expect(find.text('Tomate'), findsOneWidget);
      expect(find.text('Fruits et légumes · Au kilo'), findsOneWidget);
      expect(
        find.text('Catalogue : 500 g, 600 g, 700 g… jusqu’à 10 kg'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Image du produit'), findsOneWidget);
    });

    testWidgets('shows the description when the catalog has one', (
      tester,
    ) async {
      final product = CatalogProduct(
        id: 9,
        slug: 'citron',
        name: 'Citron',
        description: 'Citron jaune de saison',
        category: fakeFruits,
        defaultSaleUnit: SaleUnit.kg,
        allowedSaleUnits: const [SaleUnit.kg, SaleUnit.piece],
        defaultMinQuantity: 500,
        defaultQuantityStep: 100,
      );

      await _openSheet(tester, _repository(), product: product);

      expect(find.text('Citron jaune de saison'), findsOneWidget);
    });

    testWidgets('an image that cannot load falls back to a placeholder', (
      tester,
    ) async {
      final product = CatalogProduct(
        id: 9,
        slug: 'citron',
        name: 'Citron',
        photo: 'https://images.example.test/citron.jpg',
        category: fakeFruits,
        defaultSaleUnit: SaleUnit.kg,
        allowedSaleUnits: const [SaleUnit.kg, SaleUnit.piece],
        defaultMinQuantity: 500,
        defaultQuantityStep: 100,
      );

      await _openSheet(tester, _repository(), product: product);

      expect(tester.takeException(), isNull);
      expect(find.text('Citron'), findsOneWidget);
      expect(find.byIcon(Icons.shopping_basket_rounded), findsOneWidget);
    });

    testWidgets('offers no way to edit name, category, description, image or '
        'slug — only the store’s own settings', (tester) async {
      await _openSheet(tester, _repository());
      await _expandRules(tester);

      final labels = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.decoration!.labelText)
          .toList();

      expect(labels, [
        'Prix au kilo (DT)',
        'Quantité minimale (g)',
        'Par tranche de (g)',
        'Quantité maximale (g) — facultatif',
      ]);
    });
  });

  group('prefill and quick path', () {
    testWidgets('asks for a price first; everything else is tucked away', (
      tester,
    ) async {
      await _openSheet(tester, _repository());

      expect(_priceField, findsOneWidget);
      expect(_textOf(tester, 'Prix au kilo (DT)'), isEmpty);
      expect(find.text('Quantités, stock et disponibilité'), findsOneWidget);
      expect(_field('Quantité minimale (g)'), findsNothing); // collapsed
      expect(find.text('Par tranche de 100 g · minimum 500 g'), findsOneWidget);
    });

    testWidgets('the section holds the catalog defaults', (tester) async {
      await _openSheet(tester, _repository());

      await _expandRules(tester);

      expect(_textOf(tester, 'Quantité minimale (g)'), '500');
      expect(_textOf(tester, 'Par tranche de (g)'), '100');
      expect(_textOf(tester, 'Quantité maximale (g) — facultatif'), '10000');
      expect(
        find.widgetWithText(SwitchListTile, 'Suivre le stock'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Disponible à la vente'),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('typing a price is enough: one tap adds the product', (
      tester,
    ) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);

      await _type(tester, _priceField, '1,8');
      await _add(tester);

      expect(opened.closed, isTrue);
      expect(opened.outcome!.created!.product.slug, 'tomate');
      final sent = repository.lastCreate!;
      expect(sent.productId, _weighed.id);
      expect(sent.priceMillimes, 1800);
      expect(sent.saleUnit, SaleUnit.kg);
      expect(sent.minQuantity, 500);
      expect(sent.quantityStep, 100);
      expect(sent.maxQuantity, 10000);
      expect(sent.trackStock, isFalse);
      expect(sent.isAvailable, isTrue);
      expect(find.text('Ajouter à mon magasin'), findsNothing); // sheet closed
    });

    testWidgets('the keyboard "done" key adds it too', (tester) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);

      await _type(tester, _priceField, '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(opened.closed, isTrue);
      expect(repository.createCalls, 1);
    });

    testWidgets('cancelling closes it and adds nothing', (tester) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(opened.closed, isTrue);
      expect(opened.outcome, isNull);
      expect(repository.createCalls, 0);
    });
  });

  group('price validation', () {
    testWidgets('a missing price is explained and nothing is sent', (
      tester,
    ) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);

      await _add(tester);

      expect(find.text('Le prix est requis.'), findsOneWidget);
      expect(opened.closed, isFalse);
      expect(repository.createCalls, 0);
    });

    for (final (text, message) in [
      ('abc', 'Prix invalide (ex. 1,800).'),
      ('1,2345', 'Prix invalide (ex. 1,800).'),
      ('0', 'Le prix doit être supérieur à 0.'),
      ('10000,001', 'Prix trop élevé (maximum 10 000 DT).'),
    ]) {
      testWidgets('"$text" → $message', (tester) async {
        final repository = _repository();
        await _openSheet(tester, repository);

        await _type(tester, _priceField, text);
        await _add(tester);

        expect(find.text(message), findsOneWidget);
        expect(repository.createCalls, 0);
      });
    }

    testWidgets('the message goes away once the price is fixed', (
      tester,
    ) async {
      await _openSheet(tester, _repository());
      await _add(tester);
      expect(find.text('Le prix est requis.'), findsOneWidget);

      await _type(tester, _priceField, '1,5');

      expect(find.text('Le prix est requis.'), findsNothing);
    });
  });

  group('unit', () {
    testWidgets('a weighed product can be sold by the kilo or by the piece', (
      tester,
    ) async {
      await _openSheet(tester, _repository());

      expect(find.byType(SegmentedButton<SaleUnit>), findsOneWidget);
      expect(find.text('Au kilo'), findsOneWidget);
      expect(find.text('À la pièce'), findsOneWidget);
      expect(find.text('Au litre'), findsNothing); // an unrelated unit
    });

    testWidgets('a piece-only product offers no choice', (tester) async {
      await _openSheet(tester, _repository(), product: _pieces);

      expect(find.byType(SegmentedButton<SaleUnit>), findsNothing);
      expect(_field('Prix à la pièce (DT)'), findsOneWidget);
    });

    testWidgets('switching to pieces adapts the price label and resets the '
        'rules to piece defaults', (tester) async {
      await _openSheet(tester, _repository());
      await _expandRules(tester);

      await tester.tap(find.text('À la pièce'));
      await tester.pumpAndSettle();

      expect(_field('Prix à la pièce (DT)'), findsOneWidget);
      expect(_field('Prix au kilo (DT)'), findsNothing);
      expect(_textOf(tester, 'Quantité minimale (pièces)'), '1');
      expect(_textOf(tester, 'Par tranche de (pièces)'), '1');
      expect(
        _textOf(tester, 'Quantité maximale (pièces) — facultatif'),
        isEmpty,
      );
    });

    testWidgets('the unit chosen is the unit sent', (tester) async {
      final repository = _repository();
      await _openSheet(tester, repository);

      await tester.tap(find.text('À la pièce'));
      await tester.pumpAndSettle();
      await _type(tester, _field('Prix à la pièce (DT)'), '0,5');
      await _add(tester);

      final sent = repository.lastCreate!;
      expect(sent.saleUnit, SaleUnit.piece);
      expect(sent.priceMillimes, 500);
      expect(sent.minQuantity, 1);
      expect(sent.quantityStep, 1);
      expect(sent.noMaximum, isTrue);
    });

    testWidgets('rules are validated for the unit in force', (tester) async {
      final repository = _repository();
      await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1');

      await _type(tester, _field('Par tranche de (g)'), '15');
      await _add(tester);

      expect(find.text('Utilisez un multiple de 10 g.'), findsOneWidget);
      expect(repository.createCalls, 0);
    });
  });

  group('quantity rules', () {
    testWidgets('an invalid rule blocks adding and says why', (tester) async {
      final repository = _repository();
      await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1');

      await _type(tester, _field('Quantité minimale (g)'), '150');
      await _add(tester);

      expect(
        find.text('Doit être un multiple de la tranche (100 g).'),
        findsOneWidget,
      );
      expect(repository.createCalls, 0);
    });

    testWidgets('the section reopens by itself when it holds the error', (
      tester,
    ) async {
      await _openSheet(tester, _repository());
      await _expandRules(tester);
      await _type(tester, _field('Par tranche de (g)'), '15');
      await _type(tester, _priceField, '1');
      await _expandRules(tester); // collapse
      expect(_field('Par tranche de (g)'), findsNothing);

      await _add(tester);

      expect(_field('Par tranche de (g)'), findsOneWidget);
      expect(find.text('Utilisez un multiple de 10 g.'), findsOneWidget);
    });

    testWidgets('edited rules are the ones sent; a blank maximum means none', (
      tester,
    ) async {
      final repository = _repository();
      await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '4,5');

      await _type(tester, _field('Quantité minimale (g)'), '250');
      await _type(tester, _field('Par tranche de (g)'), '250');
      await _type(tester, _field('Quantité maximale (g) — facultatif'), '');
      await _add(tester);

      final sent = repository.lastCreate!;
      expect(sent.minQuantity, 250);
      expect(sent.quantityStep, 250);
      expect(sent.maxQuantity, isNull);
      expect(sent.noMaximum, isTrue);
    });
  });

  group('stock', () {
    testWidgets('has no stock field until tracking is switched on', (
      tester,
    ) async {
      await _openSheet(tester, _repository());
      await _expandRules(tester);
      expect(_field('Stock actuel (g)'), findsNothing);

      await _toggle(tester, 'Suivre le stock');

      expect(_field('Stock actuel (g)'), findsOneWidget);
    });

    testWidgets('an initial stock is sent with tracking on', (tester) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1,8');
      await _toggle(tester, 'Suivre le stock');

      await _type(tester, _field('Stock actuel (g)'), '20000');
      await _add(tester);

      final sent = repository.lastCreate!;
      expect(sent.trackStock, isTrue);
      expect(sent.stockQuantity, 20000);
      final created = opened.outcome!.created!;
      expect(created.trackStock, isTrue);
      expect(created.stockQuantity, 20000);
      expect(created.isOrderable, isTrue);
    });

    testWidgets('without tracking, no stock is sent and availability is just '
        'the owner’s switch', (tester) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);
      await _type(tester, _priceField, '1,8');

      await _add(tester);

      expect(repository.lastCreate!.trackStock, isFalse);
      expect(repository.lastCreate!.stockQuantity, isNull);
      expect(opened.outcome!.created!.stockQuantity, isNull);
      expect(opened.outcome!.created!.isOrderable, isTrue);
    });

    testWidgets('tracking needs a stock — zero counts, blank does not', (
      tester,
    ) async {
      final repository = _repository();
      await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1');
      await _toggle(tester, 'Suivre le stock');

      await _add(tester);

      expect(
        find.text('Indiquez le stock actuel (0 si épuisé).'),
        findsOneWidget,
      );
      expect(repository.createCalls, 0);
    });

    for (final (text, message) in [
      ('-5', 'Entrez un nombre entier (0 ou plus).'),
      ('1.5', 'Entrez un nombre entier (0 ou plus).'),
      ('15', 'Utilisez un multiple de 10 g.'),
    ]) {
      testWidgets('stock "$text" → $message', (tester) async {
        final repository = _repository();
        await _openSheet(tester, repository);
        await _expandRules(tester);
        await _type(tester, _priceField, '1');
        await _toggle(tester, 'Suivre le stock');

        await _type(tester, _field('Stock actuel (g)'), text);
        await _add(tester);

        expect(find.text(message), findsOneWidget);
        expect(repository.createCalls, 0);
      });
    }

    testWidgets('piece stock is counted in pieces', (tester) async {
      final repository = _repository();
      await _openSheet(tester, repository, product: _pieces);
      await _expandRules(tester);
      await _type(tester, _field('Prix à la pièce (DT)'), '0,35');
      await _toggle(tester, 'Suivre le stock');

      await _type(tester, _field('Stock actuel (pièces)'), '12');
      await _add(tester);

      expect(repository.lastCreate!.stockQuantity, 12);
    });

    testWidgets('a stock typed then abandoned is not sent', (tester) async {
      final repository = _repository();
      await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1');
      await _toggle(tester, 'Suivre le stock');
      await _type(tester, _field('Stock actuel (g)'), '5000');
      await _toggle(tester, 'Suivre le stock'); // off again

      await _add(tester);

      expect(repository.lastCreate!.trackStock, isFalse);
      expect(repository.lastCreate!.stockQuantity, isNull);
    });
  });

  group('zero stock', () {
    testWidgets('is explained as it is typed, and the note goes away with '
        'stock', (tester) async {
      await _openSheet(tester, _repository());
      await _expandRules(tester);
      await _toggle(tester, 'Suivre le stock');

      await _type(tester, _field('Stock actuel (g)'), '0');
      await tester.pump();

      expect(find.textContaining('Stock à 0'), findsOneWidget);
      expect(
        find.textContaining('indisponible pour les clients'),
        findsOneWidget,
      );

      await _type(tester, _field('Stock actuel (g)'), '5000');
      await tester.pump();

      expect(find.textContaining('Stock à 0'), findsNothing);
    });

    testWidgets('stock below the minimum order is explained too', (
      tester,
    ) async {
      await _openSheet(tester, _repository());
      await _expandRules(tester);
      await _toggle(tester, 'Suivre le stock');

      await _type(tester, _field('Stock actuel (g)'), '50');
      await tester.pump();

      expect(
        find.textContaining('inférieur à la quantité minimale'),
        findsOneWidget,
      );
    });

    testWidgets('an initial stock of zero is accepted: the product is created '
        'and is unavailable to customers by itself', (tester) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1,8');
      await _toggle(tester, 'Suivre le stock');
      await _type(tester, _field('Stock actuel (g)'), '0');

      await _add(tester);

      // The app did not touch the owner's switch…
      expect(repository.lastCreate!.stockQuantity, 0);
      expect(repository.lastCreate!.isAvailable, isTrue);
      // …the backend's derived availability made the product unorderable.
      final created = opened.outcome!.created!;
      expect(created.isAvailable, isTrue);
      expect(created.isOrderable, isFalse);
      expect(created.unavailabilityReason, UnavailabilityReason.outOfStock);
    });
  });

  group('availability', () {
    testWidgets('can be switched off at creation', (tester) async {
      final repository = _repository();
      final opened = await _openSheet(tester, repository);
      await _expandRules(tester);
      await _type(tester, _priceField, '1,8');

      await _toggle(tester, 'Disponible à la vente');
      await _add(tester);

      expect(repository.lastCreate!.isAvailable, isFalse);
      expect(opened.outcome!.created!.isOrderable, isFalse);
      expect(
        opened.outcome!.created!.unavailabilityReason,
        UnavailabilityReason.ownerDisabled,
      );
    });
  });

  group('duplicate product', () {
    testWidgets('closes as a conflict — no error banner, nothing duplicated', (
      tester,
    ) async {
      final repository = _repository(
        existing: [fakeStoreProduct(id: 40, product: _weighed)],
      );
      final opened = await _openSheet(tester, repository);
      await _type(tester, _priceField, '1,8');

      await _add(tester);

      expect(opened.closed, isTrue);
      expect(opened.outcome!.conflict, isTrue);
      expect(opened.outcome!.created, isNull);
      expect(repository.names, ['Tomate']); // still just the one
    });
  });

  group('API errors', () {
    testWidgets('a server error keeps the sheet and the typed values, with a '
        'retry', (tester) async {
      final repository = _repository()
        ..createError = const ApiException(statusCode: 500);
      final opened = await _openSheet(tester, repository);
      await _type(tester, _priceField, '1,8');

      await _add(tester);

      expect(
        find.text('Impossible d’ajouter le produit. Veuillez réessayer.'),
        findsOneWidget,
      );
      expect(opened.closed, isFalse);
      expect(_textOf(tester, 'Prix au kilo (DT)'), '1,8');

      repository.createError = null;
      await _add(tester);

      expect(opened.closed, isTrue);
      expect(opened.outcome!.created, isNotNull);
      expect(repository.createCalls, 2);
    });

    testWidgets('being offline is explained', (tester) async {
      final repository = _repository()
        ..createError = const NetworkException('offline');
      await _openSheet(tester, repository);
      await _type(tester, _priceField, '1,8');

      await _add(tester);

      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the server refusing the values is explained', (tester) async {
      final repository = _repository()
        ..createError = const ApiException(statusCode: 400);
      await _openSheet(tester, repository);
      await _type(tester, _priceField, '1,8');

      await _add(tester);

      expect(
        find.textContaining('Le serveur a refusé ces valeurs'),
        findsOneWidget,
      );
    });

    testWidgets('the error clears as soon as the owner edits', (tester) async {
      final repository = _repository()
        ..createError = const ApiException(statusCode: 500);
      await _openSheet(tester, repository);
      await _type(tester, _priceField, '1,8');
      await _add(tester);
      expect(find.textContaining('Impossible d’ajouter'), findsOneWidget);

      await _type(tester, _priceField, '1,9');

      expect(find.textContaining('Impossible d’ajouter'), findsNothing);
    });
  });
}
