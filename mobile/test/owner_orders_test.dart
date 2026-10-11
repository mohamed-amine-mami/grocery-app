import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/app_services.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/core/utils/date_formatters.dart';
import 'package:grocery_mobile/ui/features/orders/view_models/owner_orders_view_model.dart';
import 'package:grocery_mobile/ui/features/orders/views/owner_orders_view.dart';

import 'fakes.dart';

Future<FakeOrdersRepository> _pump(
  WidgetTester tester, {
  List<Order> orders = const [],
  bool fails = false,
  Completer<void>? gate,
  bool openTab = true,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = FakeOrdersRepository(ApiClient(), orders: orders, fails: fails)
    ..gate = gate;
  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
    ordersRepository: (_) => repo,
  );
  if (openTab) {
    await _openOrders(tester);
  }
  return repo;
}

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _openOrders(WidgetTester tester) async {
  await tester.tap(_navLabel('Commandes'));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_navLabel(label));
  await tester.pumpAndSettle();
}

/// Pulls the order list down, the way an owner refreshes it.
Future<void> _pullToRefresh(WidgetTester tester) async {
  // The indicator wants a drag of a quarter of the (tall) test screen.
  await tester.drag(find.byType(ListView).first, const Offset(0, 1800));
  await tester.pumpAndSettle();
}

/// Taps a filter chip (the row scrolls sideways, so bring it into view).
Future<void> _selectChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(_chip(label));
  await tester.pumpAndSettle();
  await tester.tap(_chip(label));
  await tester.pumpAndSettle();
}

/// Walks the app through lifecycle states in the order the platform does.
void _lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// The visible tab's vertical scrollable (the filter row scrolls sideways).
Finder _verticalScrollable() => find
    .byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    )
    .first;

Finder _chip(String label) =>
    find.widgetWithText(ChoiceChip, label, skipOffstage: false);

