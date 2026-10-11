import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('owner with a store lands in the owner shell', (tester) async {
    await pumpAppSignedInAs(
      tester,
      testOwner,
      storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
    );

    expect(find.text('Menzah Market'), findsOneWidget);
    expect(find.text('Magasin fermé'), findsOneWidget);
    expect(find.text('Créer votre magasin'), findsNothing);
    expect(find.textContaining('Vous êtes connecté en tant que'), findsNothing);
  });

  testWidgets('owner without a store is sent to store creation', (
    tester,
  ) async {
    await pumpAppSignedInAs(
      tester,
      testOwner,
      storeRepository: FakeStoreRepository.new,
    );

    expect(find.text('Créer votre magasin'), findsOneWidget);
    expect(find.text('Adresse du magasin'), findsOneWidget);
    expect(find.text('Magasin fermé'), findsNothing);
    expect(find.textContaining('Vous êtes connecté en tant que'), findsNothing);
  });

  testWidgets('owner sees a retry screen, not the shell, if the store '
      'cannot be loaded', (tester) async {
    await pumpAppSignedInAs(
      tester,
      testOwner,
      storeRepository: (api) => FakeStoreRepository(api, fails: true),
    );

    expect(find.text('Impossible de charger votre magasin.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Magasin fermé'), findsNothing);
    expect(find.text('Créer votre magasin'), findsNothing);
  });

  testWidgets('client never asks for a store and lands on the customer shell', (
    tester,
  ) async {
    await pumpAppSignedInAs(
      tester,
      testClient,
      storeRepository: (api) => FakeStoreRepository(api, fails: true),
    );

    // The customer shell: Magasins · Panier · Commandes · Profil.
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Magasins', 'Panier', 'Commandes', 'Profil']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Créer votre magasin'), findsNothing);
    expect(find.text('Impossible de charger votre magasin.'), findsNothing);
  });

  testWidgets('store creation requires an address and paired coordinates', (
    tester,
  ) async {
    await pumpAppSignedInAs(
      tester,
      testOwner,
      storeRepository: FakeStoreRepository.new,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom du magasin'),
      'Menzah Market',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '36.8',
    );
    await tester.ensureVisible(find.text('Créer mon magasin'));
    await tester.tap(find.text('Créer mon magasin'));
    await tester.pumpAndSettle();

    expect(find.text("L'adresse du magasin est requise."), findsOneWidget);
    expect(find.text('Renseignez aussi la longitude.'), findsOneWidget);
  });
}
