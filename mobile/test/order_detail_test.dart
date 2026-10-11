import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/utils/date_formatters.dart';

import 'fakes.dart';

Future<FakeOrdersRepository> _openDetail(
  WidgetTester tester,
  Order order, {
  List<Order> others = const [],
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = FakeOrdersRepository(ApiClient(), orders: [order, ...others]);
  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
    ordersRepository: (_) => repo,
  );
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Commandes'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(order.code));
  await tester.pumpAndSettle();
  return repo;
}

/// The pinned action button with [label] (any Material button kind).
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

/// The action buttons only (the app bar's back button is a Material button too).
Finder get _anyButton => find.byWidgetPredicate(
  (widget) =>
      widget is ElevatedButton ||
      widget is OutlinedButton ||
      widget is TextButton,
);
Finder _dialogButton(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _sanaNetwork =
    'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.';

void main() {
  group('content', () {
    testWidgets(
      'shows the order, its customer, pickup, total, payment and status',
      (tester) async {
        final pickup = DateTime.now().toUtc().add(const Duration(hours: 5));
        final created = DateTime.utc(2026, 10, 4, 14, 48, 2, 454);
        await _openDetail(
          tester,
          fakeOrder(
            code: 'AB12CD',
            status: OrderStatus.confirmed,
            customerName: 'Sana Ben Ali',
            customerPhone: '+21698765432',
            requestedPickupAt: pickup,
            createdAt: created,
          ),
        );

        expect(find.text('Commande AB12CD'), findsOneWidget); // title
        expect(find.text('AB12CD'), findsOneWidget);
        expect(find.text('Confirmée'), findsOneWidget);
        expect(find.text('Sana Ben Ali'), findsOneWidget);
        expect(find.text('+21698765432'), findsOneWidget);
        expect(find.text(DateFormatFr.pickup(pickup)), findsOneWidget);
        expect(find.text('Retrait souhaité'), findsOneWidget);
        expect(find.text(DateFormatFr.dateTime(created)), findsWidgets);
        // The server's total (900 + 2100 millimes), and payment at pickup.
        expect(find.text('Total'), findsOneWidget);
        expect(find.text('3,000 DT'), findsWidgets);
        expect(find.text('Paiement'), findsOneWidget);
        expect(find.text('À la récupération'), findsOneWidget);
      },
    );

    testWidgets(
      'lists every kept line with name, quantity, unit, price and total',
      (tester) async {
        await _openDetail(tester, fakeOrder(status: OrderStatus.confirmed));

        expect(find.text('Lignes conservées · 2'), findsOneWidget);
        expect(find.text('Tomate'), findsOneWidget);
        expect(find.text('500 g · 1,800 DT / kg'), findsOneWidget);
        expect(find.text('0,900 DT'), findsOneWidget);
        expect(find.text('Œufs'), findsOneWidget);
        expect(find.text('6 pièces · 0,350 DT / pièce'), findsOneWidget);
        expect(find.text('2,100 DT'), findsOneWidget);
        expect(find.text('Lignes retirées', skipOffstage: false), findsNothing);
        // No stock or internal ids anywhere.
        expect(find.textContaining('tock'), findsNothing);
      },
    );

    testWidgets('shows removed lines apart, marked, and out of the total', (
      tester,
    ) async {
      final removedAt = DateTime.utc(2026, 10, 4, 14, 50);
      await _openDetail(
        tester,
        fakeOrder(
          status: OrderStatus.confirmed,
          items: [
            fakeOrderItem(id: 11),
            fakeOrderItem(
              id: 12,
              name: 'Œufs',
              unit: SaleUnit.piece,
              quantity: 6,
              unitPrice: 350,
              lineTotal: 2100,
              removedAt: removedAt,
            ),
          ],
          totalMillimes: 900,
        ),
      );

      expect(find.text('Lignes conservées · 1'), findsOneWidget);
      expect(find.text('Lignes retirées · 1'), findsOneWidget);
      expect(find.text('Retirée'), findsOneWidget);
      // The removed line keeps its history…
      expect(find.text('6 pièces · 0,350 DT / pièce'), findsOneWidget);
      expect(find.text('2,100 DT'), findsOneWidget);
      // …but only the server's total (kept lines) is the total.
      final totalRow = find.ancestor(
        of: find.text('Total'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: totalRow.first, matching: find.text('0,900 DT')),
        findsOneWidget,
      );
      expect(find.text('3,000 DT'), findsNothing);
      // The removed line is struck through (not only colored).
      final name = tester.widget<Text>(find.text('Œufs'));
      expect(name.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('shows the history in French, with who and why', (
      tester,
    ) async {
      final t0 = DateTime.utc(2026, 10, 4, 14, 48);
      final t1 = DateTime.utc(2026, 10, 4, 15, 2);
      await _openDetail(
        tester,
        fakeOrder(
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
      );

      await tester.ensureVisible(find.text('Historique'));
      expect(find.text('Historique'), findsOneWidget);
      expect(find.text('Commande reçue'), findsOneWidget);
      expect(find.text('Commande annulée par le magasin'), findsOneWidget);
      expect(find.text('Motif : Produit épuisé'), findsOneWidget);
      expect(find.text(DateFormatFr.dateTime(t0)), findsWidgets);
      expect(find.text(DateFormatFr.dateTime(t1)), findsOneWidget);
    });

    testWidgets('names every status in the history', (tester) async {
      DateTime at(int minute) => DateTime.utc(2026, 10, 4, 14, minute);
      await _openDetail(
        tester,
        fakeOrder(
          status: OrderStatus.noShow,
          events: [
            OrderEvent(
              toStatus: OrderStatus.pending,
              actorType: OrderActorType.client,
              createdAt: at(1),
            ),
            OrderEvent(
              fromStatus: OrderStatus.pending,
              toStatus: OrderStatus.confirmed,
              actorType: OrderActorType.owner,
              createdAt: at(2),
            ),
            OrderEvent(
              fromStatus: OrderStatus.confirmed,
              toStatus: OrderStatus.readyForPickup,
              actorType: OrderActorType.owner,
              createdAt: at(3),
            ),
            OrderEvent(
              fromStatus: OrderStatus.readyForPickup,
              toStatus: OrderStatus.noShow,
              actorType: OrderActorType.owner,
              createdAt: at(4),
            ),
          ],
        ),
      );
      await tester.ensureVisible(find.text('Historique'));
      for (final label in [
        'Commande reçue',
        'Commande confirmée',
        'Prête à retirer',
        'Commande non récupérée',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });
  });

  group('small phones', () {
    testWidgets('list and detail fit a 360 px screen with long names', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final order = fakeOrder(
        status: OrderStatus.readyForPickup,
        customerName: 'Mohamed Amine Ben Abdallah El Mekki Trabelsi',
        items: [
          fakeOrderItem(
            id: 11,
            name: 'Fromage frais de chèvre fermier affiné aux herbes',
            lineTotal: 123456,
          ),
          fakeOrderItem(id: 12, name: 'Tomate', removedAt: DateTime.utc(2026)),
        ],
      );
      final repo = FakeOrdersRepository(ApiClient(), orders: [order]);
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
        ordersRepository: (_) => repo,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Commandes'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('K7M2QX'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_button('Marquer comme non récupérée'), findsOneWidget);
    });
  });

  group('actions by status', () {
    Future<void> expectActions(
      WidgetTester tester,
      OrderStatus status,
      List<String> shown,
    ) async {
      await _openDetail(tester, fakeOrder(status: status));
      const all = [
        'Confirmer',
        'Annuler',
        'Prête',
        'Marquer comme récupérée',
        'Marquer comme non récupérée',
      ];
      for (final label in all) {
        expect(
          _button(label),
          shown.contains(label) ? findsOneWidget : findsNothing,
          reason: '$status / $label',
        );
      }
    }

    testWidgets('PENDING: Confirmer, Annuler', (tester) async {
      await expectActions(tester, OrderStatus.pending, [
        'Confirmer',
        'Annuler',
      ]);
    });

    testWidgets('CONFIRMED: Prête, Annuler', (tester) async {
      await expectActions(tester, OrderStatus.confirmed, ['Prête', 'Annuler']);
    });

    testWidgets('READY_FOR_PICKUP: récupérée, non récupérée', (tester) async {
      await expectActions(tester, OrderStatus.readyForPickup, [
        'Marquer comme récupérée',
        'Marquer comme non récupérée',
      ]);
    });

    for (final status in [
      OrderStatus.completed,
      OrderStatus.cancelled,
      OrderStatus.noShow,
    ]) {
      testWidgets('$status: no action at all', (tester) async {
        await _openDetail(tester, fakeOrder(status: status));
        expect(_anyButton, findsNothing);
        expect(find.byType(TextButton), findsNothing);
      });
    }
  });

  group('transitions', () {
    testWidgets('Confirmer confirms with no removals, without a dialog', (
      tester,
    ) async {
      final repo = await _openDetail(tester, fakeOrder());
      await _tap(tester, _button('Confirmer'));

      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.transitions, ['confirm:1']);
      expect(repo.lastRemoved, isEmpty);
      expect(find.text('Confirmée'), findsOneWidget);
      expect(find.text('Commande confirmée.'), findsOneWidget);
      // The buttons follow the new status.
      expect(_button('Prête'), findsOneWidget);
      expect(_button('Confirmer'), findsNothing);
    });

    testWidgets('Prête moves a confirmed order to ready for pickup', (
      tester,
    ) async {
      final repo = await _openDetail(
        tester,
        fakeOrder(status: OrderStatus.confirmed),
      );
      await _tap(tester, _button('Prête'));
      expect(repo.transitions, ['ready:1']);
      expect(find.text('Prête à retirer'), findsWidgets);
      expect(_button('Marquer comme récupérée'), findsOneWidget);
    });

    testWidgets(
      'Marquer comme récupérée completes the order and clears the actions',
      (tester) async {
        final repo = await _openDetail(
          tester,
          fakeOrder(status: OrderStatus.readyForPickup),
        );
        await _tap(tester, _button('Marquer comme récupérée'));
        expect(repo.transitions, ['complete:1']);
        expect(find.text('Terminée'), findsOneWidget);
        expect(_anyButton, findsNothing);
      },
    );

    testWidgets('no-show asks first, and can be backed out of', (tester) async {
      final repo = await _openDetail(
        tester,
        fakeOrder(status: OrderStatus.readyForPickup),
      );
      await _tap(tester, _button('Marquer comme non récupérée'));
      expect(find.text('Marquer comme non récupérée ?'), findsOneWidget);

      await _tap(tester, _dialogButton('Retour'));
      expect(repo.transitions, isEmpty);

      await _tap(tester, _button('Marquer comme non récupérée'));
      await _tap(tester, _dialogButton('Confirmer'));
      expect(repo.transitions, ['no-show:1']);
      expect(find.text('Non récupérée'), findsOneWidget);
    });
  });

  group('cancellation', () {
    testWidgets('needs a reason, which is trimmed and sent', (tester) async {
      final repo = await _openDetail(tester, fakeOrder());
      await _tap(tester, _button('Annuler'));

      expect(find.text('Annuler la commande ?'), findsOneWidget);
      expect(find.text('Le client verra ce motif.'), findsOneWidget);
      // No reason yet: the action is disabled.
      final confirm = find.widgetWithText(TextButton, 'Annuler la commande');
      expect(tester.widget<TextButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<TextButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  Produit épuisé  ');
      await tester.pump();
      expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(repo.transitions, ['cancel:1']);
      expect(repo.lastReason, 'Produit épuisé');
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.text('Motif : Produit épuisé'), findsOneWidget);
      expect(_anyButton, findsNothing);
    });

    testWidgets('backing out sends nothing', (tester) async {
      final repo = await _openDetail(
        tester,
        fakeOrder(status: OrderStatus.confirmed),
      );
      await _tap(tester, _button('Annuler'));
      await tester.enterText(find.byType(TextField), 'Raison');
      await _tap(tester, _dialogButton('Retour'));
      expect(repo.transitions, isEmpty);
      expect(find.text('Confirmée'), findsOneWidget);
    });
  });

  group('confirming with removed lines', () {
    testWidgets('a line can be staged for removal and put back', (
      tester,
    ) async {
      await _openDetail(tester, fakeOrder());
      expect(find.text('Lignes conservées · 2'), findsOneWidget);

      await _tap(tester, find.widgetWithText(TextButton, 'Retirer').first);
      expect(find.text('Lignes conservées · 1'), findsOneWidget);
      expect(find.text('Lignes retirées · 1'), findsOneWidget);
      expect(find.text('Sera retirée'), findsOneWidget);
      expect(
        find.text('Le total sera recalculé à la confirmation.'),
        findsOneWidget,
      );
      // Nothing is recomputed here: the total is still the server's.
      expect(find.text('3,000 DT'), findsWidgets);

      await _tap(tester, find.widgetWithText(TextButton, 'Rétablir'));
      expect(find.text('Lignes conservées · 2'), findsOneWidget);
      expect(find.text('Lignes retirées', skipOffstage: false), findsNothing);
    });

    testWidgets(
      'lists what will be removed before sending, then sends only ids',
      (tester) async {
        final repo = await _openDetail(tester, fakeOrder());
        await _tap(tester, find.widgetWithText(TextButton, 'Retirer').last);
        await _tap(tester, _button('Confirmer'));

        expect(find.text('Retirer ces produits ?'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('Œufs'),
          ),
          findsOneWidget,
        );
        expect(repo.transitions, isEmpty);

        await _tap(tester, _dialogButton('Retirer et confirmer'));

        expect(repo.transitions, ['confirm:1']);
        expect(repo.lastRemoved, [12]);
        // The backend's order comes back: the line is removed, total recomputed
        // by the server.
        expect(find.text('Lignes retirées · 1'), findsOneWidget);
        expect(find.text('Retirée'), findsOneWidget);
        expect(find.text('Confirmée'), findsOneWidget);
        final totalRow = find.ancestor(
          of: find.text('Total'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: totalRow.first, matching: find.text('0,900 DT')),
          findsOneWidget,
        );
      },
    );

    testWidgets('backing out of the removal dialog sends nothing', (
      tester,
    ) async {
      final repo = await _openDetail(tester, fakeOrder());
      await _tap(tester, find.widgetWithText(TextButton, 'Retirer').first);
      await _tap(tester, _button('Confirmer'));
      await _tap(tester, _dialogButton('Retour'));
      expect(repo.transitions, isEmpty);
      expect(find.text('Lignes retirées · 1'), findsOneWidget);
    });

    testWidgets('removing every line is refused locally: cancel instead', (
      tester,
    ) async {
      final repo = await _openDetail(tester, fakeOrder());
      await _tap(tester, find.widgetWithText(TextButton, 'Retirer').first);
      await _tap(tester, find.widgetWithText(TextButton, 'Retirer').first);

      expect(
        find.text(
          'Toutes les lignes seraient retirées. Annulez plutôt la commande.',
        ),
        findsOneWidget,
      );
      expect(find.text('Lignes conservées · 0'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(_button('Confirmer')).onPressed,
        isNull,
      );
      // Cancelling stays possible.
      expect(
        tester.widget<OutlinedButton>(_button('Annuler')).onPressed,
        isNotNull,
      );
      await tester.tap(_button('Confirmer'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.transitions, isEmpty);

      // Putting one back lifts the block.
      await _tap(tester, find.widgetWithText(TextButton, 'Rétablir').first);
      expect(
        tester.widget<ElevatedButton>(_button('Confirmer')).onPressed,
        isNotNull,
      );
    });

    testWidgets('only a pending order offers removal', (tester) async {
      await _openDetail(tester, fakeOrder(status: OrderStatus.confirmed));
      expect(find.widgetWithText(TextButton, 'Retirer'), findsNothing);
    });
  });

  group('errors', () {
    testWidgets(
      'ORDER_STATE_CHANGED explains, refreshes the order, never retries',
      (tester) async {
        final repo = await _openDetail(tester, fakeOrder());
        // The customer cancelled while the owner was looking.
        repo.replace(fakeOrder(status: OrderStatus.cancelled));
        repo.transitionError = orderStateChanged;
        await _tap(tester, _button('Confirmer'));

        expect(
          find.text(
            'La commande a changé d’état. Actualisez les informations.',
          ),
          findsOneWidget,
        );
        expect(repo.transitions, ['confirm:1']); // not retried
        // What is true now is on screen.
        expect(find.text('Annulée'), findsOneWidget);
        expect(_anyButton, findsNothing);
      },
    );

    testWidgets('STOCK_CHANGED asks the owner to review again', (tester) async {
      final repo = await _openDetail(tester, fakeOrder());
      repo.transitionError = const ApiException(
        statusCode: 409,
        code: 'STOCK_CHANGED',
      );
      await _tap(tester, _button('Confirmer'));
      expect(
        find.text(
          'Le stock a changé. Vérifiez à nouveau la commande avant de continuer.',
        ),
        findsOneWidget,
      );
      expect(repo.transitions, ['confirm:1']);
      expect(
        _button('Confirmer'),
        findsOneWidget,
      ); // still pending, review again
    });

    testWidgets('a network error is retryable', (tester) async {
      final repo = await _openDetail(tester, fakeOrder());
      repo.transitionError = const NetworkException('offline');
      await _tap(tester, _button('Confirmer'));
      expect(find.text(_sanaNetwork), findsOneWidget);
      expect(find.text('En attente'), findsWidgets);

      repo.transitionError = null;
      await tester.pump(const Duration(seconds: 5));
      await _tap(tester, _button('Confirmer'));
      expect(find.text('Confirmée'), findsOneWidget);
    });

    testWidgets(
      'a validation error shows a French fallback, never the English text',
      (tester) async {
        final repo = await _openDetail(tester, fakeOrder());
        repo.transitionError = const ApiException(
          statusCode: 400,
          message: 'Items are not part of this order',
        );
        await _tap(tester, _button('Confirmer'));
        expect(
          find.text(
            'Cette demande n’est pas valide. Vérifiez la commande et réessayez.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Items are not'), findsNothing);
      },
    );

    testWidgets('an unknown server error is generic, with no raw text', (
      tester,
    ) async {
      final repo = await _openDetail(tester, fakeOrder());
      repo.transitionError = const ApiException(
        statusCode: 500,
        message: 'Internal server error: boom',
      );
      await _tap(tester, _button('Confirmer'));
      expect(
        find.text('Une erreur est survenue. Veuillez réessayer.'),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('404 closes the order and tells the list it is gone', (
      tester,
    ) async {
      final repo = await _openDetail(tester, fakeOrder());
      repo.transitionError = const ApiException(statusCode: 404);
      await _tap(tester, _button('Confirmer'));

      expect(find.text('Commande K7M2QX'), findsNothing); // back on the list
      expect(
        find.text('Cette commande n’est plus disponible.'),
        findsOneWidget,
      );
      expect(find.text('Commandes'), findsWidgets);
    });

    testWidgets(
      'a rejected token signs the owner out through the existing flow',
      (tester) async {
        final repo = await _openDetail(tester, fakeOrder());
        repo.transitionError = const ApiException(statusCode: 401);
        await _tap(tester, _button('Confirmer'));
        expect(find.text('Connexion'), findsWidgets);
        expect(find.text('Commande K7M2QX'), findsNothing);
      },
    );

    testWidgets('a failed first refresh keeps the list’s copy on screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeOrdersRepository(ApiClient(), orders: [fakeOrder()]);
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: (api) => FakeStoreRepository(api, store: closedStore),
        ordersRepository: (_) => repo,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Commandes'),
        ),
      );
      await tester.pumpAndSettle();
      repo.getError = const NetworkException('offline');
      await tester.tap(find.text('K7M2QX'));
      await tester.pumpAndSettle();

      expect(find.text('Commande K7M2QX'), findsOneWidget);
      expect(find.text('Sana Ben Ali'), findsOneWidget);
      expect(find.text(_sanaNetwork), findsOneWidget);
    });
  });

  group('freshness', () {
    testWidgets(
      'opening an order reloads it and the list refreshes on return',
      (tester) async {
        final repo = await _openDetail(tester, fakeOrder());
        expect(repo.getCalls, 1);

        await _tap(tester, _button('Confirmer'));
        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();

        // Back on the list, which now shows the new status and count.
        expect(find.text('Aucune commande en attente'), findsOneWidget);
        expect(find.text('Confirmée'), findsWidgets);
      },
    );
  });
}
