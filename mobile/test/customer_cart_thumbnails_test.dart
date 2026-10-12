import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/core/widgets/product_image.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/cart_view_model.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/customer_scope.dart';
import 'package:grocery_mobile/ui/features/customer/views/cart_view.dart';
import 'package:grocery_mobile/ui/features/customer/views/checkout_view.dart';

import 'fakes.dart';

const _photo = 'https://res.example/f_auto,q_auto/v1/banane.jpg';

CustomerProduct _banane({bool isOrderable = true}) => fakeCustomerProduct(
  id: 1,
  name: 'Banane',
  photo: _photo,
  isOrderable: isOrderable,
);

CustomerProduct _mayo() => fakeCustomerProduct(
  id: 2,
  name: 'Mayonnaise',
  category: fakeDairyCategory,
  unit: SaleUnit.piece,
  priceMillimes: 1500,
  minQuantity: 1,
  quantityStep: 1,
  maxQuantity: 6,
);

/// A signed-in customer in Menzah Market with a banana (with a photo) and a
/// mayonnaise (without) in the cart, on the Panier tab.
Future<CartViewModel> _openCart(
  WidgetTester tester, {
  Size size = const Size(400, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repository = FakeCustomerStoresRepository(
    ApiClient(),
    stores: [fakeCustomerStore(id: 10, name: 'Menzah Market')],
    products: {
      10: [_banane(), _mayo()],
    },
  );
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerStoresRepository: (_) => repository,
  );
  await tester.tap(find.text('Menzah Market'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Ajouter Banane'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Ajouter Mayonnaise'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Voir le panier'));
  await tester.pumpAndSettle();
  return CustomerScope.of(tester.element(find.byType(CartView))).cart;
}

Finder _inCart(Finder matching) =>
    find.descendant(of: find.byType(CartView), matching: matching);

Finder _inCheckout(Finder matching) =>
    find.descendant(of: find.byType(CheckoutView), matching: matching);

Future<void> _openCheckout(WidgetTester tester) async {
  await tester.tap(find.text('Commander'));
  await tester.pumpAndSettle();
}

void main() {
  // Phone-width layouts depend on real glyph widths (see the grid test).
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  group('cart lines', () {
    testWidgets('show the product’s own picture, at the start of the line', (
      tester,
    ) async {
      await _openCart(tester);

      final images = tester
          .widgetList<ProductImage>(_inCart(find.byType(ProductImage)))
          .toList();
      expect(images.map((i) => i.photo), [_photo, null]);
      // The catalogue's component and the whole picture: 56 px with a photo,
      // the quiet 48 px tile without one.
      expect(images.map((i) => i.size), [56, 48]);
      expect(images.map((i) => i.quiet), [false, true]);
      expect(images.every((i) => i.fit == BoxFit.contain), isTrue);

      // Left of the name, level with it.
      final image = tester.getRect(_inCart(find.byType(ProductImage)).first);
      final name = tester.getTopLeft(_inCart(find.text('Banane')));
      expect(image.right, lessThan(name.dx));
      expect(image.top, closeTo(name.dy, 4));
      // The line's amount is under the name, on its left edge; the control
      // is at the right edge of the same line.
      final amount = tester.getRect(_inCart(find.text('0,900 DT')));
      expect(
        amount.top,
        greaterThan(tester.getBottomLeft(_inCart(find.text('Banane'))).dy),
      );
      expect(amount.left, closeTo(name.dx, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing or unloadable picture is the neutral placeholder', (
      tester,
    ) async {
      await _openCart(tester);
      // Mayonnaise has no photo; the banana's cannot be fetched in a test.
      expect(
        _inCart(find.byIcon(Icons.shopping_basket_rounded)),
        findsNWidgets(2),
      );
      expect(find.text('Banane'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the picture adds nothing for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await _openCart(tester);
      expect(_inCart(find.bySemanticsLabel('Image du produit')), findsNothing);
      // The name and the quantity controls are still there to be read.
      expect(_inCart(find.bySemanticsLabel(RegExp('Banane'))), findsWidgets);
      expect(find.byTooltip('Augmenter la quantité de Banane'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('quantity and removal behave exactly as before', (
      tester,
    ) async {
      final cart = await _openCart(tester);
      expect(cart.quantityOf(1), 500);

      await tester.tap(find.byTooltip('Augmenter la quantité de Banane'));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(1), 600);
      expect(cart.estimatedTotalMillimes, 600 * 1800 ~/ 1000 + 1500);

      // Mayonnaise is at its minimum: the control removes the line, picture too.
      await tester.tap(find.byTooltip('Retirer Mayonnaise du panier'));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(2), 0);
      expect(_inCart(find.byType(ProductImage)), findsOneWidget);
      expect(_inCart(find.text('Mayonnaise')), findsNothing);
    });

    testWidgets('a product that is gone is dimmed, like in the catalogue', (
      tester,
    ) async {
      final cart = await _openCart(tester);
      cart.syncWithCatalog(10, [_banane(isOrderable: false), _mayo()]);
      await tester.pumpAndSettle();

      double opacityOf(Finder image) => tester
          .widget<Opacity>(
            find.ancestor(of: image, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final images = _inCart(find.byType(ProductImage));
      expect(opacityOf(images.at(0)), 0.45);
      expect(opacityOf(images.at(1)), 1);
      expect(find.text('Retirer'), findsOneWidget); // its own action, unchanged
    });
  });

  group('cart list surface', () {
    testWidgets('one list surface with hairlines, no card per line', (
      tester,
    ) async {
      await _openCart(tester);
      // The lines share one card; the store and the total have none.
      expect(_inCart(find.byType(Card)), findsOneWidget);
      expect(_inCart(find.byType(Divider)), findsOneWidget);
      // The store is a heading above the list, not inside a card.
      final store = tester.getTopLeft(_inCart(find.text('Menzah Market')));
      final list = tester.getTopLeft(_inCart(find.byType(Card)));
      expect(store.dy, lessThan(list.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the divider starts at the text, not at the thumbnail', (
      tester,
    ) async {
      await _openCart(tester);
      final divider = tester.getTopLeft(_inCart(find.byType(Divider)));
      final name = tester.getTopLeft(_inCart(find.text('Mayonnaise')));
      expect(divider.dx, closeTo(name.dx, 1));
    });

    testWidgets('the total is the largest amount and is not in a card', (
      tester,
    ) async {
      await _openCart(tester);
      final label = find.text('Total estimé');
      expect(label, findsOneWidget);
      expect(
        find.ancestor(of: label, matching: find.byType(Card)),
        findsNothing,
      );
      // 20/700, above the 18/700 line amounts.
      final total = tester.widget<Text>(_inCart(find.text('2,400 DT')).first);
      expect(total.style?.fontSize, 20);
      expect(total.style?.fontWeight, FontWeight.w700);
      expect(
        find.text('Le total définitif est confirmé à l’envoi de la commande.'),
        findsOneWidget,
      );
    });

    testWidgets('an emptied cart shows the empty state and its action', (
      tester,
    ) async {
      final cart = await _openCart(tester);
      cart.clear();
      await tester.pumpAndSettle();
      expect(find.text('Votre panier est vide'), findsOneWidget);
      expect(find.text('Voir les magasins'), findsOneWidget);
      expect(find.text('Commander'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.65), (402.0, 1.0)]) {
      testWidgets('amount and control stay whole at $width px, $scale×', (
        tester,
      ) async {
        await _openCart(tester, size: Size(width, 2400), textScale: scale);
        expect(tester.takeException(), isNull);
        for (final name in ['Banane', 'Mayonnaise']) {
          final plus = tester.getRect(
            find.byTooltip('Augmenter la quantité de $name'),
          );
          expect(plus.right, lessThanOrEqualTo(width));
          expect(plus.width, greaterThanOrEqualTo(44));
        }
        expect(_inCart(find.text('0,900 DT')), findsOneWidget);
        expect(
          tester.getRect(_inCart(find.text('0,900 DT'))).right,
          lessThanOrEqualTo(width),
        );
      });
    }
  });

  group('checkout lines', () {
    testWidgets('show the same pictures, with the lines’ text unchanged', (
      tester,
    ) async {
      await _openCart(tester);
      await _openCheckout(tester);

      final images = tester
          .widgetList<ProductImage>(_inCheckout(find.byType(ProductImage)))
          .toList();
      expect(images.map((i) => i.photo), [_photo, null]);
      // The same tiles as the cart: 56 px with a photo, quiet 48 px without.
      expect(images.map((i) => i.size), [56, 48]);
      expect(
        _inCheckout(find.byIcon(Icons.shopping_basket_rounded)),
        findsNWidgets(2),
      );

      // Same copy as before.
      expect(_inCheckout(find.text('Banane')), findsOneWidget);
      expect(_inCheckout(find.text('500 g ·')), findsOneWidget);
      expect(_inCheckout(find.text('1,800 DT / kg')), findsOneWidget);
      expect(_inCheckout(find.text('0,900 DT')), findsOneWidget);
      expect(_inCheckout(find.text('Mayonnaise')), findsOneWidget);
      expect(_inCheckout(find.text('1 pièce ·')), findsOneWidget);
      expect(_inCheckout(find.text('1,500 DT / pièce')), findsOneWidget);
      expect(find.text('Confirmer la commande'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Level with the name.
      final image = tester.getRect(
        _inCheckout(find.byType(ProductImage)).first,
      );
      expect(
        image.top,
        closeTo(tester.getTopLeft(_inCheckout(find.text('Banane'))).dy, 6),
      );
    });
  });

  group('line amount and tile', () {
    // The amount's role is the same on every screen: titleMedium, on the
    // first baseline of the name.
    void expectAmount(
      WidgetTester tester,
      Finder scope,
      String amount, {
      FontWeight weight = FontWeight.w600,
    }) {
      final text = tester.widget<Text>(
        find.descendant(of: scope, matching: find.text(amount)).first,
      );
      expect(text.style?.fontSize, 18);
      expect(text.style?.fontWeight, weight);
    }

    testWidgets('the cart line’s amount is 18/700 at the text’s left edge', (
      tester,
    ) async {
      await _openCart(tester);
      expectAmount(
        tester,
        find.byType(CartView),
        '0,900 DT',
        weight: FontWeight.w700,
      );
      final name = tester.getRect(_inCart(find.text('Banane')));
      final amount = tester.getRect(_inCart(find.text('0,900 DT')));
      // Under the name and its unit price, on the same left edge.
      expect(amount.left, closeTo(name.left, 1));
      expect(amount.top, greaterThan(name.bottom));
      // The control sits at the right of the same line.
      final plus = tester.getRect(
        find.byTooltip('Augmenter la quantité de Banane'),
      );
      expect(plus.right, greaterThan(amount.right));
      expect(plus.center.dy, closeTo(amount.center.dy, 12));
    });

    testWidgets('the checkout line’s amount is the same role', (tester) async {
      await _openCart(tester);
      await _openCheckout(tester);
      expectAmount(
        tester,
        find.byType(CheckoutView),
        '0,900 DT',
        weight: FontWeight.w700,
      );
      final name = tester.getRect(_inCheckout(find.text('Banane')));
      final amount = tester.getRect(_inCheckout(find.text('0,900 DT')));
      // The cart's anatomy: under the name and its meta, on its left edge.
      expect(amount.left, closeTo(name.left, 1));
      expect(amount.top, greaterThan(name.bottom));
    });

    testWidgets('the tile is 56 × 56, tinted, with or without a picture', (
      tester,
    ) async {
      await _openCart(tester);
      for (final image in tester.widgetList<ProductImage>(
        _inCart(find.byType(ProductImage)),
      )) {
        expect(image.tile, isTrue);
      }
      final tiles = find.descendant(
        of: _inCart(find.byType(ProductImage)),
        matching: find.byType(ColoredBox),
      );
      expect(tiles, findsNWidgets(2));
      final sizes = <Size>[];
      for (final element in tiles.evaluate()) {
        final box = element.widget as ColoredBox;
        expect(box.color, AppColors.primary.withValues(alpha: 0.08));
        sizes.add(tester.getSize(find.byWidget(box)));
      }
      // 56 px for the photographed product, the quiet 48 px for the other.
      expect(sizes, [const Size(56, 56), const Size(48, 48)]);
      // Both in the same 56 px slot: the names start at the same x.
      expect(
        tester.getTopLeft(_inCart(find.text('Banane'))).dx,
        tester.getTopLeft(_inCart(find.text('Mayonnaise'))).dx,
      );
      // Placeholder does not tint twice (the tile is the only tint).
      final placeholder = tester
          .widgetList<Container>(
            find.descendant(
              of: _inCart(find.byType(ProductImage)),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.child is Icon);
      expect(placeholder, isNotEmpty);
      expect(placeholder.every((c) => c.color == null), isTrue);
    });
  });

  group('checkout line metadata', () {
    // "1 pièce · 1,500 DT / pièce" may break after the "·", never inside the
    // unit price (no lone "pièce" on a second line).
    for (final width in [402.0, 360.0, 320.0]) {
      testWidgets('keeps the unit price on one line at $width px', (
        tester,
      ) async {
        await _openCart(tester, size: Size(width, 2400));
        await _openCheckout(tester);

        final quantity = _inCheckout(find.text('1 pièce ·'));
        final unitPrice = _inCheckout(find.text('1,500 DT / pièce'));
        // One line of the same text style: same height as the quantity piece.
        expect(
          tester.getSize(unitPrice).height,
          tester.getSize(quantity).height,
        );
        final name = _inCheckout(find.text('Mayonnaise'));
        // Left-aligned with the name, under it; inside the screen.
        expect(tester.getTopLeft(quantity).dx, tester.getTopLeft(name).dx);
        expect(
          tester.getTopLeft(quantity).dy,
          greaterThan(tester.getTopLeft(name).dy),
        );
        expect(tester.getRect(unitPrice).right, lessThanOrEqualTo(width));
        // The line's amount: 18/700, under the meta, on the same left edge.
        final amount = _inCheckout(find.text('1,500 DT')).first;
        final text = tester.widget<Text>(amount);
        expect(text.style?.fontSize, 18);
        expect(text.style?.fontWeight, FontWeight.w700);
        expect(
          tester.getTopLeft(amount).dy,
          greaterThan(tester.getBottomLeft(quantity).dy - 1),
        );
        expect(tester.getTopLeft(amount).dx, tester.getTopLeft(name).dx);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a screen reader still hears quantity and unit price', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _openCart(tester);
      await _openCheckout(tester);
      expect(
        _inCheckout(find.bySemanticsLabel(RegExp('1 pièce ·'))),
        findsWidgets,
      );
      expect(
        _inCheckout(find.bySemanticsLabel(RegExp('1,500 DT / pièce'))),
        findsWidgets,
      );
      semantics.dispose();
    });
  });

  group('checkout composition', () {
    testWidgets('store is a heading, retrait and payment share one surface, '
        'the lines share another', (tester) async {
      await _openCart(tester);
      await _openCheckout(tester);

      // Two list surfaces only: pickup+payment, and the lines.
      expect(_inCheckout(find.byType(Card)), findsNWidgets(2));
      // The store is not in a card.
      expect(
        find.ancestor(
          of: _inCheckout(find.text('Menzah Market')),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      // Payment sits with the pickup time, above the order.
      final pay = tester.getTopLeft(_inCheckout(find.text('Paiement'))).dy;
      expect(
        pay,
        lessThan(
          tester.getTopLeft(_inCheckout(find.text('Votre commande'))).dy,
        ),
      );
      // The pickup note is kept.
      expect(
        find.text('C’est une heure souhaitée, pas un créneau réservé.'),
        findsOneWidget,
      );
    });

    testWidgets('the estimated total is not in a card, the bar repeats it', (
      tester,
    ) async {
      await _openCart(tester);
      await _openCheckout(tester);
      final label = _inCheckout(find.text('Total estimé'));
      expect(label, findsOneWidget);
      expect(
        find.ancestor(of: label, matching: find.byType(Card)),
        findsNothing,
      );
      final total = tester.widget<Text>(
        _inCheckout(find.text('2,400 DT')).first,
      );
      expect(total.style?.fontSize, 20);
      expect(total.style?.fontWeight, FontWeight.w700);
      expect(find.text('Confirmer la commande'), findsOneWidget);
    });

    testWidgets('the pickup row is a 48 px target that opens the sheet', (
      tester,
    ) async {
      await _openCart(tester);
      await _openCheckout(tester);
      final row = find.byKey(const Key('pickup-field'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      await tester.tap(row);
      await tester.pumpAndSettle();
      // The existing sheet: times grouped under their day.
      expect(find.textContaining('Aujourd'), findsWidgets);
    });

    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.65), (402.0, 1.0)]) {
      testWidgets('payment and lines stay whole at $width px, $scale×', (
        tester,
      ) async {
        await _openCart(tester, size: Size(width, 3000), textScale: scale);
        await _openCheckout(tester);
        expect(tester.takeException(), isNull);
        // "À la récupération" is one piece of text, never split mid-word.
        final payment = _inCheckout(find.text('À la récupération'));
        expect(payment, findsOneWidget);
        expect(tester.getRect(payment).right, lessThanOrEqualTo(width));
        final painter = TextPainter(
          text: const TextSpan(
            text: 'À la récupération',
            style: TextStyle(fontSize: 14, fontFamily: 'Inter'),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout();
        // Whole words: the box is at least as wide as the text needs, or it
        // wraps between words (at most two lines).
        expect(tester.getSize(payment).height, lessThan(painter.height * 2.5));
      });
    }
  });

  group('text size', () {
    testWidgets('at 1.3× the pictures stay and nothing overflows', (
      tester,
    ) async {
      await _openCart(tester, size: const Size(360, 1600), textScale: 1.3);
      expect(_inCart(find.byType(ProductImage)), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _openCheckout(tester);
      expect(_inCheckout(find.byType(ProductImage)), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 2× the pictures step aside and the lines are as before', (
      tester,
    ) async {
      await _openCart(tester, size: const Size(320, 2400), textScale: 2);
      expect(_inCart(find.byType(ProductImage)), findsNothing);
      expect(_inCart(find.text('Banane')), findsOneWidget);
      expect(_inCart(find.text('Mayonnaise')), findsOneWidget);
      expect(find.byTooltip('Augmenter la quantité de Banane'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _openCheckout(tester);
      expect(_inCheckout(find.byType(ProductImage)), findsNothing);
      expect(_inCheckout(find.text('Banane')), findsOneWidget);
      expect(find.text('Confirmer la commande'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
