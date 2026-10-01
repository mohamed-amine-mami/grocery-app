import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

late FakeStoreRepository _stores;
late FakeCategoryRepository _categories;

Future<void> _pumpOwnerShell(
  WidgetTester tester, {
  List<String> categoryNames = const [],
}) async {
  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) =>
        _stores = FakeStoreRepository(api, store: closedStore),
    categoryRepository: (api) =>
        _categories = FakeCategoryRepository(api, names: categoryNames),
  );
}

/// Categories are managed from the Catalogue tab's app bar.
Future<void> _openCategories(WidgetTester tester) async {
  await _openTab(tester, 'Catalogue');
  await tester.tap(find.byTooltip('Gérer les catégories'));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('owner navigation', () {
    testWidgets('offers Accueil, Catalogue and Magasin — no orders tab yet', (
      tester,
    ) async {
      await _pumpOwnerShell(tester);

      for (final label in ['Accueil', 'Catalogue', 'Magasin']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Commandes'), findsNothing);
      expect(find.text('Bonjour, Karim'), findsOneWidget);
    });
  });

  group('catégories', () {
    testWidgets('shows a clean empty state with an add action', (tester) async {
      await _pumpOwnerShell(tester);
      await _openCategories(tester);

      expect(find.text('Aucune catégorie'), findsOneWidget);
      expect(find.text('Ajouter une catégorie'), findsOneWidget);
    });

    testWidgets('lists categories sorted by name', (tester) async {
      await _pumpOwnerShell(tester, categoryNames: ['Boissons', 'Épicerie']);
      await _openCategories(tester);

      expect(find.text('Aucune catégorie'), findsNothing);
      expect(find.text('Boissons'), findsOneWidget);
      expect(find.text('Épicerie'), findsOneWidget);
    });

    testWidgets('adds a category from the empty state', (tester) async {
      await _pumpOwnerShell(tester);
      await _openCategories(tester);

      await tester.tap(find.text('Ajouter une catégorie'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom de la catégorie'),
        '  Produits laitiers ',
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();

      expect(_categories.names, ['Produits laitiers']);
      expect(find.text('Produits laitiers'), findsOneWidget);
      expect(find.text('Aucune catégorie'), findsNothing);
    });

    testWidgets('validates the name before calling the backend', (
      tester,
    ) async {
      await _pumpOwnerShell(tester);
      await _openCategories(tester);

      await tester.tap(find.text('Ajouter une catégorie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Le nom de la catégorie est requis.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom de la catégorie'),
        'x' * 51,
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le nom ne doit pas dépasser 50 caractères.'),
        findsOneWidget,
      );
      expect(_categories.names, isEmpty);
    });

    testWidgets('keeps the dialog open and explains a duplicate name', (
      tester,
    ) async {
      await _pumpOwnerShell(tester, categoryNames: ['Boissons']);
      await _openCategories(tester);

      await tester.tap(find.text('Ajouter une catégorie'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom de la catégorie'),
        'boissons',
      );
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();

      expect(
        find.text('Une catégorie avec ce nom existe déjà.'),
        findsOneWidget,
      );
      expect(find.text('Nouvelle catégorie'), findsOneWidget);
      expect(_categories.names, ['Boissons']);
    });

    testWidgets('renames a category', (tester) async {
      await _pumpOwnerShell(tester, categoryNames: ['Boissons']);
      await _openCategories(tester);

      await tester.tap(find.byTooltip('Renommer « Boissons »'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Nom de la catégorie');
      expect(tester.widget<TextFormField>(field).controller!.text, 'Boissons');
      await tester.enterText(field, 'Jus et sodas');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(_categories.names, ['Jus et sodas']);
      expect(find.text('Jus et sodas'), findsOneWidget);
    });

    testWidgets('deletes only after confirmation', (tester) async {
      await _pumpOwnerShell(tester, categoryNames: ['Boissons']);
      await _openCategories(tester);

      await tester.tap(find.byTooltip('Supprimer « Boissons »'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(_categories.names, ['Boissons']);

      await tester.tap(find.byTooltip('Supprimer « Boissons »'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(_categories.names, isEmpty);
      expect(find.text('Aucune catégorie'), findsOneWidget);
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
      await _pumpOwnerShell(tester);
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
      await _pumpOwnerShell(tester);
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
        'photo': '',
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

    testWidgets('rejects a photo link that is not an http(s) URL', (
      tester,
    ) async {
      await _pumpOwnerShell(tester);
      await _openTab(tester, 'Magasin');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Photo du magasin'),
        'pas un lien',
      );
      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Lien invalide (il doit commencer par http:// ou https://).'),
        findsOneWidget,
      );
      expect(_stores.lastUpdate, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Photo du magasin'),
        'https://x.test/a.jpg',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(_stores.lastUpdate?['photo'], 'https://x.test/a.jpg');
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
}
