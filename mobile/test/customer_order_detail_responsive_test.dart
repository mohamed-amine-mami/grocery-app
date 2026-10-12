import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/utils/date_formatters.dart';
import 'package:grocery_mobile/ui/features/customer/views/customer_order_detail_view.dart';

import 'fakes.dart';

/// Opens the order detail the way the checkout does, on a phone-sized view.
Future<void> _openDetail(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  required bool justPlaced,
  required OrderStatus status,
  required String code,
  required DateTime pickup,
  String storeName = 'Menzah Market',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final order = fakeCustomerOrder(
    code: code,
    status: status,
    requestedPickupAt: pickup,
    storeName: storeName,
  );
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerOrdersRepository: (_) =>
        FakeCustomerOrdersRepository(ApiClient(), orders: [order]),
  );
  Navigator.of(tester.element(find.byType(NavigationBar))).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          CustomerOrderDetailView(order: order, justPlaced: justPlaced),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _inDetail => find.byType(CustomerOrderDetailView);

/// The visible part of the page: from under the app bar to above the bottom
/// bar (the cancel button) when there is one.
double _foldBottom(WidgetTester tester) {
  final bar = find.descendant(
    of: _inDetail,
    matching: find.widgetWithText(OutlinedButton, 'Annuler la commande'),
  );
  final viewport = tester.view.physicalSize.height;
  if (bar.evaluate().isEmpty) {
    return viewport;
  }
  // The bar's own padding sits above the button.
  return tester.getTopLeft(bar).dy - 16;
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  final pickup = DateTime.utc(2026, 12, 24, 17, 30);

  group('just-placed order on a 375 × 667 phone', () {
    testWidgets('code and pickup time are above the fold and unclipped', (
      tester,
    ) async {
      await _openDetail(
        tester,
        size: const Size(375, 667),
        justPlaced: true,
        status: OrderStatus.pending,
        code: 'K7M2QX',
        pickup: pickup,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Commande envoyée'), findsOneWidget);

      final code = find.text('K7M2QX');
      final time = find.text(DateFormatFr.pickup(pickup));
      final fold = _foldBottom(tester);

      // Above the fold as it opens (measured: code ~379, time ~529 of 587).
      expect(tester.getBottomLeft(code).dy, lessThanOrEqualTo(fold));
      expect(tester.getBottomLeft(time).dy, lessThanOrEqualTo(fold));

      // Reachable: scrolling brings each fully into view, unclipped.
      for (final finder in [code, time]) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(375));
        expect(rect.bottom, lessThanOrEqualTo(fold + 0.5));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the banner’s two actions and the page stay usable', (
      tester,
    ) async {
      await _openDetail(
        tester,
        size: const Size(375, 667),
        justPlaced: true,
        status: OrderStatus.pending,
        code: 'K7M2QX',
        pickup: pickup,
      );
      for (final label in ['Voir mes commandes', 'Continuer mes achats']) {
        final button = find.descendant(
          of: _inDetail,
          matching: find.text(label),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.getRect(button).right, lessThanOrEqualTo(375));
      }
      expect(find.text('Annuler la commande'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  const steps = ['Envoyée', 'Confirmée', 'Prête', 'Récupérée'];

  group('status tracker at normal text size', () {
    testWidgets('shows all four icons and all four step names', (tester) async {
      await _openDetail(
        tester,
        size: const Size(375, 1200),
        justPlaced: false,
        status: OrderStatus.confirmed,
        code: 'K7M2QX',
        pickup: pickup,
      );
      for (final step in steps) {
        expect(find.text(step), findsWidgets, reason: step);
      }
      // Reached: sent and confirmed; to come: ready and collected.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      expect(
        find.byIcon(Icons.radio_button_unchecked_rounded),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('320 px wide at 2× text', () {
    // status, the step it stands on, how many times that name is on screen
    // (the status badge also says "Confirmée" once).
    final cases = [
      (OrderStatus.pending, 0, 1),
      (OrderStatus.confirmed, 1, 2),
      (OrderStatus.readyForPickup, 2, 1),
      (OrderStatus.completed, 3, 1),
    ];
    for (final (status, reached, nameCount) in cases) {
      testWidgets('the tracker names only the step it is on: ${status.name}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _openDetail(
          tester,
          size: const Size(320, 2400),
          textScale: 2,
          justPlaced: status == OrderStatus.pending,
          status: status,
          code: 'K7M2QX',
          pickup: pickup,
          storeName: 'Supermarché Coopérative de la Médina',
        );
        expect(tester.takeException(), isNull);

        // All four icons are still there: the steps reached are ticked.
        final banner = status == OrderStatus.pending ? 1 : 0;
        expect(
          find.byIcon(Icons.check_circle_rounded),
          findsNWidgets(reached + 1 + banner),
        );
        expect(
          find.byIcon(Icons.radio_button_unchecked_rounded),
          findsNWidgets(3 - reached),
        );

        // Only the current step's name, whole, on one line, inside the screen.
        for (final (index, step) in steps.indexed) {
          if (index != reached) {
            expect(find.text(step), findsNothing, reason: '$step is hidden');
          }
        }
        final name = find.text(steps[reached]);
        expect(name, findsNWidgets(nameCount));
        final painter = TextPainter(
          text: TextSpan(
            text: steps[reached],
            style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
          ),
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(2),
        )..layout();
        final shown = name.evaluate().length - 1; // the tracker's, last one
        final rect = tester.getRect(name.at(shown));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, lessThan(painter.height * 1.5), reason: 'one line');

        // Each step is still announced, whatever the text size.
        for (final (index, step) in steps.indexed) {
          expect(
            find.bySemanticsLabel(
              RegExp(
                index <= reached
                    ? 'Étape $step : atteinte'
                    : 'Étape $step : à venir',
              ),
            ),
            findsWidgets,
            reason: step,
          );
        }

        // The pickup code and time stay inside the screen.
        expect(
          tester.getRect(find.text('K7M2QX')).right,
          lessThanOrEqualTo(320),
        );
        expect(
          tester.getRect(find.text(DateFormatFr.pickup(pickup))).right,
          lessThanOrEqualTo(320),
        );
        semantics.dispose();
      });
    }

    testWidgets('the ready status’s long hint and badge fit', (tester) async {
      await _openDetail(
        tester,
        size: const Size(320, 2400),
        textScale: 2,
        justPlaced: false,
        status: OrderStatus.readyForPickup,
        code: 'K7M2QX',
        pickup: pickup,
      );
      expect(find.text('Prête à retirer'), findsOneWidget);
      expect(
        find.text('Votre commande est prête. Présentez votre code au magasin.'),
        findsOneWidget,
      );
      final badge = tester.getRect(find.text('Prête à retirer'));
      expect(badge.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  });

  group('line amounts', () {
    testWidgets('use the same role as the cart and checkout lines', (
      tester,
    ) async {
      await _openDetail(
        tester,
        size: const Size(375, 1200),
        justPlaced: false,
        status: OrderStatus.confirmed,
        code: 'K7M2QX',
        pickup: pickup,
      );
      final amount = tester.widget<Text>(find.text('0,900 DT'));
      expect(amount.style?.fontSize, 18);
      expect(amount.style?.fontWeight, FontWeight.w700);
      // The cart's anatomy: under the name and its meta, on its left edge.
      final name = tester.getRect(find.text('Tomate'));
      final price = tester.getRect(find.text('0,900 DT'));
      expect(price.left, closeTo(name.left, 1));
      expect(price.top, greaterThan(name.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  group('confirmed hint', () {
    testWidgets('says the store confirmed, not that it is preparing', (
      tester,
    ) async {
      await _openDetail(
        tester,
        size: const Size(375, 800),
        justPlaced: false,
        status: OrderStatus.confirmed,
        code: 'K7M2QX',
        pickup: pickup,
      );
      expect(
        find.text('Le magasin a confirmé votre commande.'),
        findsOneWidget,
      );
      expect(find.textContaining('prépare'), findsNothing);
    });
  });
}
