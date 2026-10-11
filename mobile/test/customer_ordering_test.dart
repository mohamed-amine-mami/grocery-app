import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_order.dart';
import 'package:grocery_mobile/data/models/customer_product.dart';
import 'package:grocery_mobile/data/models/customer_store.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/utils/date_formatters.dart';
import 'package:grocery_mobile/ui/core/utils/pickup_slots.dart';
import 'package:grocery_mobile/ui/features/auth/views/login_view.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/customer_scope.dart';

import 'fakes.dart';

class _Harness {
  _Harness({
    required this.stores,
    required this.orders,
    required this.openStore,
    required this.closedStore,
    required this.products,
  });

  final FakeCustomerStoresRepository stores;
  final FakeCustomerOrdersRepository orders;
  final CustomerStore openStore;
  final CustomerStore closedStore;
  final Map<int, List<CustomerProduct>> products;
}

/// Two open stores and a closed one, each with its own catalogue (and its own
/// price for milk), and a signed-in customer on the Magasins tab.
Future<_Harness> _pump(
  WidgetTester tester, {
  List<CustomerOrderSeed> seededOrders = const [],
  Size size = const Size(800, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final open = fakeCustomerStore(id: 10, name: 'Menzah Market');
  final other = fakeCustomerStore(
    id: 20,
    name: 'Lac Épicerie',
    address: '3 Avenue du Lac, Tunis',
  );
  final closed = fakeCustomerStore(
    id: 30,
    name: 'Ariana Primeur',
    address: '8 Rue de Marseille, Ariana',
    isOpen: false,
  );
  final banane = fakeCustomerProduct(id: 1, name: 'Banane');
  final milk = fakeMilk(id: 2);
  final products = {
    10: [
      banane,
      fakeCustomerProduct(
        id: 3,
        name: 'Pomme',
        priceMillimes: 2500,
        minQuantity: 1000,
        quantityStep: 500,
        maxQuantity: null,
      ),
      fakeCustomerProduct(
        id: 4,
        name: 'Œufs',
        category: fakeDairyCategory,
        unit: SaleUnit.piece,
        priceMillimes: 400,
        minQuantity: 6,
        quantityStep: 6,
        maxQuantity: 30,
      ),
      milk,
      fakeCustomerProduct(
        id: 5,
        name: 'Fraise',
        isOrderable: false,
        priceMillimes: 4000,
        minQuantity: 250,
        quantityStep: 250,
        maxQuantity: 2000,
        reason: UnavailabilityReason.outOfStock,
      ),
    ],
    // Another store: its own price for milk, and a product the first lacks.
    20: [
      fakeCustomerProduct(
        id: 12,
        name: 'Lait Délice 1 L',
        category: fakeDairyCategory,
        unit: SaleUnit.piece,
        priceMillimes: 1500,
        minQuantity: 1,
        quantityStep: 1,
        maxQuantity: 6,
      ),
      fakeCustomerProduct(id: 13, name: 'Orange', priceMillimes: 2200),
    ],
    30: [fakeCustomerProduct(id: 21, name: 'Cerise', priceMillimes: 9000)],
  };
  final api = ApiClient();
  final stores = FakeCustomerStoresRepository(
    api,
    stores: [open, other, closed],
    products: products,
  );
  final orders = FakeCustomerOrdersRepository(
    api,
    catalog: {
      for (final p in [...products[10]!, ...products[20]!]) p.id: p,
    },
    orders: [for (final seed in seededOrders) seed.order],
  );
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerStoresRepository: (_) => stores,
    customerOrdersRepository: (_) => orders,
  );
  return _Harness(
    stores: stores,
    orders: orders,
    openStore: open,
    closedStore: closed,
    products: products,
  );
}

class CustomerOrderSeed {
  const CustomerOrderSeed(this.order);
  final CustomerOrder order;
}

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(_navLabel(label));
  await tester.pumpAndSettle();
}

