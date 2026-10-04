import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/store_product.dart';

import 'fakes.dart';

const _openStore = Store(
  id: 10,
  name: 'Menzah Market',
  address: '12 Rue de la Liberté, Tunis',
  isOpen: true,
  ownerId: 1,
);

Future<void> _pumpShell(
  WidgetTester tester, {
  Store store = closedStore,
  List<StoreProduct> Function()? products,
  bool productsFail = false,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: store),
    storeProductsRepository: (api) => FakeStoreProductsRepository(
      api,
      products: products?.call() ?? [],
      fails: productsFail,
    ),
  );
}

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_navLabel(label));
  await tester.pumpAndSettle();
}

void main() {
  group('navigation', () {
    testWidgets('shows only owner areas; Commandes stays hidden until orders '
        'exist', (tester) async {
      await _pumpShell(tester);

      for (final label in ['Accueil', 'Catalogue', 'Magasin']) {
        expect(_navLabel(label), findsOneWidget);
      }
      expect(_navLabel('Commandes'), findsNothing);
      // No customer-side navigation, ever.
      for (final label in ['Recherche', 'Panier', 'Profil', 'Catégories']) {
        expect(_navLabel(label), findsNothing);
      }
      expect(find.byType(NavigationDestination), findsNWidgets(3));
    });
  });

  group('dashboard', () {
    testWidgets('a new store shows its state and the full setup checklist', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.text('Bonjour, Karim'), findsOneWidget);
      expect(find.text('Magasin fermé'), findsOneWidget);
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('Démarrer votre magasin · 0/2'), findsOneWidget);
      expect(find.text('Ajouter des produits'), findsOneWidget);
      expect(find.text('Ouvrir le magasin'), findsOneWidget);
      // Categories belong to the global catalog now: nothing to create.
      expect(find.text('Créer une catégorie'), findsNothing);
    });

    testWidgets('has no analytics, charts or fake numbers', (tester) async {
      await _pumpShell(tester);
      expect(find.textContaining('DT'), findsNothing);
      expect(find.textContaining('Chiffre'), findsNothing);
      expect(find.textContaining('Commandes'), findsNothing);
    });

    testWidgets('counts progress and only lists what is left to do', (
      tester,
    ) async {
      await _pumpShell(tester, products: () => [fakeTomatoes()]);

      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);
      // Done steps are listed without their hint; the open step keeps it.
      expect(find.text('Prix, unité de vente et quantités.'), findsNothing);
      expect(
        find.text('Vos clients pourront alors commander.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('the checklist disappears once setup is complete', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        store: _openStore,
        products: () => [fakeTomatoes()],
      );

      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsOneWidget);
    });

    testWidgets('archived products do not count as a product', (tester) async {
      await _pumpShell(
        tester,
        products: () => [fakeStoreProduct(isArchived: true)],
      );
      expect(find.text('Démarrer votre magasin · 0/2'), findsOneWidget);
    });

    testWidgets('a product the owner switched off still counts as added', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        products: () => [fakeTomatoes(isAvailable: false)],
      );
      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);
    });

    testWidgets('each open step leads to the right place', (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Ajouter des produits'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit'), findsOneWidget); // Catalogue tab

      await _openTab(tester, 'Accueil');
      await tester.tap(find.text('Ouvrir le magasin'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget); // Magasin tab
    });

    testWidgets('updates when the owner finishes the steps elsewhere', (
      tester,
    ) async {
      await _pumpShell(tester, products: () => [fakeTomatoes()]);
      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);

      await _openTab(tester, 'Magasin');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await _openTab(tester, 'Accueil');
      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsWidgets);
    });

    testWidgets('says so, instead of a wrong checklist, when it cannot load', (
      tester,
    ) async {
      await _pumpShell(tester, productsFail: true);

      expect(
        find.textContaining('Impossible de charger la configuration'),
        findsOneWidget,
      );
      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(
        find.text('Magasin fermé'),
        findsOneWidget,
      ); // store info still shown
    });
  });
}