void main() {
  group('navigation', () {
    testWidgets('the Commandes tab is enabled and opens the order list', (
      tester,
    ) async {
      await _pump(tester, openTab: false);
      expect(_navLabel('Commandes'), findsOneWidget);
      await _openOrders(tester);
      expect(find.text('Commandes'), findsNWidgets(2)); // tab + title
      expect(find.text('Aucune commande'), findsOneWidget);
    });
  });

  group('list', () {
    testWidgets('shows a loading state, then the orders', (tester) async {
      final gate = Completer<void>();
      final repo = FakeOrdersRepository(ApiClient(), orders: [fakeOrder()])
        ..gate = gate;
      await tester.pumpWidget(
        AppServices(
          storeRepository: FakeStoreRepository(ApiClient()),
          catalogRepository: FakeCatalogRepository(ApiClient()),
          storeProductsRepository: FakeStoreProductsRepository(ApiClient()),
          ordersRepository: repo,
          customerStoresRepository: FakeCustomerStoresRepository(ApiClient()),
          customerOrdersRepository: FakeCustomerOrdersRepository(ApiClient()),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const OwnerOrdersView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('K7M2QX'), findsNothing);

      repo.gate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('K7M2QX'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('each card shows code, customer, pickup, total and status', (
      tester,
    ) async {
      final pickup = DateTime.now().toUtc().add(const Duration(hours: 4));
      await _pump(
        tester,
        orders: [
          fakeOrder(
            id: 1,
            code: 'AB12CD',
            customerName: 'Sana Ben Ali',
            requestedPickupAt: pickup,
          ),
          fakeOrder(
            id: 2,
            code: 'ZZ99YY',
            status: OrderStatus.readyForPickup,
            customerName: 'Karim Trabelsi',
            items: [fakeOrderItem(id: 21, lineTotal: 5400)],
          ),
        ],
      );

      final first = find.ancestor(
        of: find.text('AB12CD'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: first, matching: find.text('Sana Ben Ali')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: first,
          matching: find.text(DateFormatFr.pickup(pickup)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('En attente')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('3,000 DT')),
        findsOneWidget,
      );

      final second = find.ancestor(
        of: find.text('ZZ99YY'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: second, matching: find.text('Prête à retirer')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: second, matching: find.text('5,400 DT')),
        findsOneWidget,
      );
      expect(find.text('Karim Trabelsi'), findsOneWidget);
    });

    testWidgets('lists newest first and never shows stock or internal ids', (
      tester,
    ) async {
      await _pump(
        tester,
        orders: [
          fakeOrder(id: 1, code: 'OLD111'),
          fakeOrder(id: 2, code: 'NEW222'),
        ],
      );
      final newer = tester.getTopLeft(find.text('NEW222')).dy;
      final older = tester.getTopLeft(find.text('OLD111')).dy;
      expect(newer, lessThan(older));
      expect(find.textContaining('Stock'), findsNothing);
      expect(find.textContaining('stock'), findsNothing);
      expect(find.text('1'), findsNothing); // no raw order id
    });

    testWidgets('an empty list says so and invites a refresh', (tester) async {
      await _pump(tester);
      expect(find.text('Aucune commande'), findsOneWidget);
      expect(
        find.text('Les nouvelles commandes apparaîtront ici.'),
        findsOneWidget,
      );
    });

    testWidgets('an unreachable server shows the failure state, retry works', (
      tester,
    ) async {
      final repo = await _pump(tester, fails: true);
      expect(find.text('Impossible de charger les commandes.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);

      repo
        ..fails = false
        ..add(fakeOrder());
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('K7M2QX'), findsOneWidget);
    });

    testWidgets('pull-to-refresh requests fresh data and keeps the filter', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        orders: [
          fakeOrder(id: 1, code: 'PEND01'),
          fakeOrder(id: 2, code: 'CONF02', status: OrderStatus.confirmed),
        ],
      );
      await _selectChip(tester, 'Confirmée');
      expect(find.text('CONF02'), findsOneWidget);
      expect(find.text('PEND01'), findsNothing);

      repo.add(fakeOrder(id: 3, code: 'CONF03', status: OrderStatus.confirmed));
      repo.listCalls.clear();
      await _pullToRefresh(tester);
      await tester.pumpAndSettle();

      expect(repo.listCalls, isNotEmpty);
      expect(repo.listCalls.first.status, OrderStatus.confirmed);
      expect(find.text('CONF03'), findsOneWidget);
      expect(find.text('PEND01'), findsNothing);
      expect(tester.widget<ChoiceChip>(_chip('Confirmée')).selected, isTrue);
    });

    testWidgets('a failed refresh keeps the list and says so', (tester) async {
      final repo = await _pump(tester, orders: [fakeOrder()]);
      repo.fails = true;
      await _pullToRefresh(tester);
      await tester.pumpAndSettle();
      expect(find.text('K7M2QX'), findsOneWidget);
      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a long list offers more pages, within the backend’s limits', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        orders: [
          for (var i = 1; i <= 25; i++)
            fakeOrder(id: i, code: 'ORD${i.toString().padLeft(3, '0')}'),
        ],
      );
      expect(repo.listCalls.first.limit, lessThanOrEqualTo(50));
      expect(find.text('ORD025', skipOffstage: false), findsOneWidget);
      expect(find.text('ORD005', skipOffstage: false), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Voir plus de commandes'),
        400,
        scrollable: _verticalScrollable(),
      );
      await tester.ensureVisible(find.text('Voir plus de commandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir plus de commandes'));
      await tester.pumpAndSettle();
      expect(repo.listCalls.last.page, 2);
      expect(repo.listCalls.last.limit, lessThanOrEqualTo(50));
      await tester.scrollUntilVisible(
        find.text('ORD001'),
        400,
        scrollable: _verticalScrollable(),
      );
      expect(find.text('ORD001'), findsOneWidget);
      expect(find.text('Voir plus de commandes'), findsNothing);
    });
  });

  group('status filters', () {
    testWidgets(
      'offers the agreed French filters, and only the real statuses',
      (tester) async {
        await _pump(tester);
        for (final label in [
          'Toutes',
          'En attente',
          'Confirmée',
          'Prête',
          'Terminée',
          'Annulée',
          'Non récupérée',
        ]) {
          expect(_chip(label), findsOneWidget, reason: label);
        }
        expect(find.byType(ChoiceChip, skipOffstage: false), findsNWidgets(7));
        expect(tester.widget<ChoiceChip>(_chip('Toutes')).selected, isTrue);
      },
    );

    testWidgets('each filter reloads the list for that status', (tester) async {
      final repo = await _pump(
        tester,
        orders: [
          fakeOrder(id: 1, code: 'PEND01'),
          fakeOrder(id: 2, code: 'CONF02', status: OrderStatus.confirmed),
          fakeOrder(id: 3, code: 'REDY03', status: OrderStatus.readyForPickup),
          fakeOrder(id: 4, code: 'DONE04', status: OrderStatus.completed),
          fakeOrder(id: 5, code: 'CANC05', status: OrderStatus.cancelled),
          fakeOrder(id: 6, code: 'MISS06', status: OrderStatus.noShow),
        ],
      );

      final expected = {
        'En attente': (OrderStatus.pending, 'PEND01'),
        'Confirmée': (OrderStatus.confirmed, 'CONF02'),
        'Prête': (OrderStatus.readyForPickup, 'REDY03'),
        'Terminée': (OrderStatus.completed, 'DONE04'),
        'Annulée': (OrderStatus.cancelled, 'CANC05'),
        'Non récupérée': (OrderStatus.noShow, 'MISS06'),
      };
      for (final entry in expected.entries) {
        repo.listCalls.clear();
        await _selectChip(tester, entry.key);

        expect(repo.listCalls.first.status, entry.value.$1, reason: entry.key);
        expect(find.text(entry.value.$2), findsOneWidget, reason: entry.key);
        expect(
          find.byType(Card).evaluate().length,
          greaterThan(1),
        ); // the pending header and one order
        expect(tester.widget<ChoiceChip>(_chip(entry.key)).selected, isTrue);
      }

      repo.listCalls.clear();
      await _selectChip(tester, 'Toutes');
      expect(repo.listCalls.first.status, isNull);
      expect(find.text('PEND01'), findsOneWidget);
      expect(find.text('MISS06'), findsOneWidget);
    });

    testWidgets('an empty filter names the status', (tester) async {
      await _pump(tester, orders: [fakeOrder()]);
      await _selectChip(tester, 'Annulée');
      expect(find.text('Aucune commande · Annulée'), findsOneWidget);
    });
  });

  group('pending count', () {
    testWidgets('is shown prominently, from the backend', (tester) async {
      await _pump(
        tester,
        orders: [
          fakeOrder(id: 1),
          fakeOrder(id: 2),
          fakeOrder(id: 3, status: OrderStatus.confirmed),
        ],
      );
      expect(find.byKey(const Key('pending-count')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('pending-count'))).data,
        '2',
      );
      expect(find.text('commandes en attente'), findsOneWidget);
    });

    testWidgets('is singular for one and a calm line for none', (tester) async {
      final repo = await _pump(tester, orders: [fakeOrder()]);
      expect(find.text('commande en attente'), findsOneWidget);

      repo.replace(fakeOrder(status: OrderStatus.confirmed));
      await _pullToRefresh(tester);
      await tester.pumpAndSettle();
      expect(find.text('Aucune commande en attente'), findsOneWidget);
      expect(find.byKey(const Key('pending-count')), findsNothing);
    });

    testWidgets('does not depend on the selected filter', (tester) async {
      await _pump(
        tester,
        orders: [
          fakeOrder(id: 1),
          fakeOrder(id: 2, status: OrderStatus.completed),
        ],
      );
      await _selectChip(tester, 'Terminée');
      expect(
        tester.widget<Text>(find.byKey(const Key('pending-count'))).data,
        '1',
      );
    });

    testWidgets('tapping it filters to the pending orders', (tester) async {
      final repo = await _pump(
        tester,
        orders: [
          fakeOrder(id: 1, code: 'PEND01'),
          fakeOrder(id: 2, code: 'CONF02', status: OrderStatus.confirmed),
        ],
      );
      repo.listCalls.clear();
      await tester.tap(find.byKey(const Key('pending-count')));
      await tester.pumpAndSettle();
      expect(repo.listCalls.first.status, OrderStatus.pending);
      expect(find.text('CONF02'), findsNothing);
    });

    testWidgets('updates on pull-to-refresh', (tester) async {
      final repo = await _pump(tester, orders: [fakeOrder(id: 1)]);
      repo.add(fakeOrder(id: 2));
      await _pullToRefresh(tester);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('pending-count'))).data,
        '2',
      );
    });
  });

  group('polling in the app', () {
    testWidgets(
      'refreshes the open tab every 30 seconds, new orders included',
      (tester) async {
        final repo = await _pump(
          tester,
          orders: [fakeOrder(id: 1, code: 'FIRST1')],
        );
        repo.add(fakeOrder(id: 2, code: 'SECND2'));
        expect(find.text('SECND2'), findsNothing);

        await tester.pump(ordersPollInterval);
        await tester.pumpAndSettle();

        expect(find.text('SECND2'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('pending-count'))).data,
          '2',
        );
      },
    );

    testWidgets('does not poll while another tab is showing', (tester) async {
      final repo = await _pump(tester, orders: [fakeOrder()]);
      await _openTab(tester, 'Catalogue');
      repo.listCalls.clear();

      await tester.pump(ordersPollInterval * 3);
      expect(repo.listCalls, isEmpty);

      // Coming back refreshes at once and polling resumes.
      await _openOrders(tester);
      expect(repo.listCalls, isNotEmpty);
      repo.listCalls.clear();
      await tester.pump(ordersPollInterval);
      await tester.pumpAndSettle();
      expect(repo.listCalls, isNotEmpty);
    });

    testWidgets('pauses in the background and refreshes on return', (
      tester,
    ) async {
      final repo = await _pump(tester, orders: [fakeOrder()]);
      _lifecycle(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await tester.pump();
      repo.listCalls.clear();

      await tester.pump(ordersPollInterval * 3);
      expect(repo.listCalls, isEmpty);

      _lifecycle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pumpAndSettle();
      expect(repo.listCalls, isNotEmpty);

      repo.listCalls.clear();
      await tester.pump(ordersPollInterval);
      await tester.pumpAndSettle();
      expect(repo.listCalls, isNotEmpty);
    });

    testWidgets('keeps the filter across polling ticks', (tester) async {
      final repo = await _pump(
        tester,
        orders: [
          fakeOrder(id: 1, code: 'PEND01'),
          fakeOrder(id: 2, code: 'CONF02', status: OrderStatus.confirmed),
        ],
      );
      await _selectChip(tester, 'Confirmée');
      repo.listCalls.clear();

      await tester.pump(ordersPollInterval);
      await tester.pumpAndSettle();

      expect(repo.listCalls.where((c) => c.limit != 1).map((c) => c.status), [
        OrderStatus.confirmed,
      ]);
      expect(find.text('PEND01'), findsNothing);
      expect(find.text('CONF02'), findsOneWidget);
    });

    testWidgets('the timer is gone once the tab is disposed', (tester) async {
      final repo = await _pump(tester, orders: [fakeOrder()]);
      await tester.pumpWidget(const SizedBox());
      repo.listCalls.clear();
      await tester.pump(ordersPollInterval * 3);
      expect(repo.listCalls, isEmpty);
    });
  });
}
