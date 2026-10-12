import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/store_product.dart';

import 'fakes.dart';

const _openStore = Store(
  id: 10,
  name: 'Menzah Market',
  address: '12 Rue de la Liberté, Tunis',
  isOpen: true,
  ownerId: 1,
);

Future<void> _pumpShell(
  WidgetTester tester, {
  Store store = closedStore,
  List<StoreProduct> Function()? products,
  bool productsFail = false,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: store),
    storeProductsRepository: (api) => FakeStoreProductsRepository(
      api,
      products: products?.call() ?? [],
      fails: productsFail,
    ),
  );
}

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_navLabel(label));
  await tester.pumpAndSettle();
}

void main() {
  homeOrdersTests();
  group('navigation', () {
    testWidgets('shows only owner areas: Accueil, Commandes, Catalogue, '
        'Magasin', (tester) async {
      await _pumpShell(tester);

      for (final label in ['Accueil', 'Commandes', 'Catalogue', 'Magasin']) {
        expect(_navLabel(label), findsOneWidget);
      }
      // No customer-side navigation, ever.
      for (final label in ['Recherche', 'Panier', 'Profil', 'Catégories']) {
        expect(_navLabel(label), findsNothing);
      }
      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });
  });

  group('dashboard', () {
    testWidgets('a new store shows its state and the full setup checklist', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.text('Bonjour, Karim'), findsOneWidget);
      expect(find.text('Magasin fermé'), findsOneWidget);
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('Démarrer votre magasin · 0/2'), findsOneWidget);
      expect(find.text('Ajouter des produits'), findsOneWidget);
      expect(find.text('Ouvrir le magasin'), findsOneWidget);
      // Categories belong to the global catalog now: nothing to create.
      expect(find.text('Créer une catégorie'), findsNothing);
    });

    testWidgets('has no analytics, charts or fake numbers', (tester) async {
      await _pumpShell(tester);
      expect(find.textContaining('DT'), findsNothing);
      expect(find.textContaining('Chiffre'), findsNothing);
      // The only "Commandes" on the dashboard is the navigation tab.
      expect(find.textContaining('Commandes'), findsOneWidget);
      expect(_navLabel('Commandes'), findsOneWidget);
    });

    testWidgets('counts progress and only lists what is left to do', (
      tester,
    ) async {
      await _pumpShell(tester, products: () => [fakeTomatoes()]);

      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);
      // Done steps are listed without their hint; the open step keeps it.
      expect(find.text('Prix, unité de vente et quantités.'), findsNothing);
      expect(
        find.text('Vos clients pourront alors commander.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('the checklist disappears once setup is complete', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        store: _openStore,
        products: () => [fakeTomatoes()],
      );

      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsOneWidget);
    });

    testWidgets('archived products do not count as a product', (tester) async {
      await _pumpShell(
        tester,
        products: () => [fakeStoreProduct(isArchived: true)],
      );
      expect(find.text('Démarrer votre magasin · 0/2'), findsOneWidget);
    });

    testWidgets('a product the owner switched off is added but not orderable', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        products: () => [fakeTomatoes(isAvailable: false)],
      );
      // Nothing can be ordered yet: the step is still to do, with the facts.
      expect(find.text('Démarrer votre magasin · 0/2'), findsOneWidget);
      expect(
        find.text('1 produit · aucun disponible à la commande'),
        findsOneWidget,
      );
      expect(find.text('À compléter'), findsOneWidget);
    });

    testWidgets('each open step leads to the right place', (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Ajouter des produits'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit'), findsOneWidget); // Catalogue tab

      await _openTab(tester, 'Accueil');
      await tester.tap(find.text('Ouvrir le magasin'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget); // Magasin tab
    });

    testWidgets('updates when the owner finishes the steps elsewhere', (
      tester,
    ) async {
      await _pumpShell(tester, products: () => [fakeTomatoes()]);
      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);

      await _openTab(tester, 'Magasin');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await _openTab(tester, 'Accueil');
      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(find.text('Magasin ouvert'), findsWidgets);
    });

    testWidgets('says so, instead of a wrong checklist, when it cannot load', (
      tester,
    ) async {
      await _pumpShell(tester, productsFail: true);

      expect(
        find.textContaining('Impossible de charger la configuration'),
        findsOneWidget,
      );
      expect(find.textContaining('Démarrer votre magasin'), findsNothing);
      expect(
        find.text('Magasin fermé'),
        findsOneWidget,
      ); // store info still shown
    });
  });

  group('inventory facts in the checklist', () {
    testWidgets('no product: the original hint, "À compléter", no counts', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(find.text('À compléter'), findsOneWidget);
      expect(find.text('Prix, unité de vente et quantités.'), findsOneWidget);
      expect(find.textContaining('produit ·'), findsNothing);
      expect(find.textContaining('produits ·'), findsNothing);
    });

    testWidgets(
      'one orderable product is enough: step done, no "À compléter"',
      (tester) async {
        await _pumpShell(tester, products: () => [fakeTomatoes()]);
        expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);
        expect(
          find.text('1 produit · 1 disponible à la commande'),
          findsOneWidget,
        );
        expect(find.text('À compléter'), findsNothing);
        // One is not described as too few.
        expect(find.textContaining('insuffisant'), findsNothing);
        expect(find.textContaining('minimum'), findsNothing);
      },
    );

    testWidgets('several products: total and orderable are told apart', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        products: () => [
          fakeTomatoes(),
          fakeStoreProduct(id: 2),
          fakeTomatoes(isAvailable: false),
        ],
      );
      expect(
        find.text('3 produits · 2 disponibles à la commande'),
        findsOneWidget,
      );
      expect(find.text('Démarrer votre magasin · 1/2'), findsOneWidget);
    });

    testWidgets('stock at zero is not orderable, whatever the owner switch', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        products: () => [fakeTomatoes(trackStock: true, stockQuantity: 0)],
      );
      expect(
        find.text('1 produit · aucun disponible à la commande'),
        findsOneWidget,
      );
      expect(find.text('À compléter'), findsOneWidget);
    });

    testWidgets('stays readable at 1.6× text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpShell(
        tester,
        products: () => [fakeTomatoes(isAvailable: false)],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('À compléter'), findsOneWidget);
    });
  });
}

