import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/widgets/app_primary_button.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/customer_scope.dart';
import 'package:grocery_mobile/ui/features/customer/views/cart_view.dart';

import 'fakes.dart';

CustomerProduct _piece(int id, String name, int price, {int max = 12}) =>
    fakeCustomerProduct(
      id: id,
      name: name,
      unit: SaleUnit.piece,
      priceMillimes: price,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: max,
    );

/// Three lines (1 000 + 2 500 + 4 000 = 7 500 millimes → "7,500 DT"), on the
/// Panier tab.
Future<void> _openCart(
  WidgetTester tester, {
  Size size = const Size(402, 874),
  double textScale = 1,
  List<CustomerProduct>? products,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final catalogue =
      products ??
      [
        _piece(1, 'Yaourt', 1000),
        _piece(2, 'Fromage', 2500),
        _piece(3, 'Miel', 4000),
      ];
  final repository = FakeCustomerStoresRepository(
    ApiClient(),
    stores: [fakeCustomerStore(id: 10, name: 'Menzah Market')],
    products: {10: catalogue},
  );
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerStoresRepository: (_) => repository,
  );
  // Put the lines in the cart directly (the catalogue grid is not what this
  // file is about), then open the Panier tab.
  final scope = CustomerScope.of(tester.element(find.byType(Scaffold).first));
  final store = fakeCustomerStore(id: 10, name: 'Menzah Market');
  for (final p in catalogue) {
    scope.cart.add(store, p);
  }
  scope.navigation.select(CustomerTab.cart);
  await tester.pumpAndSettle();
}

Finder get _commander => find.widgetWithText(AppPrimaryButton, 'Commander');
Finder get _confirm =>
    find.widgetWithText(AppPrimaryButton, 'Confirmer la commande');

/// [amount] shown inside [button] (the bar), not in a total card.
Finder _inButton(Finder button, String amount) =>
    find.descendant(of: button, matching: find.text(amount));

bool _onScreen(WidgetTester tester, Finder finder, double height) {
  final rect = tester.getRect(finder);
  return rect.top >= 0 && rect.bottom <= height;
}

