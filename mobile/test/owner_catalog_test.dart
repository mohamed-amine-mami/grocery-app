import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';

import 'fakes.dart';

late FakeProductRepository _products;

Future<void> _pumpCatalog(
  WidgetTester tester, {
  List<String> categories = const [],
  List<Product> Function()? products,
}) async {
  // Tall viewport: the editor is a long form and we don't want to scroll it.
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
    categoryRepository: (api) => FakeCategoryRepository(api, names: categories),
    productRepository: (api) => _products = FakeProductRepository(
      api,
      products: products?.call() ?? [],
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openNewProductEditor(WidgetTester tester) async {
  final empty = find.text('Ajouter un produit');
  await tester.tap(empty.first);
  await tester.pumpAndSettle();
}

void main() {
  group('catalogue list', () {
    testWidgets('has a clean empty state with an add action', (tester) async {
      await _pumpCatalog(tester);

      expect(find.text('Aucun produit'), findsOneWidget);
      expect(find.text('Ajouter un produit'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('groups products by category and shows price and step', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        categories: ['Fruits', 'Légumes'],
        products: () => [
          fakeTomatoes(categoryId: 2), // Légumes (ids follow creation order)
          fakeEggs(), // uncategorized
        ],
      );

      expect(find.text('Légumes · 1'), findsOneWidget);
      expect(find.text('Sans catégorie · 1'), findsOneWidget);
      expect(find.text('Fruits · 1'), findsNothing); // empty groups are hidden
      expect(find.text('Tomates'), findsOneWidget);
      expect(find.text('1,800 DT / kg'), findsOneWidget);
      expect(find.text('Par tranche de 500 g'), findsOneWidget);
      expect(find.text('0,350 DT / pièce'), findsOneWidget);
      expect(find.text('Par tranche de 1 pièce'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('filter chips narrow the list by category', (tester) async {
      await _pumpCatalog(
        tester,
        categories: ['Fruits', 'Légumes'],
        products: () => [
          fakeTomatoes(categoryId: 2),
          fakeEggs(),
          fakeTomatoes(id: 3, categoryId: 1).copyWith(),
        ],
      );
      // Two products share the name in this fixture; filter by chip instead.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Légumes'));
      await tester.pumpAndSettle();
      expect(find.text('Légumes · 1'), findsOneWidget);
      expect(find.text('Fruits · 1'), findsNothing);
      expect(find.text('Sans catégorie · 1'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sans catégorie'));
      await tester.pumpAndSettle();
      expect(find.text('Sans catégorie · 1'), findsOneWidget);
      expect(find.text('Légumes · 1'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Légumes · 1'), findsOneWidget);
      expect(find.text('Sans catégorie · 1'), findsOneWidget);
    });

    testWidgets('a category without products says so instead of a blank page', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        categories: ['Fruits', 'Légumes'],
        products: () => [fakeTomatoes(categoryId: 2)],
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Fruits'));
      await tester.pumpAndSettle();

      expect(find.text('Aucun produit dans cette catégorie.'), findsOneWidget);
      expect(find.text('Tomates'), findsNothing);
    });

    testWidgets('does not show the chips when there are no categories', (
      tester,
    ) async {
      await _pumpCatalog(tester, products: () => [fakeEggs()]);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('the switch makes a product unavailable — with text, not just '
        'color — and keeps it listed', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);
      expect(find.text('Indisponible'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(_products.byName('Tomates').isAvailable, isFalse);
      expect(find.text('Indisponible'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
      expect(find.text('Tomates'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(_products.byName('Tomates').isAvailable, isTrue);
      expect(find.text('Indisponible'), findsNothing);
    });

    testWidgets('opens the category manager from the app bar', (tester) async {
      await _pumpCatalog(tester, categories: ['Fruits']);
      await tester.tap(find.byTooltip('Gérer les catégories'));
      await tester.pumpAndSettle();
      expect(find.text('Fruits'), findsOneWidget);
      expect(find.text('Ajouter une catégorie'), findsOneWidget);
    });
  });

  group('product editor — creating', () {
    testWidgets('explains the category choice when there are no categories', (
      tester,
    ) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);
      expect(
        find.textContaining('Aucune catégorie pour l’instant'),
        findsOneWidget,
      );
    });

    testWidgets('adapts the price label and quantity controls to the unit', (
      tester,
    ) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);

      expect(find.text('Nouveau produit'), findsOneWidget);
      expect(_field('Prix à la pièce (DT)'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '2 pièces'), findsOneWidget);

      await _tap(tester, find.text('Au kilo'));
      expect(_field('Prix au kilo (DT)'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '250 g'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '1 kg'), findsOneWidget);

      await _tap(tester, find.text('Au litre'));
      expect(_field('Prix au litre (DT)'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '250 mL'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '1 L'), findsOneWidget);
    });

    testWidgets('shows a live preview generated from the settings', (
      tester,
    ) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);

      // Pieces by default.
      expect(find.text('Le client pourra commander :'), findsOneWidget);
      expect(find.text('1, 2, 3 pièces…'), findsOneWidget);

      await _tap(tester, find.text('Au kilo'));
      expect(find.text('100 g, 200 g, 300 g…'), findsOneWidget);

      await _tap(tester, find.widgetWithText(ChoiceChip, '250 g'));
      expect(find.text('250 g, 500 g, 750 g…'), findsOneWidget);

      await _tap(tester, find.widgetWithText(ChoiceChip, '500 g'));
      expect(find.text('500 g, 1 kg, 1,5 kg…'), findsOneWidget);

      // Raising the minimum shifts the list.
      await _tap(tester, find.byTooltip('Quantité minimale : augmenter'));
      expect(find.text('1 kg, 1,5 kg, 2 kg…'), findsOneWidget);

      // A maximum closes the list and is named.
      await _tap(tester, find.byType(Switch).last);
      expect(find.textContaining('jusqu’à 10 kg'), findsOneWidget);
    });

    testWidgets('previews the price of the minimum quantity with exact '
        'integer math', (tester) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);
      await _tap(tester, find.text('Au kilo'));
      await _tap(tester, find.widgetWithText(ChoiceChip, '500 g'));
      await tester.enterText(_field('Prix au kilo (DT)'), '1,8');
      await tester.pumpAndSettle();

      expect(find.text('500 g = 0,900 DT · 1,800 DT / kg'), findsOneWidget);
    });

    testWidgets('changing the unit resets the quantity settings', (
      tester,
    ) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);
      await _tap(tester, find.text('Au kilo'));
      await _tap(tester, find.widgetWithText(ChoiceChip, '1 kg'));
      expect(find.text('1 kg, 2 kg, 3 kg…'), findsOneWidget);

      await _tap(tester, find.text('À la pièce'));
      expect(find.text('1, 2, 3 pièces…'), findsOneWidget);
      expect(find.text('1 kg, 2 kg, 3 kg…'), findsNothing);
    });

    testWidgets('keeps the maximum aligned when the step changes', (
      tester,
    ) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);
      await _tap(tester, find.text('Au kilo'));
      await _tap(tester, find.widgetWithText(ChoiceChip, '100 g'));
      await _tap(tester, find.byType(Switch).last); // max = 10 × min = 1 kg
      expect(find.textContaining('jusqu’à 1 kg'), findsOneWidget);

      await _tap(tester, find.widgetWithText(ChoiceChip, '500 g'));
      // min 500 g, max 1 kg — both multiples of the new step.
      expect(find.text('500 g, 1 kg'), findsOneWidget);
    });

    testWidgets('saves a KG product exactly as configured', (tester) async {
      await _pumpCatalog(tester, categories: ['Fruits', 'Légumes']);
      await _openNewProductEditor(tester);

      await _tap(tester, find.text('Au kilo'));
      await tester.enterText(_field('Nom du produit'), '  Tomates ');
      await tester.enterText(_field('Prix au kilo (DT)'), '1,8');
      await _tap(tester, find.widgetWithText(ChoiceChip, '500 g'));
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Légumes').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Ajouter le produit'));

      final input = _products.lastInput!;
      expect(input.name, 'Tomates');
      expect(input.saleUnit, SaleUnit.kg);
      expect(input.priceMillimes, 1800);
      expect(input.minQuantity, 500);
      expect(input.quantityStep, 500);
      expect(input.maxQuantity, isNull);
      expect(input.categoryId, 2);

      // Back on the catalogue with a confirmation and the new product.
      expect(find.text('Produit ajouté.'), findsOneWidget);
      expect(find.text('Tomates'), findsOneWidget);
      expect(find.text('1,800 DT / kg'), findsOneWidget);
    });

    testWidgets('saves an uncategorized PIECE product', (tester) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);
      await tester.enterText(_field('Nom du produit'), 'Œufs');
      await tester.enterText(_field('Prix à la pièce (DT)'), '0,350');
      await _tap(tester, find.text('Ajouter le produit'));

      final input = _products.lastInput!;
      expect(input.saleUnit, SaleUnit.piece);
      expect(input.priceMillimes, 350);
      expect(input.minQuantity, 1);
      expect(input.quantityStep, 1);
      expect(input.categoryId, isNull);
    });

    testWidgets('validates name and price before calling the backend', (
      tester,
    ) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);

      await _tap(tester, find.text('Ajouter le produit'));
      expect(find.text('Le nom du produit est requis.'), findsOneWidget);
      expect(find.text('Le prix est requis.'), findsOneWidget);

      await tester.enterText(_field('Nom du produit'), 'Sel');
      await tester.enterText(_field('Prix à la pièce (DT)'), '1,2345');
      await _tap(tester, find.text('Ajouter le produit'));
      expect(find.text('Prix invalide (ex. 1,800).'), findsOneWidget);

      await tester.enterText(_field('Prix à la pièce (DT)'), '0');
      await _tap(tester, find.text('Ajouter le produit'));
      expect(find.text('Le prix doit être supérieur à 0.'), findsOneWidget);

      expect(_products.lastInput, isNull);
    });

    testWidgets('shows a French error for a duplicate name and stays open', (
      tester,
    ) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(_field('Nom du produit'), 'tomates');
      await tester.enterText(_field('Prix à la pièce (DT)'), '1');
      await _tap(tester, find.text('Ajouter le produit'));

      expect(
        find.text('Un produit avec ce nom existe déjà dans votre catalogue.'),
        findsOneWidget,
      );
      expect(find.text('Nouveau produit'), findsOneWidget);
    });
  });

  group('product editor — editing and archiving', () {
    testWidgets('opens pre-filled from the list', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);
      await tester.tap(find.text('Tomates'));
      await tester.pumpAndSettle();

      expect(find.text('Modifier le produit'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(_field('Nom du produit')).controller!.text,
        'Tomates',
      );
      expect(
        tester
            .widget<TextFormField>(_field('Prix au kilo (DT)'))
            .controller!
            .text,
        '1,800',
      );
      expect(find.text('500 g, 1 kg, 1,5 kg… jusqu’à 10 kg'), findsOneWidget);
      expect(find.text('Supprimer du catalogue'), findsOneWidget);
    });

    testWidgets('saves changes to an existing product', (tester) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes()]);
      await tester.tap(find.text('Tomates'));
      await tester.pumpAndSettle();

      await tester.enterText(_field('Prix au kilo (DT)'), '2,5');
      await _tap(tester, find.text('Enregistrer'));

      expect(_products.lastUpdatedId, 1);
      expect(_products.lastInput!.priceMillimes, 2500);
      // Unit, step and limits are restated unchanged.
      expect(_products.lastInput!.quantityStep, 500);
      expect(_products.lastInput!.maxQuantity, 10000);
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
      expect(find.text('2,500 DT / kg'), findsOneWidget);
    });

    testWidgets('keeps a custom step as a selectable chip', (tester) async {
      await _pumpCatalog(
        tester,
        products: () => [
          fakeEggs().copyWith(),
          Product(
            id: 5,
            name: 'Yaourts',
            saleUnit: SaleUnit.piece,
            priceMillimes: 500,
            minQuantity: 4,
            quantityStep: 4,
            isAvailable: true,
          ),
        ],
      );
      await tester.tap(find.text('Yaourts'));
      await tester.pumpAndSettle();

      // 4 is not among the 1/2/5/10 presets but must still show, selected.
      final chip = find.widgetWithText(ChoiceChip, '4 pièces');
      expect(chip, findsOneWidget);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(find.text('4, 8, 12 pièces…'), findsOneWidget);
    });

    testWidgets('a new product has no delete button', (tester) async {
      await _pumpCatalog(tester);
      await _openNewProductEditor(tester);
      expect(find.text('Supprimer du catalogue'), findsNothing);
    });

    testWidgets('deleting asks first, then archives and hides the product', (
      tester,
    ) async {
      await _pumpCatalog(tester, products: () => [fakeTomatoes(), fakeEggs()]);
      await tester.tap(find.text('Tomates'));
      await tester.pumpAndSettle();

      await _tap(tester, find.text('Supprimer du catalogue'));
      expect(find.text('Supprimer ce produit du catalogue ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(_products.byName('Tomates').isArchived, isFalse);

      await _tap(tester, find.text('Supprimer du catalogue'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(_products.byName('Tomates').isArchived, isTrue);
      expect(find.text('Produit supprimé du catalogue.'), findsOneWidget);
      expect(find.text('Tomates'), findsNothing);
      expect(find.text('Œufs'), findsOneWidget);
    });
  });
}
