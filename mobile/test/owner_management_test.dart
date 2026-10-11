import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/store_product.dart';

import 'fakes.dart';

late FakeStoreRepository _stores;

Future<void> _pumpOwnerShell(
  WidgetTester tester, {
  List<StoreProduct> products = const [],
  bool productsFail = false,
}) async {
  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) =>
        _stores = FakeStoreRepository(api, store: closedStore),
    storeProductsRepository: (api) => FakeStoreProductsRepository(
      api,
      products: products,
      fails: productsFail,
    ),
  );
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('owner navigation', () {
    testWidgets('offers Accueil, Commandes, Catalogue and Magasin', (
      tester,
    ) async {
      await _pumpOwnerShell(tester);

      for (final label in ['Accueil', 'Commandes', 'Catalogue', 'Magasin']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Bonjour, Karim'), findsOneWidget);
    });
  });

  group('magasin', () {
    testWidgets('shows the store details and starts closed', (tester) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      expect(find.text('Magasin fermé'), findsOneWidget);
      expect(
        find.text('Le magasin n’accepte pas de commandes pour le moment.'),
        findsOneWidget,
      );
      expect(find.text('Menzah Market'), findsOneWidget); // name field
      expect(find.text('12 Rue de la Liberté, Tunis'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('the switch opens and closes the store', (tester) async {
      await _pumpOwnerShell(tester, products: [fakeTomatoes()]);
      await _openTab(tester, 'Magasin');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Magasin ouvert'), findsOneWidget);
      expect(_stores.store!.isOpen, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Magasin fermé'), findsOneWidget);
      expect(_stores.store!.isOpen, isFalse);
    });

    testWidgets('the new state also shows on the Accueil tab', (tester) async {
      await _pumpOwnerShell(tester, products: [fakeTomatoes()]);
      await _openTab(tester, 'Magasin');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await _openTab(tester, 'Accueil');
      expect(find.text('Magasin ouvert'), findsOneWidget);
    });

    testWidgets('saves edited details', (tester) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du magasin'),
        'Menzah Fresh',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '36.8',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '10.18',
      );
      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(_stores.lastUpdate, {
        'name': 'Menzah Fresh',
        'address': '12 Rue de la Liberté, Tunis',
        'description': '',
        'latitude': 36.8,
        'longitude': 10.18,
      });
      expect(find.text('Modifications enregistrées.'), findsOneWidget);
    });

    testWidgets('does not save an invalid form', (tester) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Adresse du magasin'),
        '',
      );
      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.text("L'adresse du magasin est requise."), findsOneWidget);
      expect(_stores.lastUpdate, isNull);
    });

    testWidgets('signs out from the Magasin tab', (tester) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();

      expect(find.text('Connexion'), findsOneWidget);
    });
  });

  group('opening a store with nothing to order', () {
    const warning = 'Ouvrir sans produit disponible ?';

    testWidgets('asks first; "Annuler" leaves the store closed', (
      tester,
    ) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsOneWidget);
      expect(
        find.textContaining('vos clients ne pourront pas encore commander'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsNothing);
      expect(_stores.store!.isOpen, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('"Ouvrir quand même" opens it: a warning, not a block', (
      tester,
    ) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ouvrir quand même'));
      await tester.pumpAndSettle();

      expect(_stores.store!.isOpen, isTrue);
      expect(find.text('Magasin ouvert'), findsOneWidget);
    });

    testWidgets('products that are all switched off or out of stock still '
        'warn', (tester) async {
      await _pumpOwnerShell(
        tester,
        products: [
          fakeTomatoes(isAvailable: false),
          fakeStoreProduct(id: 2, trackStock: true, stockQuantity: 0),
        ],
      );
      await _openTab(tester, 'Magasin');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
    });

    testWidgets('one orderable product: no warning', (tester) async {
      await _pumpOwnerShell(tester, products: [fakeTomatoes()]);
      await _openTab(tester, 'Magasin');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsNothing);
      expect(_stores.store!.isOpen, isTrue);
    });

    testWidgets('closing the store never asks', (tester) async {
      await _pumpOwnerShell(tester, products: [fakeTomatoes()]);
      await _openTab(tester, 'Magasin');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(warning), findsNothing);
      expect(_stores.store!.isOpen, isFalse);
    });

    testWidgets('if the products cannot be loaded, the store just opens', (
      tester,
    ) async {
      await _pumpOwnerShell(tester, productsFail: true);
      await _openTab(tester, 'Magasin');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsNothing);
      expect(_stores.store!.isOpen, isTrue);
    });

    testWidgets('the dialog fits at 1.6× text on a small phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');
      // The screen under the dialog may itself overflow at this size and text
      // scale (it did before this change); this test is about the dialog.
      tester.takeException();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Ouvrir quand même'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Both actions can be reached on the screen.
      for (final label in ['Annuler', 'Ouvrir quand même']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(320), reason: label);
      }
    });
  });
}