Future<void> _openStore(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Retour'));
  await tester.pumpAndSettle();
}

/// The add button of a product card (its label is the tooltip; the visible
/// text is just "Ajouter").
Finder _add(String product) => find.byTooltip('Ajouter $product');
Finder _plus(String product) =>
    find.byTooltip('Augmenter la quantité de $product');
Finder _minus(String product) =>
    find.byTooltip('Diminuer la quantité de $product');
Finder _trash(String product) => find.byTooltip('Retirer $product du panier');

/// A cart of 500 g of bananas at Menzah Market, then on to the checkout.
Future<void> _toCheckout(WidgetTester tester) async {
  await _openStore(tester, 'Menzah Market');
  await _tap(tester, _add('Banane'));
  await _tap(tester, _add('Lait Délice 1 L'));
  await tester.tap(find.textContaining('Voir le panier'));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Commander'));
}

void main() {
  group('store selection', () {
    testWidgets('lists every store with its address and open/closed state', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Magasins'), findsWidgets);
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('12 Rue de la Liberté, Tunis'), findsOneWidget);
      expect(find.text('Lac Épicerie'), findsOneWidget);
      expect(find.text('3 Avenue du Lac, Tunis'), findsOneWidget);
      expect(find.text('Ariana Primeur'), findsOneWidget);
      expect(find.text('Ouvert'), findsNWidgets(2));
      expect(find.text('Fermé'), findsOneWidget);
    });

    testWidgets('shows no owner information', (tester) async {
      await _pump(tester);
      expect(find.textContaining('karim'), findsNothing);
      expect(find.textContaining('+216'), findsNothing);
      expect(find.textContaining('propriétaire'), findsNothing);
    });

    testWidgets('a failed load says so and can be retried', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final stores = FakeCustomerStoresRepository(
        ApiClient(),
        stores: [fakeCustomerStore()],
        fails: true,
      );
      await pumpAppSignedInAs(
        tester,
        testClient,
        storeRepository: FakeStoreRepository.new,
        customerStoresRepository: (_) => stores,
      );
      expect(find.text('Impossible de charger les magasins.'), findsOneWidget);
      stores.fails = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Menzah Market'), findsOneWidget);
    });

    testWidgets(
      'a closed store opens and can be browsed, but not ordered from',
      (tester) async {
        final h = await _pump(tester);
        await _openStore(tester, 'Ariana Primeur');

        expect(find.text('Cerise'), findsOneWidget);
        expect(find.text('9,000 DT'), findsOneWidget);
        expect(find.text('/ kg'), findsOneWidget);
        expect(
          find.textContaining('Ce magasin est fermé pour le moment'),
          findsOneWidget,
        );
        expect(_add('Cerise'), findsNothing);
        expect(find.textContaining('Voir le panier'), findsNothing);
        expect(h.stores.productCalls, [30]);
      },
    );
  });

  group('store catalogue', () {
    testWidgets(
      'shows the store’s products with price, unit, minimum and category',
      (tester) async {
        await _pump(tester);
        await _openStore(tester, 'Menzah Market');

        expect(find.text('Fruits · 3'), findsOneWidget);
        expect(find.text('Produits laitiers · 2'), findsOneWidget);
        expect(find.text('Banane'), findsOneWidget);
        expect(find.text('1,800 DT'), findsOneWidget);
        expect(find.text('/ kg'), findsWidgets);
        // The minimum is said before adding — except for the obvious one piece.
        expect(find.text('Min. 500 g'), findsOneWidget);
        expect(find.text('Lait Délice 1 L'), findsOneWidget);
        expect(find.text('1,200 DT'), findsOneWidget);
        expect(find.text('/ pièce'), findsWidgets);
        expect(find.text('Œufs'), findsOneWidget);
        expect(find.text('Min. 6 pièces'), findsOneWidget);
        expect(find.text('Min. 1 kg'), findsOneWidget); // no maximum either
        expect(find.text('Min. 1 pièce'), findsNothing);
        // The cards are a grid: step and maximum are the stepper's business.
        expect(find.textContaining('par 100 g'), findsNothing);
        expect(find.textContaining('maximum'), findsNothing);
      },
    );

    testWidgets('an unavailable product says so and cannot be added', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');

      expect(find.text('Fraise'), findsOneWidget);
      expect(find.text('Indisponible'), findsOneWidget);
      expect(_add('Fraise'), findsNothing);
      expect(_add('Banane'), findsOneWidget);
    });

    testWidgets('never shows stock, or anything that hints at it', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      for (final word in [
        'tock',
        'Rupture',
        'restant',
        'quantité disponible',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      // The out-of-stock product reads like any unavailable one.
      expect(find.text('Indisponible'), findsOneWidget);
    });

    testWidgets('shows only this store’s products and prices', (tester) async {
      final h = await _pump(tester);
      await _openStore(tester, 'Lac Épicerie');

      expect(find.text('Orange'), findsOneWidget);
      expect(find.text('Lait Délice 1 L'), findsOneWidget);
      expect(find.text('1,500 DT'), findsOneWidget); // not Menzah's 1,200
      expect(find.text('1,200 DT'), findsNothing);
      expect(find.text('Banane'), findsNothing);
      expect(find.text('Pomme'), findsNothing);
      expect(find.text('Cerise'), findsNothing);
      expect(h.stores.productCalls, [20]);
    });

    testWidgets('search narrows the list, ignoring case and accents', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');

      await tester.enterText(find.byType(TextField), 'LAIT');
      await tester.pumpAndSettle();
      expect(find.text('Lait Délice 1 L'), findsOneWidget);
      expect(find.text('Banane'), findsNothing);

      await tester.enterText(find.byType(TextField), 'oeuf');
      await tester.pumpAndSettle();
      expect(find.text('Œufs'), findsOneWidget);
      expect(find.text('Lait Délice 1 L'), findsNothing);

      // Description and category are searched too.
      await tester.enterText(find.byType(TextField), 'demi');
      await tester.pumpAndSettle();
      expect(find.text('Lait Délice 1 L'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fruits');
      await tester.pumpAndSettle();
      expect(find.text('Banane'), findsOneWidget);
      expect(find.text('Pomme'), findsOneWidget);
    });

    testWidgets('no match says so, and the filters can be cleared', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit trouvé'), findsOneWidget);
      await tester.tap(find.text('Effacer les filtres'));
      await tester.pumpAndSettle();
      expect(find.text('Banane'), findsOneWidget);
    });

    testWidgets('category chips filter the catalogue', (tester) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');

      // Text tabs under the search field.
      Finder tab(String label) => find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(label),
      );
      expect(tab('Tous'), findsOneWidget);
      await tester.tap(tab('Produits laitiers'));
      await tester.pumpAndSettle();
      expect(find.text('Lait Délice 1 L'), findsOneWidget);
      expect(find.text('Œufs'), findsOneWidget);
      expect(find.text('Banane'), findsNothing);

      await tester.tap(tab('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Banane'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final h = await _pump(tester);
      h.stores.failingStores.add(10);
      await _openStore(tester, 'Menzah Market');
      expect(find.text('Impossible de charger le catalogue.'), findsOneWidget);
      h.stores.failingStores.clear();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Banane'), findsOneWidget);
    });
  });

  group('adding and the quantity stepper', () {
    testWidgets('Ajouter puts the minimum in the cart, then − quantity +', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');

      await _tap(tester, _add('Banane'));
      expect(_add('Banane'), findsNothing);
      expect(find.text('500 g'), findsOneWidget); // the minimum
      // The bar: the count and the estimated total beside the action.
      expect(find.text('Voir le panier'), findsOneWidget);
      expect(find.text('1 produit'), findsOneWidget);
      expect(find.text('0,900 DT'), findsOneWidget);

      await _tap(tester, _plus('Banane'));
      expect(find.text('600 g'), findsOneWidget); // the product's own step
      expect(find.text('1,080 DT'), findsOneWidget);
    });

    testWidgets('pieces use their own step and minimum', (tester) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      await _tap(tester, _add('Œufs'));
      expect(find.text('6 pièces'), findsOneWidget);
      await _tap(tester, _plus('Œufs'));
      expect(find.text('12 pièces'), findsOneWidget);
    });

    testWidgets('the plus stops at the maximum', (tester) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      await _tap(tester, _add('Œufs')); // 6, max 30
      for (var i = 0; i < 4; i++) {
        await _tap(tester, _plus('Œufs'));
      }
      expect(find.text('30 pièces'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Quantité maximale atteinte pour Œufs'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byTooltip('Quantité maximale atteinte pour Œufs'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('30 pièces'), findsOneWidget);
    });

    testWidgets('the minus steps down, and at the minimum removes the line', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      await _tap(tester, _add('Banane'));
      await _tap(tester, _plus('Banane'));
      await _tap(tester, _minus('Banane'));
      expect(find.text('500 g'), findsOneWidget);

      // At the minimum the control says what it does: it removes.
      expect(_minus('Banane'), findsNothing);
      expect(_trash('Banane'), findsOneWidget);
      await _tap(tester, _trash('Banane'));
      expect(_add('Banane'), findsOneWidget);
      expect(find.textContaining('Voir le panier'), findsNothing);
    });
  });

  group('cart', () {
    testWidgets('is empty at first, with a way to the stores', (tester) async {
      await _pump(tester);
      await _tab(tester, 'Panier');
      expect(find.text('Votre panier est vide'), findsOneWidget);
      await tester.tap(find.text('Voir les magasins'));
      await tester.pumpAndSettle();
      expect(find.text('Menzah Market'), findsOneWidget);
    });

    testWidgets(
      'lists each line with quantity, unit, price and subtotal, and an estimated total',
      (tester) async {
        await _pump(tester);
        await _openStore(tester, 'Menzah Market');
        await _tap(tester, _add('Banane'));
        await _tap(tester, _plus('Banane'));
        await _tap(tester, _add('Lait Délice 1 L'));
        await tester.tap(find.textContaining('Voir le panier'));
        await tester.pumpAndSettle();

        expect(find.text('Panier'), findsWidgets);
        expect(find.text('Menzah Market'), findsOneWidget);
        expect(find.text('Banane'), findsOneWidget);
        expect(find.text('1,800 DT / kg'), findsOneWidget);
        expect(find.text('600 g'), findsOneWidget);
        expect(find.text('1,080 DT'), findsOneWidget); // 600 g × 1,800/kg
        expect(find.text('Lait Délice 1 L'), findsOneWidget);
        expect(find.text('1 pièce'), findsOneWidget);
        expect(find.text('1,200 DT'), findsWidgets);
        expect(find.text('Total estimé'), findsOneWidget);
        // 1,080 + 1,200: in the total card and in the action bar.
        expect(find.text('2,280 DT'), findsNWidgets(2));
        expect(
          find.text(
            'Le total définitif est confirmé à l’envoi de la commande.',
          ),
          findsOneWidget,
        );
        // The badge counts the products.
        expect(find.byType(Badge), findsOneWidget);
        for (final word in ['tock']) {
          expect(find.textContaining(word), findsNothing);
        }
      },
    );

    testWidgets(
      'increments, decrements and removes, keeping the total in step',
      (tester) async {
        await _pump(tester);
        await _openStore(tester, 'Menzah Market');
        await _tap(tester, _add('Banane'));
        await tester.tap(find.textContaining('Voir le panier'));
        await tester.pumpAndSettle();

        await _tap(tester, _plus('Banane'));
        expect(find.text('600 g'), findsOneWidget);
        expect(find.text('1,080 DT'), findsWidgets);
        await _tap(tester, _minus('Banane'));
        expect(find.text('500 g'), findsOneWidget);
        await _tap(tester, _trash('Banane'));
        expect(find.text('Votre panier est vide'), findsOneWidget);
      },
    );

    testWidgets(
      'a product that is no longer available blocks ordering until removed',
      (tester) async {
        final h = await _pump(tester);
        await _openStore(tester, 'Menzah Market');
        await _tap(tester, _add('Banane'));
        await _tap(tester, _add('Lait Délice 1 L'));

        // The catalogue changes behind the customer's back; pulling refreshes it.
        h.stores.setProducts(10, [
          fakeCustomerProduct(id: 1, name: 'Banane', isOrderable: false),
          fakeMilk(id: 2),
        ]);
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, 1800),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Voir le panier'));
        await tester.pumpAndSettle();

        expect(
          find.text('Ce produit n’est plus disponible. Retirez-le du panier.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ElevatedButton>(
                find.ancestor(
                  of: find.text('Commander'),
                  matching: find.byType(ElevatedButton),
                ),
              )
              .onPressed,
          isNull,
        );
        await _tap(tester, find.text('Retirer'));
        expect(find.text('Banane'), findsNothing);
        expect(
          tester
              .widget<ElevatedButton>(
                find.ancestor(
                  of: find.text('Commander'),
                  matching: find.byType(ElevatedButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
      },
    );
  });

  group('switching store', () {
    testWidgets('with an empty cart the other store is used without asking', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      await _tap(tester, _add('Banane'));
      await _tap(tester, _trash('Banane')); // empty again
      await _back(tester);

      await _openStore(tester, 'Lac Épicerie');
      await _tap(tester, _add('Orange'));
      expect(find.text('Changer de magasin ?'), findsNothing);
      expect(find.text('Voir le panier'), findsOneWidget);
      expect(find.text('1 produit'), findsOneWidget);
    });

    Future<void> startAtMenzahThenOpenLac(WidgetTester tester) async {
      await _openStore(tester, 'Menzah Market');
      await _tap(tester, _add('Banane'));
      await _back(tester);
      await _openStore(tester, 'Lac Épicerie');
    }

    testWidgets(
      'with products in the cart it asks, and says the cart will be emptied',
      (tester) async {
        await _pump(tester);
        await startAtMenzahThenOpenLac(tester);
        await _tap(tester, _add('Orange'));

        expect(find.text('Changer de magasin ?'), findsOneWidget);
        expect(
          find.text(
            'Votre panier contient des produits de Menzah Market. Changer de magasin videra votre panier.',
          ),
          findsOneWidget,
        );
        // Nothing changed yet: the Orange is not in a cart.
        expect(find.textContaining('Voir le panier'), findsNothing);
      },
    );

    testWidgets('cancelling keeps the cart and the current store', (
      tester,
    ) async {
      await _pump(tester);
      await startAtMenzahThenOpenLac(tester);
      await _tap(tester, _add('Orange'));
      await tester.tap(find.text('Garder mon panier'));
      await tester.pumpAndSettle();

      expect(find.text('Changer de magasin ?'), findsNothing);
      expect(_add('Orange'), findsOneWidget); // not added
      await _back(tester);
      await _tab(tester, 'Panier');
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('Banane'), findsOneWidget);
      expect(find.text('Orange'), findsNothing);
    });

    testWidgets('confirming empties the cart and the new store takes over', (
      tester,
    ) async {
      await _pump(tester);
      await startAtMenzahThenOpenLac(tester);
      await _tap(tester, _add('Orange'));
      await tester.tap(find.text('Vider et changer'));
      await tester.pumpAndSettle();

      expect(find.text('Changer de magasin ?'), findsNothing);
      expect(find.text('Voir le panier'), findsOneWidget);
      expect(find.text('1 produit'), findsOneWidget);
      await _back(tester);
      await _tab(tester, 'Panier');
      expect(find.text('Lac Épicerie'), findsOneWidget);
      expect(find.text('Orange'), findsOneWidget);
      expect(find.text('Banane'), findsNothing);
    });
  });

  group('checkout', () {
    testWidgets(
      'shows the order, the estimated total, the pickup time and payment',
      (tester) async {
        await _pump(tester);
        await _toCheckout(tester);

        expect(find.text('Valider la commande'), findsOneWidget);
        expect(find.text('Menzah Market'), findsOneWidget);
        expect(find.text('Banane'), findsOneWidget);
        // Quantity and unit price are two pieces of one line (they break
        // between them, never inside the unit price).
        expect(find.text('500 g ·'), findsOneWidget);
        expect(find.text('1,800 DT / kg'), findsOneWidget);
        expect(find.text('0,900 DT'), findsOneWidget);
        expect(find.text('Lait Délice 1 L'), findsOneWidget);
        expect(find.text('1 pièce ·'), findsOneWidget);
        expect(find.text('1,200 DT / pièce'), findsOneWidget);
        expect(find.text('Total estimé'), findsOneWidget);
        // In the total card and in the confirm bar.
        expect(find.text('2,100 DT'), findsNWidgets(2));
        expect(
          find.text(
            'Le total définitif est confirmé à l’envoi de la commande.',
          ),
          findsOneWidget,
        );
        expect(find.text('Paiement'), findsOneWidget);
        expect(find.text('À la récupération'), findsOneWidget);
        expect(find.text('Heure de retrait souhaitée'), findsOneWidget);
        expect(
          find.text('C’est une heure souhaitée, pas un créneau réservé.'),
          findsOneWidget,
        );
        // Nothing internal.
        for (final word in ['tock', 'propriétaire']) {
          expect(find.textContaining(word), findsNothing);
        }
      },
    );

    testWidgets('proposes the earliest slot and a list of 30-minute choices', (
      tester,
    ) async {
      await _pump(tester);
      await _toCheckout(tester);

      final offered = [
        for (final slot in PickupSlots.generate(DateTime.now()).take(3))
          DateFormatFr.pickup(slot),
      ];
      expect(
        offered.any((text) => find.text(text).evaluate().isNotEmpty),
        isTrue,
        reason: 'the default pickup time is one of the earliest slots',
      );

      await tester.tap(find.byKey(const Key('pickup-field')));
      await tester.pumpAndSettle();
      final keys = [
        for (final element
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith('slot-'),
                )
                .evaluate())
          int.parse(
            (element.widget.key! as ValueKey<String>).value.substring(5),
          ),
      ]..sort();
      expect(keys.length, greaterThan(8));
      final now = DateTime.now();
      expect(
        DateTime.fromMillisecondsSinceEpoch(keys.first).difference(now),
        greaterThanOrEqualTo(const Duration(minutes: 30)),
      );
      for (var i = 1; i < keys.length; i++) {
        expect(
          DateTime.fromMillisecondsSinceEpoch(keys[i])
              .difference(DateTime.fromMillisecondsSinceEpoch(keys[i - 1])),
          const Duration(minutes: 30),
        );
      }
    });

    testWidgets('a chosen slot is the one that is sent', (tester) async {
      final h = await _pump(tester);
      await _toCheckout(tester);
      await tester.tap(find.byKey(const Key('pickup-field')));
      await tester.pumpAndSettle();
      final tile = find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('slot-'),
          )
          .at(3);
      final chosen = DateTime.fromMillisecondsSinceEpoch(
        int.parse(
          (tester.widget(tile).key! as ValueKey<String>).value.substring(5),
        ),
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text(DateFormatFr.pickup(chosen)), findsOneWidget);

      await _tap(tester, find.text('Confirmer la commande'));
      expect(h.orders.created.single.requestedPickupAt, chosen);
    });

    testWidgets(
      'a closed store cannot be ordered from: sending is disabled, nothing is sent',
      (tester) async {
        final h = await _pump(tester);
        await _openStore(tester, 'Menzah Market');
        await _tap(tester, _add('Banane'));
        // The store closes while the customer is shopping.
        h.stores.setStores([
          h.openStore.copyWith(isOpen: false),
          fakeCustomerStore(id: 20, name: 'Lac Épicerie'),
          h.closedStore,
        ]);
        await tester.tap(find.textContaining('Voir le panier'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Commander'));

        expect(
          find.text(
            'Ce magasin est fermé pour le moment : la commande ne peut pas être envoyée.',
          ),
          findsOneWidget,
        );
        final send = find.ancestor(
          of: find.text('Confirmer la commande'),
          matching: find.byType(ElevatedButton),
        );
        expect(tester.widget<ElevatedButton>(send).onPressed, isNull);
        expect(h.orders.created, isEmpty);
      },
    );
  });

  group('submission', () {
    testWidgets('shows the server’s order, then empties the cart', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.orders.respond = (request) => fakeCustomerOrder(
        id: 55,
        code: 'SRV123',
        totalMillimes: 7777, // the server's figure, not the cart's 2,100
        items: [
          fakeOrderItem(id: 551, name: 'Banane (serveur)', lineTotal: 7777),
        ],
      );
      await _toCheckout(tester);
      await _tap(tester, find.text('Confirmer la commande'));

      // Server values on the order screen.
      expect(find.text('Commande SRV123'), findsOneWidget);
      expect(find.text('Commande envoyée'), findsOneWidget);
      expect(find.text('7,777 DT'), findsWidgets);
      expect(find.text('Banane (serveur)'), findsOneWidget);
      expect(find.text('2,100 DT'), findsNothing);
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('À la récupération'), findsOneWidget);

      // The request carried no price or total.
      final json = h.orders.created.single.toJson();
      expect(json.keys.toSet(), {
        'storeId',
        'lines',
        'requestedPickupAt',
        'idempotencyKey',
      });
      expect(json['storeId'], 10);
      expect(
        [for (final l in json['lines'] as List) (l as Map)['storeProductId']],
        [1, 2],
      );

      // The cart is now empty.
      await tester.tap(find.text('Continuer mes achats'));
      await tester.pumpAndSettle();
      await _tab(tester, 'Panier');
      expect(find.text('Votre panier est vide'), findsOneWidget);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('offers the way back to the orders', (tester) async {
      await _pump(tester);
      await _toCheckout(tester);
      await _tap(tester, find.text('Confirmer la commande'));
      await tester.tap(find.text('Voir mes commandes'));
      await tester.pumpAndSettle();

      expect(_navLabel('Commandes'), findsOneWidget);
      expect(find.textContaining('SRV'), findsOneWidget); // listed
      expect(find.text('Commande envoyée'), findsNothing);
    });

    testWidgets(
      'a network failure keeps the cart and retries with the same key',
      (tester) async {
        final h = await _pump(tester);
        h.orders.createErrors.add(const NetworkException('timeout'));
        await _toCheckout(tester);
        await _tap(tester, find.text('Confirmer la commande'));

        expect(
          find.text(
            'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
          ),
          findsOneWidget,
        );
        expect(find.text('Valider la commande'), findsOneWidget); // still here
        expect(find.text('Réessayer l’envoi'), findsOneWidget);

        await _tap(tester, find.text('Réessayer l’envoi'));

        expect(h.orders.created, hasLength(2));
        expect(
          h.orders.created[1].idempotencyKey,
          h.orders.created[0].idempotencyKey,
        );
        expect(find.text('Commande envoyée'), findsOneWidget);
      },
    );

    testWidgets(
      'STORE_CLOSED from the backend is explained and blocks sending',
      (tester) async {
        final h = await _pump(tester);
        h.orders.createErrors.add(
          const ApiException(statusCode: 409, code: 'STORE_CLOSED'),
        );
        await _toCheckout(tester);
        await _tap(tester, find.text('Confirmer la commande'));
        expect(
          find.text(
            'Ce magasin est fermé pour le moment : la commande ne peut pas être envoyée.',
          ),
          findsOneWidget,
        );
        final send = find.ancestor(
          of: find.text('Confirmer la commande'),
          matching: find.byType(ElevatedButton),
        );
        expect(tester.widget<ElevatedButton>(send).onPressed, isNull);
      },
    );

    testWidgets(
      'PRODUCT_UNAVAILABLE explains and sends the customer back to review the cart',
      (tester) async {
        final h = await _pump(tester);
        h.orders.createErrors.add(
          const ApiException(statusCode: 409, code: 'PRODUCT_UNAVAILABLE'),
        );
        await _toCheckout(tester);
        // The banana runs out while the customer is on the checkout.
        h.stores.setProducts(10, [
          fakeCustomerProduct(id: 1, name: 'Banane', isOrderable: false),
          fakeMilk(id: 2),
        ]);
        await _tap(tester, find.text('Confirmer la commande'));
        expect(
          find.text(
            'Un ou plusieurs produits ne sont plus disponibles. Vérifiez votre panier.',
          ),
          findsOneWidget,
        );
        await _back(tester);
        expect(
          find.text('Ce produit n’est plus disponible. Retirez-le du panier.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('INVALID_PICKUP_TIME asks for another time', (tester) async {
      final h = await _pump(tester);
      h.orders.createErrors.add(
        const ApiException(statusCode: 400, code: 'INVALID_PICKUP_TIME'),
      );
      await _toCheckout(tester);
      await _tap(tester, find.text('Confirmer la commande'));
      expect(
        find.text(
          'L’heure de retrait choisie n’est plus possible. Choisissez un autre horaire.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pickup-field')), findsOneWidget);
    });

    testWidgets('an unknown server error shows no raw text', (tester) async {
      final h = await _pump(tester);
      h.orders.createErrors.add(
        const ApiException(
          statusCode: 500,
          message: 'Error: relation "x" does not exist',
        ),
      );
      await _toCheckout(tester);
      await _tap(tester, find.text('Confirmer la commande'));
      expect(
        find.text('Une erreur est survenue. Veuillez réessayer.'),
        findsOneWidget,
      );
      expect(find.textContaining('relation'), findsNothing);
    });

    testWidgets(
      'a rejected token signs the customer out through the existing flow',
      (tester) async {
        final h = await _pump(tester);
        h.orders.createErrors.add(const ApiException(statusCode: 401));
        await _toCheckout(tester);
        await _tap(tester, find.text('Confirmer la commande'));
        expect(find.text('Connexion'), findsWidgets);
      },
    );
  });

  group('signing out', () {
    testWidgets('leaves nothing of the customer’s cart for the next person', (
      tester,
    ) async {
      await _pump(tester);
      await _openStore(tester, 'Menzah Market');
      await _tap(tester, _add('Banane'));
      await _back(tester);
      await _tab(tester, 'Profil');
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginView), findsOneWidget);
      final scope = CustomerScope.of(tester.element(find.byType(LoginView)));
      expect(scope.cart.isEmpty, isTrue);
      expect(scope.cart.store, isNull);
      expect(scope.navigation.tab, CustomerTab.stores);
    });
  });

  group('the just-sent welcome', () {
    testWidgets('goes away once the order is no longer waiting for the store', (
      tester,
    ) async {
      await _pump(tester);
      await _toCheckout(tester);
      await _tap(tester, find.text('Confirmer la commande'));
      expect(find.text('Commande envoyée'), findsOneWidget);

      // Cancelling it from the same screen: nothing is "sent" any more.
      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Annuler la commande'),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Annuler la commande'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsWidgets);
      expect(find.text('Commande envoyée'), findsNothing);
      expect(find.text('Voir mes commandes'), findsNothing);
    });
  });
}
