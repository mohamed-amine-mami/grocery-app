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
      // The catalogue's component, small, and the whole picture.
      expect(images.every((i) => i.size == 56), isTrue);
      expect(images.every((i) => i.fit == BoxFit.contain), isTrue);

      // Left of the name, level with it.
      final image = tester.getRect(_inCart(find.byType(ProductImage)).first);
      final name = tester.getTopLeft(_inCart(find.text('Banane')));
      expect(image.right, lessThan(name.dx));
      // (The name sits on the amount's baseline, an 18 pt amount: ~3 px lower.)
      expect(image.top, closeTo(name.dy, 4));
      // And the line's price stays at the right edge, after the name.
      expect(
        tester.getTopRight(_inCart(find.text('0,900 DT'))).dx,
        greaterThan(tester.getTopRight(_inCart(find.text('Banane'))).dx),
      );
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
      expect(
        _inCart(find.bySemanticsLabel('Image du produit')),
        findsNothing,
      );
      // The name and the quantity controls are still there to be read.
      expect(_inCart(find.bySemanticsLabel(RegExp('Banane'))), findsWidgets);
      expect(
        find.byTooltip('Augmenter la quantité de Banane'),
        findsOneWidget,
      );
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
      expect(images.every((i) => i.size == 56), isTrue);
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
      final image = tester.getRect(_inCheckout(find.byType(ProductImage)).first);
      expect(
        image.top,
        closeTo(tester.getTopLeft(_inCheckout(find.text('Banane'))).dy, 4),
      );
    });
  });

  group('line amount and tile', () {
    // The amount's role is the same on every screen: titleMedium, on the
    // first baseline of the name.
    void expectAmount(WidgetTester tester, Finder scope, String amount) {
      final text = tester.widget<Text>(
        find.descendant(of: scope, matching: find.text(amount)).first,
      );
      expect(text.style?.fontSize, 18);
      expect(text.style?.fontWeight, FontWeight.w600);
    }

    testWidgets('the cart line’s amount is titleMedium on the name’s baseline', (
      tester,
    ) async {
      await _openCart(tester);
      expectAmount(tester, find.byType(CartView), '0,900 DT');
      final name = tester.getRect(_inCart(find.text('Banane')));
      final amount = tester.getRect(_inCart(find.text('0,900 DT')));
      // Same first line: the amount's box and the name's overlap vertically,
      // and the amount starts no lower than the name's top by more than the
      // difference of their line heights.
      expect(amount.top, closeTo(name.top, 4));
      expect(amount.right, greaterThan(name.right));
    });

    testWidgets('the checkout line’s amount is the same role', (tester) async {
      await _openCart(tester);
      await _openCheckout(tester);
      expectAmount(tester, find.byType(CheckoutView), '0,900 DT');
      final name = tester.getRect(_inCheckout(find.text('Banane')));
      final amount = tester.getRect(_inCheckout(find.text('0,900 DT')));
      expect(amount.top, closeTo(name.top, 4));
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
      for (final element in tiles.evaluate()) {
        final box = element.widget as ColoredBox;
        expect(box.color, AppColors.primary.withValues(alpha: 0.08));
        expect(tester.getSize(find.byWidget(box)), const Size(56, 56));
      }
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
        final unitSize = tester.getSize(unitPrice);
        final quantitySize = tester.getSize(quantity);
        // One line of the same text style: same height as the quantity piece.
        expect(unitSize.height, quantitySize.height);
        // Both pieces are fully visible, left-aligned with the name.
        expect(
          tester.getTopLeft(quantity).dx,
          tester.getTopLeft(_inCheckout(find.text('Mayonnaise'))).dx,
        );
        expect(tester.getRect(unitPrice).right, lessThanOrEqualTo(width));
        // Under the name: the unit price is not squeezed by the amount.
        expect(
          tester.getTopLeft(quantity).dy,
          greaterThan(tester.getTopLeft(_inCheckout(find.text('Mayonnaise'))).dy),
        );
        // The amount keeps its role.
        final amount = tester.widget<Text>(
          _inCheckout(find.text('1,500 DT')).first,
        );
        expect(amount.style?.fontSize, 18);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a screen reader still hears quantity and unit price', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _openCart(tester);
      await _openCheckout(tester);
      expect(_inCheckout(find.bySemanticsLabel(RegExp('1 pièce ·'))), findsWidgets);
      expect(
        _inCheckout(find.bySemanticsLabel(RegExp('1,500 DT / pièce'))),
        findsWidgets,
      );
      semantics.dispose();
    });
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
