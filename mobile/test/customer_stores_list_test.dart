import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_store.dart';
import 'package:grocery_mobile/data/services/api_client.dart';

import 'fakes.dart';

Future<void> _pumpStores(
  WidgetTester tester,
  List<CustomerStore> stores, {
  Size size = const Size(400, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repository = FakeCustomerStoresRepository(ApiClient(), stores: stores);
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerStoresRepository: (_) => repository,
  );
}

/// The vertical positions of the stores' names, in the order given.
List<double> _tops(WidgetTester tester, List<String> names) => [
  for (final name in names) tester.getTopLeft(find.text(name)).dy,
];

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  group('order', () {
    testWidgets('open stores come before closed ones, each group by name', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Ariana Primeur', isOpen: false),
        fakeCustomerStore(id: 2, name: 'zahra Market'),
        fakeCustomerStore(id: 3, name: 'Menzah Market'),
        fakeCustomerStore(id: 4, name: 'Bardo Frais', isOpen: false),
        fakeCustomerStore(id: 5, name: 'Lac Épicerie'),
      ]);

      const expected = [
        'Lac Épicerie',
        'Menzah Market',
        'zahra Market',
        'Ariana Primeur',
        'Bardo Frais',
      ];
      final tops = _tops(tester, expected);
      expect(tops, orderedEquals([...tops]..sort()));
      expect(tops.toSet(), hasLength(5));
    });

    testWidgets('case does not decide the order', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'beta'),
        fakeCustomerStore(id: 2, name: 'Alpha'),
        fakeCustomerStore(id: 3, name: 'Gamma'),
      ]);
      final tops = _tops(tester, ['Alpha', 'beta', 'Gamma']);
      expect(tops, orderedEquals([...tops]..sort()));
    });

    testWidgets('equal names keep a stable order, by id', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 20, name: 'Bardo', address: 'Rue B'),
        fakeCustomerStore(id: 10, name: 'Bardo', address: 'Rue A'),
      ]);
      expect(
        tester.getTopLeft(find.text('Rue A')).dy,
        lessThan(tester.getTopLeft(find.text('Rue B')).dy),
      );
    });

    testWidgets('a closed store is still listed, with "Fermé"', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Ariana Primeur', isOpen: false),
        fakeCustomerStore(id: 2, name: 'Menzah Market'),
      ]);
      expect(find.text('Fermé'), findsOneWidget);
      expect(find.text('Ouvert'), findsOneWidget);
    });
  });

  group('description', () {
    testWidgets('is shown under the address, in at most two lines', (
      tester,
    ) async {
      const description =
          'Épicerie de quartier : fruits, légumes, produits laitiers et pain '
          'frais chaque matin, retrait au comptoir de 8 h à 20 h tous les '
          'jours sauf le dimanche après-midi.';
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Menzah Market', description: description),
      ]);

      final text = tester.widget<Text>(find.text(description));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        tester.getTopLeft(find.text(description)).dy,
        greaterThan(
          tester.getTopLeft(find.text('12 Rue de la Liberté, Tunis')).dy,
        ),
      );
    });

    testWidgets('null, empty or blank adds no space', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Store A'),
        fakeCustomerStore(id: 2, name: 'Store B', description: ''),
        fakeCustomerStore(id: 3, name: 'Store C', description: '   \n '),
        fakeCustomerStore(id: 4, name: 'Store D', description: 'Une description'),
      ]);

      double height(String name) => tester
          .getSize(
            find
                .ancestor(of: find.text(name), matching: find.byType(Card))
                .first,
          )
          .height;
      expect(height('Store B'), height('Store A'));
      expect(height('Store C'), height('Store A'));
      expect(height('Store D'), greaterThan(height('Store A')));
    });
  });

  group('address', () {
    testWidgets('the owner’s placeholder is not shown, nor a gap for it', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Chahut', address: 'Adresse à renseigner'),
        fakeCustomerStore(id: 2, name: 'Menzah Market'),
      ]);
      expect(find.text('Adresse à renseigner'), findsNothing);
      expect(find.byIcon(Icons.place_outlined), findsOneWidget); // Menzah only
      expect(find.text('12 Rue de la Liberté, Tunis'), findsOneWidget);
    });

    testWidgets('matches ignoring case and surrounding spaces', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'A', address: '  ADRESSE À RENSEIGNER '),
      ]);
      expect(find.textContaining('RENSEIGNER'), findsNothing);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
    });

    testWidgets('a real address that merely contains the words stays', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(
          id: 1,
          name: 'A',
          address: 'Adresse à renseigner bientôt, 5 Rue X',
        ),
      ]);
      expect(find.textContaining('5 Rue X'), findsOneWidget);
    });
  });

  group('small screens', () {
    testWidgets('320 px at 1.6× text: long name, description, badge and '
        'photo do not overflow', (tester) async {
      await _pumpStores(
        tester,
        [
          fakeCustomerStore(
            id: 1,
            name: 'Supermarché de la Grande Épicerie du Lac de Tunis',
            address: '12 Rue de la Liberté, Les Berges du Lac 2, Tunis',
            description:
                'Fruits, légumes, produits laitiers et pain frais chaque '
                'matin, retrait au comptoir tous les jours de la semaine.',
            photo: 'https://res.example/stores/1/photo.jpg',
          ),
          fakeCustomerStore(
            id: 2,
            name: 'Ariana Primeur et Marché Frais',
            isOpen: false,
          ),
        ],
        size: const Size(320, 2400),
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Ouvert'), findsOneWidget);
      expect(find.text('Fermé'), findsOneWidget);
      // The cards stay inside the screen.
      for (final card in tester.widgetList(find.byType(Card))) {
        final rect = tester.getRect(find.byWidget(card));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
    });
  });
}
