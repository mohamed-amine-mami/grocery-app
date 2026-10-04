import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

late FakeStoreRepository _stores;

Future<void> _pumpOwnerShell(WidgetTester tester) async {
  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) =>
        _stores = FakeStoreRepository(api, store: closedStore),
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
