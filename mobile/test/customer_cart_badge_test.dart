import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/features/customer/views/cart_view.dart';

import 'fakes.dart';

Future<void> _openStore(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = FakeCustomerStoresRepository(
    ApiClient(),
    stores: [fakeCustomerStore(id: 10, name: 'Menzah Market')],
    products: {
      10: [
        fakeCustomerProduct(id: 1, name: 'Banane'),
        fakeCustomerProduct(id: 2, name: 'Tomate'),
      ],
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
}

Finder get _navBar => find.byType(NavigationBar);

void main() {
  testWidgets('an empty cart shows no count badge', (tester) async {
    await _openStore(tester);
    // The store view hides the tab bar; go back to the tabs.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _navBar, matching: find.byType(Badge)),
      findsNothing,
    );
  });

  testWidgets('a cart count is Citrus with Primary Text, and counts lines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openStore(tester);
    await tester.tap(find.byTooltip('Ajouter Banane'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ajouter Tomate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final badge = tester.widget<Badge>(
      find.descendant(of: _navBar, matching: find.byType(Badge)),
    );
    expect(badge.backgroundColor, AppColors.accent);
    expect(badge.textColor, AppColors.textPrimary);
    // Products (lines), not units; the number is shown as text.
    expect((badge.label! as Text).data, '2');
    expect(
      find.descendant(of: _navBar, matching: find.text('2')),
      findsOneWidget,
    );
    // Still announced with its destination.
    expect(find.bySemanticsLabel(RegExp('Panier')), findsWidgets);

    // Not the error colour.
    expect(badge.backgroundColor, isNot(AppColors.error));
    semantics.dispose();
  });

  testWidgets('the Panier tab still opens the cart', (tester) async {
    await _openStore(tester);
    await tester.tap(find.byTooltip('Ajouter Banane'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: _navBar, matching: find.text('Panier')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CartView), findsOneWidget);
    expect(find.text('Total estimé'), findsOneWidget);
  });
}