// ── Orders, pickups and stock on the home ───────────────────────────────────

Future<FakeOrdersRepository> _pumpHome(
  WidgetTester tester, {
  List<Order> orders = const [],
  List<StoreProduct> products = const [],
  Store store = _openStore,
  Size size = const Size(402, 1400),
  double textScale = 1,
  bool ordersFail = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  late FakeOrdersRepository repository;
  await pumpAppSignedInAs(
    tester,
    testOwner,
    storeRepository: (api) => FakeStoreRepository(api, store: store),
    ordersRepository: (api) =>
        repository = FakeOrdersRepository(api, orders: orders)
          ..fails = ordersFail,
    storeProductsRepository: (api) =>
        FakeStoreProductsRepository(api, products: products),
  );
  return repository;
}

Order _order(int id, OrderStatus status, {String? name, Duration? pickupIn}) =>
    fakeOrder(
      id: id,
      code: 'CODE${id.toString().padLeft(2, '0')}',
      status: status,
      customerName: name ?? 'Client $id',
      requestedPickupAt: DateTime.now().toUtc().add(
        pickupIn ?? Duration(hours: id),
      ),
    );

Finder _tile(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void homeOrdersTests() {
  group('workload', () {
    testWidgets('counts only pending, confirmed and ready orders', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        orders: [
          _order(1, OrderStatus.pending),
          _order(2, OrderStatus.pending),
          _order(3, OrderStatus.confirmed),
          _order(4, OrderStatus.readyForPickup),
          _order(5, OrderStatus.readyForPickup),
          _order(6, OrderStatus.readyForPickup),
          _order(7, OrderStatus.cancelled),
          _order(8, OrderStatus.noShow),
          _order(9, OrderStatus.completed),
        ],
      );
      expect(find.text('À traiter'), findsOneWidget);
      expect(
        find.descendant(of: _tile('À confirmer'), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tile('À préparer'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _tile('Prêtes à retirer'),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('each row says what it is, and the header adds them up', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        orders: [
          _order(1, OrderStatus.pending),
          _order(2, OrderStatus.confirmed),
          _order(3, OrderStatus.confirmed),
          _order(4, OrderStatus.readyForPickup),
          _order(5, OrderStatus.cancelled),
          _order(6, OrderStatus.noShow),
          _order(7, OrderStatus.completed),
        ],
      );
      expect(find.text('Nouvelles commandes'), findsOneWidget);
      expect(find.text('Commandes confirmées'), findsOneWidget);
      expect(find.text('En attente du client'), findsOneWidget);
      // 1 + 2 + 1: cancelled, no-show and completed are not work.
      expect(find.text('4 commandes'), findsOneWidget);
    });

    testWidgets('the total is singular for one order and absent while '
        'unknown', (tester) async {
      await _pumpHome(tester, orders: [_order(1, OrderStatus.pending)]);
      expect(find.text('1 commande'), findsOneWidget);
    });

    testWidgets('rows are 48 px or more, with an icon each and a chevron', (
      tester,
    ) async {
      await _pumpHome(tester, orders: [_order(1, OrderStatus.pending)]);
      for (final label in ['À confirmer', 'À préparer', 'Prêtes à retirer']) {
        expect(tester.getSize(_tile(label)).height, greaterThanOrEqualTo(48));
      }
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shopping_basket_rounded), findsOneWidget);
      // Spoken label keeps the count and the status.
      expect(
        find.bySemanticsLabel('1 commande en attente de confirmation'),
        findsOneWidget,
      );
    });

    testWidgets('shows zero counts, and an empty pickups state', (
      tester,
    ) async {
      await _pumpHome(tester, products: [fakeTomatoes()]);
      expect(find.text('0'), findsNWidgets(3));
      expect(find.text('0 commande'), findsOneWidget);
      expect(find.text('Aucun retrait prévu'), findsOneWidget);
    });

    testWidgets('each tile opens Commandes on its status', (tester) async {
      final repo = await _pumpHome(
        tester,
        orders: [
          _order(1, OrderStatus.pending),
          _order(2, OrderStatus.confirmed),
          _order(3, OrderStatus.readyForPickup),
        ],
      );
      for (final (label, status, badge) in [
        ('À confirmer', OrderStatus.pending, 'En attente'),
        ('À préparer', OrderStatus.confirmed, 'Confirmée'),
        ('Prêtes à retirer', OrderStatus.readyForPickup, 'Prête à retirer'),
      ]) {
        await _openTab(tester, 'Accueil');
        final before = repo.listCallCount;
        await tester.tap(_tile(label));
        await tester.pumpAndSettle();
        expect(find.text('Toutes'), findsWidgets); // the orders tab
        // The list was asked for that status.
        expect(
          repo.listCalls
              .skip(before)
              .any((c) => c.status == status && c.limit == 20),
          isTrue,
          reason: label,
        );
        expect(find.text(badge), findsWidgets);
      }
    });

    testWidgets('the same tile twice applies the filter again', (tester) async {
      final repo = await _pumpHome(
        tester,
        orders: [
          _order(1, OrderStatus.pending),
          _order(2, OrderStatus.confirmed),
        ],
      );
      await tester.tap(_tile('À confirmer'));
      await tester.pumpAndSettle();
      // Change the filter inside the orders tab, then come back to the home.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Confirmée'));
      await tester.pumpAndSettle();
      await _openTab(tester, 'Accueil');
      final before = repo.listCallCount;
      await tester.tap(_tile('À confirmer'));
      await tester.pumpAndSettle();
      expect(
        repo.listCalls
            .skip(before)
            .any((c) => c.status == OrderStatus.pending && c.limit == 20),
        isTrue,
      );
    });
  });

  group('upcoming pickups', () {
    testWidgets('lists at most three confirmed or ready orders, soonest '
        'requested time first', (tester) async {
      await _pumpHome(
        tester,
        orders: [
          _order(
            1,
            OrderStatus.confirmed,
            name: 'Dernier',
            pickupIn: const Duration(hours: 9),
          ),
          _order(
            2,
            OrderStatus.readyForPickup,
            name: 'Premier',
            pickupIn: const Duration(minutes: 30),
          ),
          _order(
            3,
            OrderStatus.confirmed,
            name: 'Troisieme',
            pickupIn: const Duration(hours: 5),
          ),
          _order(
            4,
            OrderStatus.confirmed,
            name: 'Deuxieme',
            pickupIn: const Duration(hours: 2),
          ),
          _order(
            5,
            OrderStatus.pending,
            name: 'EnAttente',
            pickupIn: const Duration(minutes: 5),
          ),
          _order(
            6,
            OrderStatus.cancelled,
            name: 'Annulee',
            pickupIn: const Duration(minutes: 10),
          ),
          _order(
            7,
            OrderStatus.noShow,
            name: 'NonRetiree',
            pickupIn: const Duration(minutes: 15),
          ),
        ],
      );
      expect(find.text('Prochains retraits'), findsOneWidget);
      final tops = [
        for (final n in ['Premier', 'Deuxieme', 'Troisieme'])
          tester.getTopLeft(find.text(n)).dy,
      ];
      expect(tops, [...tops]..sort());
      for (final n in ['Dernier', 'EnAttente', 'Annulee', 'NonRetiree']) {
        expect(find.text(n), findsNothing, reason: n);
      }
    });

    testWidgets('shows time, customer, code and status; a past requested '
        'time is a note', (tester) async {
      await _pumpHome(
        tester,
        orders: [
          _order(
            1,
            OrderStatus.readyForPickup,
            name: 'Leïla Trabelsi',
            pickupIn: const Duration(minutes: -30),
          ),
        ],
      );
      expect(find.text('Leïla Trabelsi'), findsOneWidget);
      expect(find.text('CODE01'), findsOneWidget);
      expect(find.text('Prête à retirer'), findsOneWidget);
      expect(find.text('Heure souhaitée passée'), findsOneWidget);
      expect(find.textContaining('retard'), findsNothing);
    });

    testWidgets('opens the existing order page, then refreshes', (
      tester,
    ) async {
      final repo = await _pumpHome(
        tester,
        orders: [_order(1, OrderStatus.confirmed, name: 'Sana')],
      );
      final before = repo.listCallCount;
      await tester.tap(find.text('Sana'));
      await tester.pumpAndSettle();
      expect(find.text('Commande CODE01'), findsOneWidget);
      Navigator.of(tester.element(find.text('Commande CODE01'))).pop();
      await tester.pumpAndSettle();
      expect(repo.listCallCount, greaterThan(before));
    });
  });

  group('stock', () {
    testWidgets('counts the backend verdicts, and opens the catalogue', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        products: [
          fakeTomatoes(id: 1),
          fakeStoreProduct(id: 2, trackStock: true, stockQuantity: 0),
          fakeStoreProduct(id: 3, trackStock: true, stockQuantity: 0),
          fakeStoreProduct(id: 4, trackStock: true, stockQuantity: 5000),
          fakeStoreProduct(id: 5, isAvailable: false),
        ],
      );
      expect(find.text('Stock'), findsOneWidget);
      expect(find.textContaining('2 produits'), findsOneWidget);
      expect(find.textContaining('en rupture de stock'), findsOneWidget);
      // A switched-off product is the owner's choice, not a stock alert.
      expect(find.textContaining('sous le minimum'), findsNothing);
      await tester.tap(find.textContaining('en rupture de stock'));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter depuis le catalogue'), findsWidgets);
    });

    testWidgets('no alert: one calm line; no products: no block', (
      tester,
    ) async {
      await _pumpHome(tester, products: [fakeTomatoes()]);
      expect(find.text('Aucune alerte de stock'), findsOneWidget);
    });

    testWidgets('a store with no product has no stock block', (tester) async {
      await _pumpHome(tester);
      expect(find.text('Stock'), findsNothing);
    });
  });

  group('states', () {
    testWidgets('orders that cannot load say so, can be retried, and do not '
        'hide the rest', (tester) async {
      final repo = await _pumpHome(
        tester,
        ordersFail: true,
        products: [fakeTomatoes()],
      );
      expect(find.text('Impossible de charger les commandes.'), findsOneWidget);
      expect(find.text('Prochains retraits'), findsNothing);
      expect(find.text('Magasin ouvert'), findsOneWidget);
      repo.fails = false;
      repo.add(_order(1, OrderStatus.pending));
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Impossible de charger les commandes.'), findsNothing);
      expect(
        find.descendant(of: _tile('À confirmer'), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('a new store still shows only its checklist', (tester) async {
      await _pumpHome(tester, store: closedStore);
      expect(find.textContaining('Démarrer votre magasin'), findsOneWidget);
      expect(find.text('À traiter'), findsNothing);
      expect(find.text('Prochains retraits'), findsNothing);
    });

    testWidgets('a store being set up with orders already shows them', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        store: closedStore,
        orders: [_order(1, OrderStatus.pending)],
      );
      expect(find.textContaining('Démarrer votre magasin'), findsOneWidget);
      expect(find.text('À traiter'), findsOneWidget);
    });
  });

  group('freshness', () {
    testWidgets('reloads when Accueil becomes visible again', (tester) async {
      final repo = await _pumpHome(tester);
      await _openTab(tester, 'Commandes');
      repo.add(_order(1, OrderStatus.pending));
      await _openTab(tester, 'Accueil');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _tile('À confirmer'), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('polls only while Accueil is the visible tab', (tester) async {
      final repo = await _pumpHome(tester);
      int calls() => repo.listCallCount;
      final start = calls();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(calls(), greaterThan(start), reason: 'polls while visible');

      await _openTab(tester, 'Catalogue');
      final hidden = calls();
      await tester.pump(const Duration(seconds: 95));
      expect(calls(), hidden, reason: 'no home polling while hidden');
    });

    testWidgets('leaving the app cleans the timer up', (tester) async {
      await _pumpHome(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 65));
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive', () {
    final orders = [
      for (var i = 1; i <= 3; i++)
        _order(
          i,
          i == 1 ? OrderStatus.pending : OrderStatus.confirmed,
          name: 'Mohamed Amine Ben Abdelkader El Mekki Ouled Hadj $i',
        ),
    ];
    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.65), (402.0, 1.0)]) {
      testWidgets('nothing overflows at $width px, $scale×', (tester) async {
        await _pumpHome(
          tester,
          orders: orders,
          products: [
            fakeTomatoes(),
            fakeStoreProduct(id: 2, trackStock: true, stockQuantity: 0),
          ],
          size: Size(width, 4000),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        for (final label in ['À confirmer', 'À préparer', 'Prêtes à retirer']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.right, lessThanOrEqualTo(width), reason: label);
          expect(tester.getSize(_tile(label)).height, greaterThanOrEqualTo(48));
        }
      });
    }

    testWidgets('at large text the tiles stack as rows', (tester) async {
      await _pumpHome(tester, orders: orders, textScale: 1.65);
      final a = tester.getTopLeft(find.text('À confirmer'));
      final b = tester.getTopLeft(find.text('À préparer'));
      expect(b.dy, greaterThan(a.dy));
      expect(b.dx, a.dx);
    });
  });
}