Future<void> _toCheckout(WidgetTester tester) async {
  await tester.tap(find.text('Commander'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  group('cart action bar', () {
    testWidgets('shows the estimated total beside "Commander"', (tester) async {
      await _openCart(tester);
      expect(_commander, findsOneWidget);
      expect(_inButton(_commander, '7,500 DT'), findsOneWidget);
      // The in-page total card is still there, unchanged.
      expect(find.text('Total estimé'), findsOneWidget);
      expect(find.text('7,500 DT'), findsNWidgets(2));
    });

    testWidgets('follows quantity changes and removal, immediately', (
      tester,
    ) async {
      await _openCart(tester);
      final cart = CustomerScope.of(tester.element(find.byType(CartView))).cart;

      await tester.tap(find.byTooltip('Augmenter la quantité de Yaourt'));
      await tester.pumpAndSettle();
      expect(_inButton(_commander, '8,500 DT'), findsOneWidget);
      expect(cart.estimatedTotalMillimes, 8500);

      await tester.tap(find.byTooltip('Diminuer la quantité de Yaourt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retirer Miel du panier'));
      await tester.pumpAndSettle();
      expect(_inButton(_commander, '3,500 DT'), findsOneWidget);
      expect(find.text('Miel'), findsNothing);
    });

    testWidgets('a blocked cart keeps the bar, disabled, with the same total', (
      tester,
    ) async {
      await _openCart(tester);
      final cart = CustomerScope.of(tester.element(find.byType(CartView))).cart;
      cart.syncWithCatalog(10, [
        _piece(1, 'Yaourt', 1000),
        fakeCustomerProduct(
          id: 2,
          name: 'Fromage',
          unit: SaleUnit.piece,
          priceMillimes: 2500,
          minQuantity: 1,
          quantityStep: 1,
          isOrderable: false,
        ),
        _piece(3, 'Miel', 4000),
      ]);
      await tester.pumpAndSettle();

      final button = tester.widget<AppPrimaryButton>(_commander);
      expect(button.onPressed, isNull);
      expect(
        find.text('Corrigez votre panier avant de commander.'),
        findsOneWidget,
      );
    });

    testWidgets('1.65× on a phone: the total is beside the action, on screen', (
      tester,
    ) async {
      await _openCart(tester, textScale: 1.65);
      expect(_inButton(_commander, '7,500 DT'), findsOneWidget);
      expect(_onScreen(tester, _commander, 874), isTrue);
      expect(tester.getSize(_commander).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('2× on 320 px: no overflow, readable, 48 pt high', (
      tester,
    ) async {
      await _openCart(tester, size: const Size(320, 700), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(_inButton(_commander, '7,500 DT'), findsOneWidget);
      expect(_commander, findsOneWidget);
      expect(tester.getSize(_commander).height, greaterThanOrEqualTo(48));
      final label = tester.getRect(
        find.descendant(of: _commander, matching: find.text('Commander')),
      );
      final total = tester.getRect(_inButton(_commander, '7,500 DT'));
      expect(label.overlaps(total), isFalse);
      expect(total.right, lessThanOrEqualTo(320));
    });

    testWidgets('a long total does not overlap the label', (tester) async {
      await _openCart(
        tester,
        size: const Size(320, 700),
        textScale: 1.65,
        products: [_piece(1, 'Coffret cadeau', 9000000, max: 12)],
      );
      final cart = CustomerScope.of(tester.element(find.byType(CartView))).cart;
      for (var i = 0; i < 6; i++) {
        cart.increment(1);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = tester.getRect(
        find.descendant(of: _commander, matching: find.text('Commander')),
      );
      final total = tester.getRect(
        find.descendant(of: _commander, matching: find.text('63000,000 DT')),
      );
      expect(label.overlaps(total), isFalse);
    });
  });

  group('checkout', () {
    testWidgets('payment mode comes before the order, without scrolling', (
      tester,
    ) async {
      await _openCart(tester);
      await _toCheckout(tester);

      final payment = find.text('À la récupération');
      expect(payment, findsOneWidget);
      expect(_onScreen(tester, payment, 874), isTrue);
      expect(
        tester.getTopLeft(payment).dy,
        lessThan(tester.getTopLeft(find.text('Votre commande')).dy),
      );
      // The wording is as before, and the pickup note still says "souhaitée".
      expect(find.text('Paiement'), findsOneWidget);
      expect(
        find.text('C’est une heure souhaitée, pas un créneau réservé.'),
        findsOneWidget,
      );
    });

    testWidgets(
      '402 × 874, three lines: payment and total visible unscrolled',
      (tester) async {
        await _openCart(tester);
        await _toCheckout(tester);

        expect(_onScreen(tester, find.text('À la récupération'), 874), isTrue);
        expect(_inButton(_confirm, '7,500 DT'), findsOneWidget);
        expect(_onScreen(tester, _confirm, 874), isTrue);
        // The in-page total is unchanged (it may be below the fold).
        expect(find.text('Total estimé'), findsOneWidget);
        expect(tester.getSize(_confirm).height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets('the confirm bar shows the same estimate as the cart', (
      tester,
    ) async {
      await _openCart(tester);
      await tester.tap(find.byTooltip('Augmenter la quantité de Fromage'));
      await tester.pumpAndSettle();
      await _toCheckout(tester);
      expect(_inButton(_confirm, '10,000 DT'), findsOneWidget);
    });

    testWidgets('2× on 320 px: no overflow, label and total apart', (
      tester,
    ) async {
      await _openCart(tester, size: const Size(320, 700), textScale: 2);
      await _toCheckout(tester);

      expect(tester.takeException(), isNull);
      expect(_confirm, findsOneWidget);
      expect(tester.getSize(_confirm).height, greaterThanOrEqualTo(48));
      final label = tester.getRect(
        find.descendant(
          of: _confirm,
          matching: find.text('Confirmer la commande'),
        ),
      );
      final total = tester.getRect(_inButton(_confirm, '7,500 DT'));
      expect(label.overlaps(total), isFalse);
      expect(total.right, lessThanOrEqualTo(320));
    });
  });
}
