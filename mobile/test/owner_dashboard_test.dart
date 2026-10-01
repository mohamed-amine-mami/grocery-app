import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/product.dart';
import 'package:grocery_mobile/data/models/store.dart';

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
  List<String> categories = const [],
  List<Product> Function()? products,
  bool categoriesFail = false,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: store),
    categoryRepository: (api) =>
        FakeCategoryRepository(api, names: categories, fails: categoriesFail),
    productRepository: (api) =>
        FakeProductRepository(api, products: products?.call() ?? []),
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
      expect(find.text('Démarrer votre magasin · 0/3'), findsOneWidget);
      expect(find.text('Créer une catégorie'), findsOneWidget);
      expect(find.text('Ajouter un produit'), findsOneWidget);
      expect(find.text('Ouvrir le magasin'), findsOneWidget);
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
      await _pumpShell(
        tester,
        categories: ['Légumes'],
        products: () => [fakeTomatoes(categoryId: 1)],
      );

      expect(find.text('Démarrer votre magasin · 2/3'), findsOneWidget);
      // Done steps are listed without their hint; the open step keeps it.
      expect(find.text('Pour organiser vos produits.'), findsNothing);
      expect(
        find.text('Vos clients pourront alors commander.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    });

    testWidgets('the checklist disappears once setup is complete', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        store: _openStore,
        categories: ['Légumes'],
        products: () => [fakeTomatoes(categoryId: 1)],
      );

      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsOneWidget);
    });

    testWidgets('archived products do not count as a product', (tester) async {
      await _pumpShell(
        tester,
        categories: ['Légumes'],
        products: () => [
          Product(
            id: 1,
            name: 'Ancien',
            saleUnit: fakeEggs().saleUnit,
            priceMillimes: 100,
            minQuantity: 1,
            quantityStep: 1,
            isAvailable: true,
            isArchived: true,
          ),
        ],
      );
      expect(find.text('Démarrer votre magasin · 1/3'), findsOneWidget);
    });

    testWidgets('each open step leads to the right place', (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Ajouter un produit'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit'), findsOneWidget); // Catalogue tab

      await _openTab(tester, 'Accueil');
      await tester.tap(find.text('Ouvrir le magasin'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget); // Magasin tab

      await _openTab(tester, 'Accueil');
      await tester.tap(find.text('Créer une catégorie'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune catégorie'), findsOneWidget); // category manager
    });

    testWidgets('updates when the owner finishes the steps elsewhere', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        categories: ['Légumes'],
        products: () => [fakeTomatoes(categoryId: 1)],
      );
      expect(find.text('Démarrer votre magasin · 2/3'), findsOneWidget);

      await _openTab(tester, 'Magasin');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await _openTab(tester, 'Accueil');
      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsWidgets);
    });

    testWidgets('picks up a category created in the catalogue', (tester) async {
      await _pumpShell(tester);
      expect(find.text('Démarrer votre magasin · 0/3'), findsOneWidget);

      await tester.tap(find.text('Créer une catégorie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter une catégorie').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom de la catégorie'),
        'Fruits',
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      expect(find.text('Démarrer votre magasin · 1/3'), findsOneWidget);
    });

    testWidgets('says so, instead of a wrong checklist, when it cannot load', (
      tester,
    ) async {
      await _pumpShell(tester, categoriesFail: true);

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
