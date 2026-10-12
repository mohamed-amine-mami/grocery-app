import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_store.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/customer_scope.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/customer/views/stores_view.dart';

import 'fake_image_http.dart';
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

/// The storefront faces on the cards (the tab bar has the same icon).
Finder get _faces => find.descendant(
  of: find.byType(Card),
  matching: find.byIcon(Icons.storefront_rounded),
);

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

  group('composition', () {
    testWidgets('one card per store; the name leads, then open state, '
        'address and description', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(
          id: 1,
          name: 'Menzah Market',
          description: 'Épicerie de quartier',
        ),
        fakeCustomerStore(
          id: 2,
          name: 'Zahra',
          address: '5 Avenue Habib Bourguiba',
          isOpen: false,
        ),
      ]);
      // Each store is its own card; no hairline list.
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byType(Divider), findsNothing);
      final name = tester.getTopLeft(find.text('Menzah Market'));
      final state = tester.getTopLeft(find.text('Ouvert'));
      final address = tester.getTopLeft(
        find.text('12 Rue de la Liberté, Tunis'),
      );
      final description = tester.getTopLeft(find.text('Épicerie de quartier'));
      expect(name.dy, lessThan(state.dy));
      expect(state.dy, lessThan(address.dy));
      expect(address.dy, lessThan(description.dy));
      // The description lines up with the address text, not its pin.
      expect(description.dx, address.dx);
      // 20/700 name.
      final text = tester.widget<Text>(find.text('Menzah Market'));
      expect(text.style?.fontSize, 20);
      expect(text.style?.fontWeight, FontWeight.w700);
      // The address has a pin.
      expect(find.byIcon(Icons.place_outlined), findsNWidgets(2));
    });

    testWidgets('open and closed are said in words, with a dot or a clock', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'A'),
        fakeCustomerStore(id: 2, name: 'B', isOpen: false),
      ]);
      expect(find.text('Ouvert'), findsOneWidget);
      expect(find.text('Fermé'), findsOneWidget);
      // Closed: a neutral clock. Open: a dot, drawn, with no pill.
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
      expect(find.byType(StoreOpenBadge), findsNothing);
    });

    testWidgets('the chevron sits on the name line', (tester) async {
      await _pumpStores(tester, [fakeCustomerStore(id: 1, name: 'Menzah')]);
      final name = tester.getRect(find.text('Menzah'));
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      expect(chevron.top, lessThan(name.bottom));
      expect(chevron.bottom, greaterThan(name.top));
      expect(chevron.right, lessThanOrEqualTo(400));
    });

    testWidgets('a store with no photo gets the storefront face, no monogram', (
      tester,
    ) async {
      await _pumpStores(tester, [fakeCustomerStore(id: 1, name: 'menzah')]);
      expect(_faces, findsOneWidget);
      expect(find.text('M'), findsNothing);
      expect(find.byType(Image), findsNothing);
      // The face has the photo's 2:1 space, so the card is the same as one
      // with a photo.
      final cover = tester.getSize(
        find.descendant(
          of: find.byType(Card),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(cover.width / cover.height, closeTo(2, 0.01));
    });

    testWidgets('the face is a quiet cream surface, no disc, no strong fill', (
      tester,
    ) async {
      await _pumpStores(tester, [fakeCustomerStore(id: 1, name: 'menzah')]);
      final face = find.ancestor(of: _faces, matching: find.byType(ColoredBox));
      final surface = tester.widget<ColoredBox>(face.first);
      expect(surface.color, AppColors.background);
      // A small, translucent storefront: not a disc, not the brand fill.
      final icon = tester.widget<Icon>(_faces);
      expect(icon.size, lessThanOrEqualTo(40));
      expect(icon.color!.a, lessThan(0.5));
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle &&
                w.position == DecorationPosition.background,
          ),
        ),
        // Only the open-state dot is a circle.
        findsOneWidget,
      );
    });

    testWidgets('a photo is landscape 2:1 across the card, cropped', (
      tester,
    ) async {
      await servingImageErrors(hang: true, () async {
        await _pumpStores(tester, [
          fakeCustomerStore(
            id: 1,
            name: 'Chez Sami',
            photo: 'https://res.example/stores/1/photo.jpg',
          ),
        ]);
        final image = find.byType(Image);
        expect(image, findsOneWidget);
        expect(tester.widget<Image>(image).fit, BoxFit.cover);
        final card = tester.getRect(find.byType(Card));
        final photo = tester.getRect(image);
        expect(photo.topLeft, card.topLeft);
        expect(photo.width, card.width);
        expect(photo.width / photo.height, closeTo(2, 0.01));
        // While it loads, the face holds the space: no grey hole, no shift.
        expect(_faces, findsOneWidget);
      });
    });

    testWidgets('every card has the same photo area, photo or not', (
      tester,
    ) async {
      await servingImageErrors(hang: true, () async {
        await _pumpStores(tester, [
          fakeCustomerStore(
            id: 1,
            name: 'Avec photo',
            photo: 'https://res.example/stores/1/photo.jpg',
          ),
          fakeCustomerStore(id: 2, name: 'Sans photo'),
          fakeCustomerStore(id: 3, name: 'Photo vide', photo: ''),
          fakeCustomerStore(id: 4, name: 'Pas une URL', photo: 'ftp://x/y'),
        ], size: const Size(400, 3000));
        final heights = {
          for (final name in [
            'Avec photo',
            'Sans photo',
            'Photo vide',
            'Pas une URL',
          ])
            tester
                .getSize(
                  find.ancestor(
                    of: find.text(name),
                    matching: find.byType(Card),
                  ),
                )
                .height,
        };
        expect(heights, hasLength(1));
        // Only the first has an image; the others are never fetched.
        expect(find.byType(Image), findsOneWidget);
        expect(_faces, findsNWidgets(4));
      });
    });

    testWidgets('the photo is inside its card, clipped to its corners', (
      tester,
    ) async {
      await servingImageErrors(hang: true, () async {
        await _pumpStores(tester, [
          fakeCustomerStore(
            id: 1,
            name: 'Chez Sami',
            photo: 'https://res.example/stores/1/photo.jpg',
          ),
        ]);
        final card = find.byType(Card);
        // One card holds the photo and the text: a descendant, not a sibling.
        expect(
          find.descendant(of: card, matching: find.byType(Image)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Chez Sami')),
          findsOneWidget,
        );
        final widget = tester.widget<Card>(card);
        expect(widget.clipBehavior, Clip.antiAlias);
        final shape = widget.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(16));
        // The photo starts at the card's top edge and spans its whole width;
        // the text follows directly below it, with no gap.
        final photo = tester.getRect(find.byType(Image));
        final box = tester.getRect(card);
        expect(photo.topLeft, box.topLeft);
        expect(photo.width, box.width);
        final name = tester.getTopLeft(find.text('Chez Sami'));
        expect(name.dy - photo.bottom, lessThan(20));
        // The hairline is painted over the photo too.
        final outline = tester.widget<DecoratedBox>(
          find.ancestor(of: card, matching: find.byType(DecoratedBox)).first,
        );
        expect(outline.position, DecorationPosition.foreground);
      });
    });

    testWidgets('a card is the photo plus a compact text block', (
      tester,
    ) async {
      await _pumpStores(tester, [fakeCustomerStore(id: 1, name: 'Menzah')]);
      final card = tester.getSize(find.byType(Card));
      final cover = card.width / 2;
      expect(card.height - cover, lessThan(116));
    });

    testWidgets('on a wide window the cards stay a readable column', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Menzah'),
      ], size: const Size(1000, 1200));
      expect(tester.getSize(find.byType(Card)).width, lessThanOrEqualTo(560));
    });

    testWidgets('a photo that cannot load keeps the face, with no shift', (
      tester,
    ) async {
      await servingImageErrors(() async {
        await _pumpStores(tester, [
          fakeCustomerStore(
            id: 1,
            name: 'Chez Sami',
            photo: 'https://res.example/stores/1/photo.jpg',
          ),
          fakeCustomerStore(id: 2, name: 'Zahra'),
        ]);
        final before = tester.getSize(find.byType(Card).first);
        await tester.pumpAndSettle();
        expect(_faces, findsNWidgets(2));
        expect(find.text('C'), findsNothing);
        expect(tester.getSize(find.byType(Card).first), before);
        final withPhoto = tester.getSize(
          find.ancestor(
            of: find.text('Chez Sami'),
            matching: find.byType(Card),
          ),
        );
        final plain = tester.getSize(
          find.ancestor(of: find.text('Zahra'), matching: find.byType(Card)),
        );
        expect(withPhoto, plain);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the whole row opens the catalogue, closed stores too', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Fermé Market', isOpen: false),
      ]);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Fermé Market'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Fermé Market'));
      await tester.pumpAndSettle();
      expect(find.textContaining('mais pas commander'), findsOneWidget);
    });

    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.65), (402.0, 1.0)]) {
      testWidgets('nothing is cut at $width px, $scale×', (tester) async {
        await _pumpStores(
          tester,
          [
            fakeCustomerStore(
              id: 1,
              name: 'Supermarché Coopérative de la Médina',
              description:
                  'Fruits, légumes, boulangerie et produits laitiers du jour',
            ),
          ],
          size: Size(width, 3000),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Ouvert'), findsOneWidget);
        // The chevron stays on screen, on the first line of the name.
        final chevron = tester.getRect(
          find.byIcon(Icons.chevron_right_rounded),
        );
        expect(chevron.right, lessThanOrEqualTo(width));
        expect(
          chevron.top,
          lessThan(
            tester
                .getRect(find.text('Supermarché Coopérative de la Médina'))
                .bottom,
          ),
        );
        expect(
          tester
              .getRect(find.text('Supermarché Coopérative de la Médina'))
              .right,
          lessThanOrEqualTo(width),
        );
      });
    }
  });

  group('sections', () {
    testWidgets('open and closed stores are under their own headings, with '
        'counts', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Zahra', isOpen: false),
        fakeCustomerStore(id: 2, name: 'Beta'),
        fakeCustomerStore(id: 3, name: 'Alpha'),
      ]);
      expect(find.text('Ouverts maintenant · 2'), findsOneWidget);
      expect(find.text('Fermés · 1'), findsOneWidget);
      final opened = tester.getTopLeft(find.text('Ouverts maintenant · 2')).dy;
      final closed = tester.getTopLeft(find.text('Fermés · 1')).dy;
      final top = _tops(tester, ['Alpha', 'Beta', 'Zahra']);
      expect(opened, lessThan(top[0]));
      expect(top[0], lessThan(top[1]));
      expect(top[1], lessThan(closed));
      expect(closed, lessThan(top[2]));
    });

    testWidgets('a group with no store has no heading', (tester) async {
      await _pumpStores(tester, [fakeCustomerStore(id: 1, name: 'Alpha')]);
      expect(find.text('Ouverts maintenant · 1'), findsOneWidget);
      expect(find.textContaining('Fermés'), findsNothing);
    });

    testWidgets('the last card scrolls fully above the navigation bar', (
      tester,
    ) async {
      await _pumpStores(tester, [
        for (var i = 1; i <= 8; i++) fakeCustomerStore(id: i, name: 'S$i'),
      ], size: const Size(400, 600));
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -3000),
        3000,
      );
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byType(Card).last);
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(last.bottom, lessThanOrEqualTo(bar.top - 24));
    });

    testWidgets('cards in a group are 12 px apart', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Alpha'),
        fakeCustomerStore(id: 2, name: 'Beta'),
      ]);
      final cards = tester.widgetList(find.byType(Card)).toList();
      final first = tester.getRect(find.byWidget(cards[0]));
      final second = tester.getRect(find.byWidget(cards[1]));
      expect(second.top - first.bottom, 12);
    });
  });

  group('search', () {
    final stores = [
      fakeCustomerStore(
        id: 1,
        name: 'Marché du Bardo',
        address: '5 Avenue Habib Bourguiba, Le Bardo',
        description: 'Primeurs et épicerie fine',
      ),
      fakeCustomerStore(
        id: 2,
        name: 'Épicerie Zahra',
        address: 'Rue de la Liberté, Menzah 5, Tunis',
      ),
      fakeCustomerStore(
        id: 3,
        name: 'Ariana Primeur',
        address: 'Avenue de la République, Ariana',
        isOpen: false,
      ),
      fakeCustomerStore(id: 4, name: 'Chez Sami', isOpen: false),
    ];
    final field = find.byType(TextField);

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(field, text);
      await tester.pump();
    }

    testWidgets('matches the name, ignoring case and accents', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'EPICERIE');
      expect(find.text('Épicerie Zahra'), findsOneWidget);
      expect(find.text('Marché du Bardo'), findsNothing);
      await type(tester, 'marche');
      expect(find.text('Marché du Bardo'), findsOneWidget);
    });

    testWidgets('matches the address (region or city)', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'ariana');
      expect(find.text('Ariana Primeur'), findsOneWidget);
      await type(tester, 'liberte');
      expect(find.text('Épicerie Zahra'), findsOneWidget);
      expect(find.text('Ariana Primeur'), findsNothing);
    });

    testWidgets('every word must match, in any order', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'bardo avenue');
      expect(find.text('Marché du Bardo'), findsOneWidget);
      await type(tester, 'tunis bardo');
      expect(find.text('Aucun magasin trouvé'), findsOneWidget);
    });

    testWidgets('the description is not searched', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'primeurs');
      // "Primeur" is in Ariana's name, "Primeurs" only in a description.
      expect(find.text('Marché du Bardo'), findsNothing);
      await type(tester, 'fine');
      expect(find.text('Aucun magasin trouvé'), findsOneWidget);
    });

    testWidgets('the placeholder address is not searched', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(
          id: 1,
          name: 'Sans adresse',
          address: 'Adresse à renseigner',
        ),
        fakeCustomerStore(id: 2, name: 'Autre'),
      ]);
      await type(tester, 'renseigner');
      expect(find.text('Aucun magasin trouvé'), findsOneWidget);
      await type(tester, 'sans');
      expect(find.text('Sans adresse'), findsOneWidget);
    });

    testWidgets('sections, counts and order follow the matches', (
      tester,
    ) async {
      await _pumpStores(tester, stores);
      expect(find.text('Ouverts maintenant · 2'), findsOneWidget);
      expect(find.text('Fermés · 2'), findsOneWidget);
      await type(tester, 'ar');
      // Marché du Bardo (open), Ariana Primeur (closed): one in each.
      expect(find.text('Ouverts maintenant · 1'), findsOneWidget);
      expect(find.text('Fermés · 1'), findsOneWidget);
      expect(find.text('Chez Sami'), findsNothing);
      // A query that only closed stores match hides the open section.
      await type(tester, 'ariana');
      expect(find.textContaining('Ouverts maintenant'), findsNothing);
      expect(find.text('Fermés · 1'), findsOneWidget);
    });

    testWidgets('the open-first, by-name order is kept', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Zed', address: 'Tunis'),
        fakeCustomerStore(id: 2, name: 'Beta', address: 'Tunis', isOpen: false),
        fakeCustomerStore(id: 3, name: 'Alpha', address: 'Tunis'),
        fakeCustomerStore(
          id: 4,
          name: 'Gamma',
          address: 'Tunis',
          isOpen: false,
        ),
      ], size: const Size(400, 3200));
      await type(tester, 'tunis');
      final tops = _tops(tester, ['Alpha', 'Zed', 'Beta', 'Gamma']);
      expect(tops, [...tops]..sort());
    });

    testWidgets('no match: a French message with a way back', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'zzzz');
      expect(find.text('Aucun magasin trouvé'), findsOneWidget);
      expect(find.text('Effacer la recherche'), findsWidgets);
      expect(find.textContaining('Ouverts maintenant'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Effacer la recherche'));
      await tester.pump();
      expect(find.text('Marché du Bardo'), findsOneWidget);
      expect(find.text('Chez Sami'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    });

    testWidgets('the clear icon returns to the whole list', (tester) async {
      await _pumpStores(tester, stores);
      expect(find.byTooltip('Effacer la recherche'), findsNothing);
      await type(tester, 'sami');
      expect(find.text('Marché du Bardo'), findsNothing);
      await tester.tap(find.byTooltip('Effacer la recherche'));
      await tester.pump();
      expect(find.text('Marché du Bardo'), findsOneWidget);
      expect(find.text('Chez Sami'), findsOneWidget);
      expect(find.byTooltip('Effacer la recherche'), findsNothing);
    });

    testWidgets('the query survives a pull-to-refresh', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'sami');
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'sami');
      expect(find.text('Chez Sami'), findsOneWidget);
      expect(find.text('Marché du Bardo'), findsNothing);
    });

    testWidgets('the query survives a change of tab', (tester) async {
      await _pumpStores(tester, stores);
      await type(tester, 'sami');
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Commandes'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Magasins'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'sami');
      expect(find.text('Marché du Bardo'), findsNothing);
    });

    testWidgets('no stores at all: the empty state, no search field', (
      tester,
    ) async {
      await _pumpStores(tester, const []);
      expect(find.text('Aucun magasin'), findsOneWidget);
      expect(field, findsNothing);
    });

    testWidgets('1.65× on a 360 px phone: nothing overflows', (tester) async {
      await _pumpStores(
        tester,
        stores,
        size: const Size(360, 3200),
        textScale: 1.65,
      );
      await type(tester, 'bardo');
      expect(tester.takeException(), isNull);
      expect(find.text('Marché du Bardo'), findsOneWidget);
      expect(field, findsOneWidget);
    });

    testWidgets('with the keyboard up, the last result can be reached', (
      tester,
    ) async {
      await _pumpStores(tester, [
        for (var i = 1; i <= 6; i++) fakeCustomerStore(id: i, name: 'Store $i'),
      ], size: const Size(400, 800));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -4000),
        4000,
      );
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byType(Card).last);
      expect(last.bottom, lessThanOrEqualTo(800 - 320));
      expect(last.top, greaterThan(0));
    });
  });

  group('cart shortcut', () {
    final store = fakeCustomerStore(id: 10, name: 'Menzah Market');
    final yaourt = fakeCustomerProduct(
      id: 1,
      name: 'Yaourt',
      unit: SaleUnit.piece,
      priceMillimes: 1000,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 12,
    );
    final miel = fakeCustomerProduct(
      id: 2,
      name: 'Miel',
      unit: SaleUnit.piece,
      priceMillimes: 4000,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 12,
    );

    CustomerScope scope(WidgetTester tester) =>
        CustomerScope.of(tester.element(find.byType(Scaffold).first));

    final shortcut = find.text('Reprendre mon panier');

    testWidgets('is absent, and takes no room, with an empty cart', (
      tester,
    ) async {
      await _pumpStores(tester, [store]);
      expect(shortcut, findsNothing);
      // Search field, then the section heading, with only the usual gap.
      final search = tester.getRect(find.byType(TextField));
      final heading = tester.getTopLeft(find.text('Ouverts maintenant · 1'));
      expect(heading.dy - search.bottom, lessThan(40));
    });

    testWidgets('names the cart’s store and counts its products', (
      tester,
    ) async {
      await _pumpStores(tester, [store]);
      final cart = scope(tester).cart;
      cart.add(store, yaourt);
      await tester.pump();
      expect(shortcut, findsOneWidget);
      expect(find.text('Menzah Market · 1 produit'), findsWidgets);
      cart.add(store, miel);
      await tester.pump();
      expect(find.text('Menzah Market · 2 produits'), findsOneWidget);
    });

    testWidgets('sits between the search field and the sections', (
      tester,
    ) async {
      await _pumpStores(tester, [store]);
      scope(tester).cart.add(store, yaourt);
      await tester.pump();
      final search = tester.getRect(find.byType(TextField));
      final pill = tester.getRect(
        find.ancestor(of: shortcut, matching: find.byType(InkWell)).first,
      );
      final heading = tester.getTopLeft(find.text('Ouverts maintenant · 1'));
      expect(pill.top, greaterThanOrEqualTo(search.bottom));
      expect(pill.bottom, lessThanOrEqualTo(heading.dy));
      expect(pill.height, greaterThanOrEqualTo(48));
    });

    testWidgets('opens the Panier tab', (tester) async {
      await _pumpStores(tester, [store]);
      final s = scope(tester);
      s.cart.add(store, yaourt);
      await tester.pump();
      expect(s.navigation.tab, CustomerTab.stores);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(s.navigation.tab, CustomerTab.cart);
      expect(find.text('Total estimé'), findsOneWidget);
    });

    testWidgets('goes away when the cart is emptied', (tester) async {
      await _pumpStores(tester, [store]);
      final cart = scope(tester).cart;
      cart.add(store, yaourt);
      await tester.pump();
      expect(shortcut, findsOneWidget);
      cart.remove(yaourt.id);
      await tester.pump();
      expect(shortcut, findsNothing);
    });

    testWidgets('has a spoken label, and a store with a blank name says '
        'only the count', (tester) async {
      final blank = fakeCustomerStore(id: 11, name: '   ');
      await _pumpStores(tester, [blank]);
      scope(tester).cart.add(blank, yaourt);
      await tester.pump();
      expect(
        find.bySemanticsLabel('Reprendre mon panier, 1 produit'),
        findsOneWidget,
      );
    });

    testWidgets('stays whole at 1.65× on a 320 px phone', (tester) async {
      await _pumpStores(
        tester,
        [store],
        size: const Size(320, 2400),
        textScale: 1.65,
      );
      scope(tester).cart.add(store, yaourt);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final pill = tester.getRect(
        find.ancestor(of: shortcut, matching: find.byType(InkWell)).first,
      );
      expect(pill.left, greaterThanOrEqualTo(0));
      expect(pill.right, lessThanOrEqualTo(320));
    });
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

    testWidgets('a closed store is still listed, with "Fermé"', (tester) async {
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
        fakeCustomerStore(
          id: 1,
          name: 'Menzah Market',
          description: description,
        ),
      ]);

      final text = tester.widget<Text>(find.text(description));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        tester.getTopLeft(find.text(description)).dy,
        greaterThan(
          tester.getTopLeft(find.text('12 Rue de la Liberté, Tunis').first).dy,
        ),
      );
    });

    testWidgets('null, empty or blank adds no space', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'Store A'),
        fakeCustomerStore(id: 2, name: 'Store B', description: ''),
        fakeCustomerStore(id: 3, name: 'Store C', description: '   \n '),
        fakeCustomerStore(
          id: 4,
          name: 'Store D',
          description: 'Une description',
        ),
      ]);

      double height(String name) => tester
          .getSize(
            find
                .ancestor(of: find.text(name), matching: find.byType(InkWell))
                .first,
          )
          .height;
      expect(height('Store B'), height('Store A'));
      expect(height('Store C'), height('Store A'));
      // A real description is there, under the name.
      expect(
        tester.getTopLeft(find.text('Une description')).dy,
        greaterThan(tester.getBottomLeft(find.text('Store D')).dy - 1),
      );
    });
  });

  group('address', () {
    testWidgets('the owner’s placeholder is not shown, nor a gap for it', (
      tester,
    ) async {
      await _pumpStores(tester, [
        fakeCustomerStore(
          id: 1,
          name: 'Chahut',
          address: 'Adresse à renseigner',
        ),
        fakeCustomerStore(id: 2, name: 'Menzah Market'),
      ]);
      expect(find.text('Adresse à renseigner'), findsNothing);
      expect(find.text('12 Rue de la Liberté, Tunis'), findsOneWidget);
      // No second line for the store without a real address.
      expect(find.textContaining('renseigner'), findsNothing);
    });

    testWidgets('matches ignoring case and surrounding spaces', (tester) async {
      await _pumpStores(tester, [
        fakeCustomerStore(id: 1, name: 'A', address: '  ADRESSE À RENSEIGNER '),
      ]);
      expect(find.textContaining('RENSEIGNER'), findsNothing);
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
