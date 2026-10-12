import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_order.dart';
import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/core/utils/date_formatters.dart';
import 'package:grocery_mobile/ui/features/orders/view_models/owner_orders_view_model.dart'
    show ordersPollInterval;

import 'fakes.dart';

Future<FakeCustomerOrdersRepository> _pump(
  WidgetTester tester, {
  List<CustomerOrder> orders = const [],
  Size size = const Size(800, 3000),
  bool openTab = true,
  FakeCustomerOrdersRepository? repo,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake =
      repo ?? FakeCustomerOrdersRepository(ApiClient(), orders: orders);
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerOrdersRepository: (_) => fake,
  );
  if (openTab) {
    await _tab(tester, 'Commandes');
  }
  return fake;
}

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(_navLabel(label));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openOrder(WidgetTester tester, String code) async {
  await tester.tap(find.text(code));
  await tester.pumpAndSettle();
}

void _lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Finder get _cancelButton =>
    find.widgetWithText(OutlinedButton, 'Annuler la commande');

void main() {
  group('orders list composition', () {
    testWidgets('one list surface; store first, then pickup, then code and '
        'total', (tester) async {
      await _pump(
        tester,
        orders: [
          fakeCustomerOrder(id: 1, code: 'AAA111', storeName: 'Lac Épicerie'),
          fakeCustomerOrder(
            id: 2,
            code: 'BBB222',
            status: OrderStatus.cancelled,
            storeName: 'Menzah Market',
          ),
        ],
      );
      // The orders share one card, the way the catalogue's rows do.
      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      final store = tester.getTopLeft(find.text('Lac Épicerie'));
      final code = tester.getTopLeft(find.text('AAA111'));
      expect(store.dy, lessThan(code.dy));
      // The code is a caption now; the store is the title.
      expect(
        tester.widget<Text>(find.text('Lac Épicerie')).style?.fontSize,
        18,
      );
      expect(tester.widget<Text>(find.text('AAA111')).style?.fontSize, 12);
      // The total is the strong number of the row.
      final total = tester.widget<Text>(find.text('3,300 DT').first);
      expect(total.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('a ready order says what to do, in words', (tester) async {
      await _pump(
        tester,
        orders: [
          fakeCustomerOrder(
            id: 1,
            code: 'RDY111',
            status: OrderStatus.readyForPickup,
          ),
          fakeCustomerOrder(id: 2, code: 'PEN222'),
        ],
      );
      expect(find.text('Prête à retirer'), findsOneWidget);
      // Only the ready one carries the instruction.
      expect(find.text('Présentez votre code au magasin.'), findsOneWidget);
    });

    testWidgets('rows stay whole at 2× on 320 px', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        size: const Size(320, 3000),
        orders: [
          fakeCustomerOrder(
            id: 1,
            code: 'RDY111',
            status: OrderStatus.readyForPickup,
            storeName: 'Supermarché Coopérative de la Médina',
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('RDY111'), findsOneWidget);
      expect(find.text('3,300 DT'), findsOneWidget);
      expect(
        tester.getRect(find.text('3,300 DT')).right,
        lessThanOrEqualTo(320),
      );
    });

    testWidgets('opening an order still goes to its detail', (tester) async {
      await _pump(tester, orders: [fakeCustomerOrder(id: 1, code: 'AAA111')]);
      await _openOrder(tester, 'AAA111');
      expect(find.text('Commande AAA111'), findsOneWidget);
      expect(find.text('Code de retrait'), findsOneWidget);
    });
  });

  group('order ticket', () {
    Future<void> detail(
      WidgetTester tester,
      OrderStatus status, {
      Size size = const Size(400, 3000),
    }) async {
      await _pump(
        tester,
        size: size,
        orders: [fakeCustomerOrder(id: 1, code: 'TKT123', status: status)],
      );
      await _openOrder(tester, 'TKT123');
    }

    for (final status in [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.readyForPickup,
    ]) {
      testWidgets('${status.name}: a big code and the tracker', (tester) async {
        await detail(tester, status);
        final code = tester.widget<Text>(find.text('TKT123').last);
        expect(code.style?.fontSize, 28);
        expect(code.style?.fontWeight, FontWeight.w700);
        expect(find.text('Envoyée'), findsOneWidget);
        expect(find.text('Récupérée'), findsOneWidget);
      });
    }

    for (final status in [
      OrderStatus.completed,
      OrderStatus.cancelled,
      OrderStatus.noShow,
    ]) {
      testWidgets('${status.name}: the code is quiet, nothing to present', (
        tester,
      ) async {
        await detail(tester, status);
        final code = tester.widget<Text>(find.text('TKT123').last);
        expect(code.style?.fontSize, 20);
        expect(code.style?.color, AppColors.textSecondary);
        // The way back to the store is not offered.
        expect(find.textContaining('Présentez votre code'), findsNothing);
      });
    }

    testWidgets('the total is the biggest amount and not in a card', (
      tester,
    ) async {
      await detail(tester, OrderStatus.confirmed);
      final total = tester.widget<Text>(find.text('3,300 DT'));
      expect(total.style?.fontSize, 20);
      expect(total.style?.fontWeight, FontWeight.w700);
      expect(
        find.ancestor(of: find.text('Total'), matching: find.byType(Card)),
        findsNothing,
      );
      // Line amounts are the smaller 18/700.
      final line = tester.widget<Text>(find.text('0,900 DT'));
      expect(line.style?.fontSize, 18);
    });
  });

  group('history', () {
    testWidgets(
      'lists the customer’s orders with code, store, pickup, total and status',
      (tester) async {
        final pickup = DateTime.now().toUtc().add(const Duration(hours: 5));
        await _pump(
          tester,
          orders: [
            fakeCustomerOrder(
              id: 1,
              code: 'OLD111',
              status: OrderStatus.completed,
              storeName: 'Lac Épicerie',
            ),
            fakeCustomerOrder(
              id: 2,
              code: 'NEW222',
              requestedPickupAt: pickup,
              storeName: 'Menzah Market',
            ),
          ],
        );

        // The order's row (the orders share one list surface).
        final card = find
            .ancestor(of: find.text('NEW222'), matching: find.byType(InkWell))
            .first;
        expect(
          find.descendant(of: card, matching: find.text('Menzah Market')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(DateFormatFr.pickup(pickup)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('En attente')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('3,300 DT')),
          findsOneWidget,
        );
        expect(find.text('Terminée'), findsOneWidget);
        // Newest first.
        expect(
          tester.getTopLeft(find.text('NEW222')).dy,
          lessThan(tester.getTopLeft(find.text('OLD111')).dy),
        );
        // Nothing internal.
        expect(find.textContaining('tock'), findsNothing);
      },
    );

    testWidgets('uses the customer’s French status words', (tester) async {
      await _pump(
        tester,
        orders: [
          fakeCustomerOrder(id: 1, code: 'A1', status: OrderStatus.pending),
          fakeCustomerOrder(id: 2, code: 'A2', status: OrderStatus.confirmed),
          fakeCustomerOrder(
            id: 3,
            code: 'A3',
            status: OrderStatus.readyForPickup,
          ),
          fakeCustomerOrder(id: 4, code: 'A4', status: OrderStatus.completed),
          fakeCustomerOrder(id: 5, code: 'A5', status: OrderStatus.cancelled),
          fakeCustomerOrder(id: 6, code: 'A6', status: OrderStatus.noShow),
        ],
      );
      for (final label in [
        'En attente',
        'Confirmée',
        'Prête à retirer',
        'Terminée',
        'Annulée',
        'Non retirée',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
        find.text('Non récupérée'),
        findsNothing,
      ); // that is the owner's word
      for (final internal in [
        'PENDING',
        'CONFIRMED',
        'READY_FOR_PICKUP',
        'NO_SHOW',
      ]) {
        expect(find.textContaining(internal), findsNothing);
      }
    });

    testWidgets('an empty history invites the customer to shop', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Aucune commande'), findsOneWidget);
      await tester.tap(find.text('Voir les magasins'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ouvert'),
        findsNothing,
      ); // no stores seeded, but on Magasins
      expect(find.text('Aucun magasin'), findsOneWidget);
    });

    testWidgets('a failure shows the retry state', (tester) async {
      final repo = FakeCustomerOrdersRepository(ApiClient())
        ..listError = const NetworkException('offline');
      await _pump(tester, repo: repo);
      expect(find.text('Impossible de charger vos commandes.'), findsOneWidget);
      repo
        ..listError = null
        ..add(fakeCustomerOrder());
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('K7M2QX'), findsOneWidget);
    });

    testWidgets(
      'pull-to-refresh requests fresh data; a failed pull keeps the list',
      (tester) async {
        final repo = await _pump(
          tester,
          orders: [fakeCustomerOrder(id: 1, code: 'ONE111')],
        );
        repo.add(fakeCustomerOrder(id: 2, code: 'TWO222'));
        await tester.drag(find.byType(ListView).first, const Offset(0, 1800));
        await tester.pumpAndSettle();
        expect(find.text('TWO222'), findsOneWidget);

        repo.listError = const NetworkException('offline');
        await tester.drag(find.byType(ListView).first, const Offset(0, 1800));
        await tester.pumpAndSettle();
        expect(find.text('ONE111'), findsOneWidget);
        expect(
          find.text(
            'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('pages within the backend’s limits', (tester) async {
      final repo = await _pump(
        tester,
        orders: [
          for (var i = 1; i <= 25; i++)
            fakeCustomerOrder(
              id: i,
              code: 'ORD${i.toString().padLeft(3, '0')}',
            ),
        ],
      );
      expect(repo.listCalls.first.limit, lessThanOrEqualTo(50));
      await tester.scrollUntilVisible(
        find.text('Voir plus de commandes'),
        400,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
      await tester.ensureVisible(find.text('Voir plus de commandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir plus de commandes'));
      await tester.pumpAndSettle();
      expect(repo.listCalls.last.page, 2);
    });
  });

  group('detail', () {
    testWidgets(
      'shows the pickup code, status, pickup time, lines, server total and payment',
      (tester) async {
        final pickup = DateTime.now().toUtc().add(const Duration(hours: 5));
        await _pump(
          tester,
          orders: [
            fakeCustomerOrder(
              code: 'AB12CD',
              status: OrderStatus.confirmed,
              requestedPickupAt: pickup,
            ),
          ],
        );
        await _openOrder(tester, 'AB12CD');

        expect(find.text('Commande AB12CD'), findsOneWidget);
        expect(find.text('Code de retrait'), findsOneWidget);
        expect(find.text('Confirmée'), findsWidgets);
        expect(
          find.text('Le magasin a confirmé votre commande.'),
          findsOneWidget,
        );
        expect(find.text('Retrait souhaité'), findsOneWidget);
        expect(find.text(DateFormatFr.pickup(pickup)), findsOneWidget);
        expect(find.text('Menzah Market'), findsOneWidget);
        expect(find.text('Produits · 2'), findsOneWidget);
        // Quantity and unit price are two pieces of one line.
        expect(find.text('500 g ·'), findsOneWidget);
        expect(find.text('1,800 DT / kg'), findsOneWidget);
        expect(find.text('0,900 DT'), findsOneWidget);
        expect(find.text('2 pièces ·'), findsOneWidget);
        expect(find.text('1,200 DT / pièce'), findsOneWidget);
        expect(find.text('2,400 DT'), findsOneWidget);
        expect(find.text('Total'), findsOneWidget);
        expect(find.text('3,300 DT'), findsOneWidget); // the server's total
        expect(find.text('À la récupération'), findsOneWidget);
        for (final word in ['tock', 'propriétaire']) {
          expect(find.textContaining(word), findsNothing);
        }
      },
    );

    testWidgets('shows the history, with a store cancellation’s reason', (
      tester,
    ) async {
      final t0 = DateTime.utc(2026, 10, 4, 14, 48);
      final t1 = DateTime.utc(2026, 10, 4, 15, 2);
      await _pump(
        tester,
        orders: [
          fakeCustomerOrder(
            status: OrderStatus.cancelled,
            events: [
              OrderEvent(
                toStatus: OrderStatus.pending,
                actorType: OrderActorType.client,
                createdAt: t0,
              ),
              OrderEvent(
                fromStatus: OrderStatus.pending,
                toStatus: OrderStatus.cancelled,
                actorType: OrderActorType.owner,
                reason: 'Produit épuisé',
                createdAt: t1,
              ),
            ],
          ),
        ],
      );
      await _openOrder(tester, 'K7M2QX');

      await tester.ensureVisible(find.text('Suivi'));
      expect(find.text('Commande passée'), findsOneWidget);
      expect(find.text('Commande annulée par le magasin'), findsOneWidget);
      expect(find.text('Motif : Produit épuisé'), findsWidgets);
      expect(find.text(DateFormatFr.dateTime(t1)), findsOneWidget);
      // No internal actor ids or enum names.
      expect(find.textContaining('OWNER'), findsNothing);
      expect(find.textContaining('CLIENT'), findsNothing);
    });

    testWidgets('shows lines the store removed, apart and out of the total', (
      tester,
    ) async {
      await _pump(
        tester,
        orders: [
          fakeCustomerOrder(
            status: OrderStatus.confirmed,
            items: [
              fakeOrderItem(id: 11, lineTotal: 900),
              fakeOrderItem(
                id: 12,
                name: 'Œufs',
                unit: SaleUnit.piece,
                quantity: 6,
                unitPrice: 400,
                lineTotal: 2400,
                removedAt: DateTime.utc(2026, 10, 4, 15),
              ),
            ],
          ),
        ],
      );
      await _openOrder(tester, 'K7M2QX');

      expect(find.text('Produits · 1'), findsOneWidget);
      expect(find.text('Retirés par le magasin · 1'), findsOneWidget);
      expect(find.text('Retiré de la commande'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Œufs')).style?.decoration,
        TextDecoration.lineThrough,
      );
      final totalRow = find.ancestor(
        of: find.text('Total'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: totalRow.first, matching: find.text('0,900 DT')),
        findsOneWidget,
      );
    });

    testWidgets('tracks a live order on the way to being collected', (
      tester,
    ) async {
      await _pump(
        tester,
        orders: [fakeCustomerOrder(status: OrderStatus.readyForPickup)],
      );
      await _openOrder(tester, 'K7M2QX');
      for (final step in ['Envoyée', 'Confirmée', 'Prête', 'Récupérée']) {
        expect(find.text(step), findsOneWidget, reason: step);
      }
      expect(find.text('Prête à retirer'), findsOneWidget);
      expect(
        find.text('Votre commande est prête. Présentez votre code au magasin.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a cancelled order shows no road to collection, and a calm no-show',
      (tester) async {
        await _pump(
          tester,
          orders: [
            fakeCustomerOrder(
              id: 1,
              code: 'CANC01',
              status: OrderStatus.cancelled,
            ),
            fakeCustomerOrder(
              id: 2,
              code: 'MISS02',
              status: OrderStatus.noShow,
            ),
          ],
        );
        await _openOrder(tester, 'CANC01');
        expect(find.text('Envoyée'), findsNothing);
        expect(find.text('Annulée'), findsOneWidget);
        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();
        await _openOrder(tester, 'MISS02');
        expect(find.text('Non retirée'), findsOneWidget);
        expect(find.text('La commande n’a pas été retirée.'), findsOneWidget);
      },
    );

    testWidgets('does not expose anything at 360 px wide with long names', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(360, 800),
        orders: [
          fakeCustomerOrder(
            storeName: 'Supermarché du grand marché central de la Marsa',
            items: [
              fakeOrderItem(
                id: 11,
                name: 'Fromage frais de chèvre fermier affiné aux herbes',
                lineTotal: 123456,
              ),
            ],
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      await _openOrder(tester, 'K7M2QX');
      expect(tester.takeException(), isNull);
      expect(_cancelButton, findsOneWidget);
    });
  });

  group('cancellation', () {
    testWidgets('is offered for a pending and a confirmed order only', (
      tester,
    ) async {
      await _pump(
        tester,
        orders: [
          for (final (i, status) in OrderStatus.values.indexed)
            fakeCustomerOrder(
              id: i + 1,
              code: 'S${status.index}XX',
              status: status,
            ),
        ],
      );
      for (final status in OrderStatus.values) {
        await _openOrder(tester, 'S${status.index}XX');
        final offered =
            status == OrderStatus.pending || status == OrderStatus.confirmed;
        expect(
          _cancelButton,
          offered ? findsOneWidget : findsNothing,
          reason: status.apiValue,
        );
        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('asks first, and backing out sends nothing', (tester) async {
      final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
      await _openOrder(tester, 'K7M2QX');
      await _tap(tester, _cancelButton);
      expect(find.text('Annuler la commande ?'), findsOneWidget);
      await tester.tap(find.text('Retour'));
      await tester.pumpAndSettle();
      expect(repo.cancelCalls, 0);
      expect(find.text('En attente'), findsOneWidget);
    });

    testWidgets('cancels the order and shows the server’s answer', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        orders: [fakeCustomerOrder(status: OrderStatus.confirmed)],
      );
      await _openOrder(tester, 'K7M2QX');
      await _tap(tester, _cancelButton);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Annuler la commande'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.cancelCalls, 1);
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.text('Commande annulée.'), findsOneWidget); // snackbar
      expect(_cancelButton, findsNothing);
    });

    testWidgets(
      'a race with the store: ORDER_STATE_CHANGED explains and shows the current state, no retry',
      (tester) async {
        final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
        await _openOrder(tester, 'K7M2QX');
        // The store marked it ready while the customer was deciding.
        repo.replace(fakeCustomerOrder(status: OrderStatus.readyForPickup));
        repo.cancelError = customerOrderStateChanged;

        await _tap(tester, _cancelButton);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Annuler la commande'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'La commande a changé d’état. Actualisez les informations.',
          ),
          findsOneWidget,
        );
        expect(repo.cancelCalls, 1); // not retried
        expect(find.text('Prête à retirer'), findsWidgets); // what is true now
        expect(_cancelButton, findsNothing);
      },
    );

    testWidgets('a network error is retryable and keeps the order', (
      tester,
    ) async {
      final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
      await _openOrder(tester, 'K7M2QX');
      repo.cancelError = const NetworkException('offline');
      await _tap(tester, _cancelButton);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Annuler la commande'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
      expect(find.text('En attente'), findsOneWidget);
      expect(_cancelButton, findsOneWidget);
    });

    testWidgets('404 closes the order with a message', (tester) async {
      final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
      await _openOrder(tester, 'K7M2QX');
      repo.cancelError = const ApiException(statusCode: 404);
      await _tap(tester, _cancelButton);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Annuler la commande'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Commande K7M2QX'), findsNothing);
      expect(
        find.text('Cette commande n’est plus disponible.'),
        findsOneWidget,
      );
    });
  });

  group('polling', () {
    testWidgets(
      'the list refreshes every 30 seconds while the tab is showing',
      (tester) async {
        final repo = await _pump(
          tester,
          orders: [fakeCustomerOrder(id: 1, code: 'FIRST1')],
        );
        repo.add(fakeCustomerOrder(id: 2, code: 'SECND2'));
        expect(find.text('SECND2'), findsNothing);

        await tester.pump(ordersPollInterval);
        await tester.pumpAndSettle();
        expect(find.text('SECND2'), findsOneWidget);
      },
    );

    testWidgets('uses the same interval as the owner’s orders', (tester) async {
      expect(ordersPollInterval, const Duration(seconds: 30));
    });

    testWidgets(
      'does not poll while another tab is showing, and refreshes on return',
      (tester) async {
        final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
        await _tab(tester, 'Panier');
        repo.listCalls.clear();
        await tester.pump(ordersPollInterval * 3);
        expect(repo.listCalls, isEmpty);

        await _tab(tester, 'Commandes');
        expect(repo.listCalls, isNotEmpty);
        repo.listCalls.clear();
        await tester.pump(ordersPollInterval);
        await tester.pumpAndSettle();
        expect(repo.listCalls, isNotEmpty);
      },
    );

    testWidgets('pauses in the background, refreshes on return', (
      tester,
    ) async {
      final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
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
    });

    testWidgets('an open order follows its status by polling', (tester) async {
      final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
      await _openOrder(tester, 'K7M2QX');
      expect(find.text('En attente'), findsOneWidget);

      repo.replace(fakeCustomerOrder(status: OrderStatus.readyForPickup));
      await tester.pump(ordersPollInterval);
      await tester.pumpAndSettle();

      expect(find.text('Prête à retirer'), findsWidgets);
      expect(_cancelButton, findsNothing);
    });

    testWidgets('a finished order is not polled any more', (tester) async {
      final repo = await _pump(
        tester,
        orders: [fakeCustomerOrder(status: OrderStatus.completed)],
      );
      await _openOrder(tester, 'K7M2QX');
      repo.getCalls = 0;
      await tester.pump(ordersPollInterval * 3);
      expect(repo.getCalls, 0);
    });

    testWidgets(
      'does not poll the list under an open order, and refreshes after',
      (tester) async {
        final repo = await _pump(
          tester,
          orders: [fakeCustomerOrder(status: OrderStatus.completed)],
        );
        await _openOrder(tester, 'K7M2QX');
        repo.listCalls.clear();
        await tester.pump(ordersPollInterval * 2);
        expect(repo.listCalls, isEmpty);

        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();
        expect(repo.listCalls, isNotEmpty);
      },
    );

    testWidgets('timers are gone once the app is torn down', (tester) async {
      final repo = await _pump(tester, orders: [fakeCustomerOrder()]);
      await tester.pumpWidget(const SizedBox());
      repo.listCalls.clear();
      await tester.pump(ordersPollInterval * 3);
      expect(repo.listCalls, isEmpty);
    });
  });
}
