import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/cart_view_model.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/checkout_failure.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/checkout_view_model.dart';

import 'fakes.dart';

final _now = DateTime(2026, 10, 4, 10, 10);
final _banane = fakeCustomerProduct(id: 1);
final _milk = fakeMilk(id: 2);

/// A cart with 700 g of bananas and 2 milks at an open store, a checkout over
/// it, and fakes that remember what was sent.
({
  CartViewModel cart,
  CheckoutViewModel checkout,
  FakeCustomerOrdersRepository orders,
  FakeCustomerStoresRepository stores,
  List<String> keys,
})
_setup({bool open = true, DateTime Function()? now}) {
  final store = fakeCustomerStore(id: 10, isOpen: open);
  final cart = CartViewModel();
  // Add as an open store, then record the real state (a closed store takes no
  // adds): the customer may have filled the cart before it closed.
  cart
    ..add(store.copyWith(isOpen: true), _banane)
    ..increment(1)
    ..increment(1)
    ..add(store.copyWith(isOpen: true), _milk)
    ..increment(2);
  cart.updateStore(store);
  final api = ApiClient();
  final orders = FakeCustomerOrdersRepository(
    api,
    catalog: {1: _banane, 2: _milk},
  );
  final stores = FakeCustomerStoresRepository(
    api,
    stores: [store],
    products: {
      10: [_banane, _milk],
    },
  );
  final keys = <String>[];
  var counter = 0;
  final checkout = CheckoutViewModel(
    ordersRepository: orders,
    storesRepository: stores,
    cart: cart,
    now: now ?? () => _now,
    generateKey: () {
      final key = 'key-${++counter}';
      keys.add(key);
      return key;
    },
  );
  return (
    cart: cart,
    checkout: checkout,
    orders: orders,
    stores: stores,
    keys: keys,
  );
}

void main() {
  group('pickup time', () {
    test(
      'offers 30-minute slots from 30 minutes to 48 hours, earliest selected',
      () {
        final s = _setup();
        final slots = s.checkout.slots;
        expect(slots.first, DateTime(2026, 10, 4, 11));
        expect(s.checkout.selectedSlot, slots.first);
        for (var i = 1; i < slots.length; i++) {
          expect(
            slots[i].difference(slots[i - 1]),
            const Duration(minutes: 30),
          );
        }
        expect(
          slots.first.difference(_now),
          greaterThanOrEqualTo(const Duration(minutes: 30)),
        );
        expect(
          slots.last.difference(_now),
          lessThanOrEqualTo(const Duration(hours: 48)),
        );
      },
    );

    test('only an offered slot can be selected', () {
      final s = _setup();
      s.checkout.selectSlot(DateTime(2026, 10, 4, 10, 15)); // not on offer
      expect(s.checkout.selectedSlot, s.checkout.slots.first);
      s.checkout.selectSlot(s.checkout.slots[3]);
      expect(s.checkout.selectedSlot, s.checkout.slots[3]);
    });

    test('refreshing keeps a still-valid choice and replaces a stale one', () {
      var now = _now;
      final s = _setup(now: () => now);
      final chosen = s.checkout.slots[4]; // 13:00
      s.checkout.selectSlot(chosen);

      now = _now.add(const Duration(minutes: 20));
      s.checkout.refreshSlots();
      expect(s.checkout.selectedSlot, chosen);

      now = DateTime(2026, 10, 4, 12, 45); // 13:00 is now under 30 minutes away
      s.checkout.refreshSlots();
      expect(s.checkout.selectedSlot, s.checkout.slots.first);
      expect(s.checkout.selectedSlot, isNot(chosen));
    });
  });

  group('submitting', () {
    test('sends the store, the store product ids, quantities, pickup and a key — nothing else', () async {
      final s = _setup();
      final slot = s.checkout.slots[2];
      s.checkout.selectSlot(slot);

      final order = await s.checkout.submit();

      expect(order, isNotNull);
      final request = s.orders.created.single;
      expect(request.storeId, 10);
      expect([for (final l in request.lines) l.storeProductId], [1, 2]);
      expect([for (final l in request.lines) l.quantity], [700, 2]);
      expect(request.requestedPickupAt, slot);
      expect(request.idempotencyKey, 'key-1');

      // The wire format: no price, total, stock, name, unit, status, customer.
      final json = request.toJson();
      expect(json.keys.toSet(), {
        'storeId',
        'lines',
        'requestedPickupAt',
        'idempotencyKey',
      });
      for (final line in json['lines'] as List) {
        expect((line as Map).keys.toSet(), {'storeProductId', 'quantity'});
      }
      final text = json.toString().toLowerCase();
      for (final forbidden in [
        'price',
        'total',
        'stock',
        'name',
        'unit',
        'status',
        'customer',
        'owner',
      ]) {
        expect(text.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the server’s order is the one shown, not one rebuilt from the cart', () async {
      final s = _setup();
      // The server prices differently from the cart's estimate (2,100 + more).
      s.orders.respond = (request) =>
          fakeCustomerOrder(id: 77, code: 'SERVER', totalMillimes: 99999);

      final order = await s.checkout.submit();

      expect(order?.code, 'SERVER');
      expect(order?.totalMillimes, 99999);
      expect(s.checkout.created?.code, 'SERVER');
      // The estimate was different and was never sent.
      expect(s.cart.estimatedTotalMillimes, isNot(99999));
    });

    test('the cart is cleared only once the order was created', () async {
      final s = _setup();
      s.orders.createErrors.add(const ApiException(statusCode: 500));
      expect(await s.checkout.submit(), isNull);
      expect(s.cart.isEmpty, isFalse); // still there after a failure

      expect(await s.checkout.submit(), isNotNull);
      expect(s.cart.isEmpty, isTrue);
      expect(s.cart.store, isNull);
    });

    test('an order that was created is never sent a second time', () async {
      final s = _setup();
      final first = await s.checkout.submit();
      final again = await s.checkout.submit();
      expect(identical(first, again), isTrue);
      expect(s.orders.created, hasLength(1));
    });

    test('presses while a request is running send nothing more', () async {
      final s = _setup();
      final first = s.checkout.submit();
      final second = s.checkout.submit();
      expect(await second, isNull);
      await first;
      expect(s.orders.created, hasLength(1));
    });

    test(
      'each submission has a fresh key, kept only for its own attempt',
      () async {
        final s = _setup();
        await s.checkout.submit();
        expect(s.keys, ['key-1']);
        expect(s.checkout.pendingKey, isNull); // nothing kept after success
      },
    );
  });

  group('idempotency on retry', () {
    test(
      'a network failure keeps the key: the retry sends the same one',
      () async {
        final s = _setup();
        s.orders.createErrors.add(const NetworkException('timeout'));

        expect(await s.checkout.submit(), isNull);
        expect(s.checkout.failure?.kind, CheckoutFailureKind.network);
        expect(s.checkout.pendingKey, 'key-1');
        expect(s.cart.isEmpty, isFalse);

        final order = await s.checkout.submit();

        expect(order, isNotNull);
        expect(s.keys, ['key-1']); // no new key was generated
        expect(s.orders.created.map((r) => r.idempotencyKey), [
          'key-1',
          'key-1',
        ]);
        expect(s.checkout.pendingKey, isNull);
      },
    );

    test('the retry sends exactly the same request', () async {
      final s = _setup();
      s.orders.createErrors.add(const NetworkException('timeout'));
      await s.checkout.submit();
      await s.checkout.submit();
      final [first, second] = s.orders.created;
      expect(second.toJson(), first.toJson());
    });

    test('a timeout after the server created the order yields that one order, once', () async {
      final s = _setup();
      s.orders.createThenTimeout = true; // the order exists, the reply was lost

      expect(await s.checkout.submit(), isNull);
      final order = await s.checkout.submit();

      expect(order, isNotNull);
      final page = await s.orders.list();
      expect(page.total, 1); // not two orders
      expect(order!.id, page.orders.single.id);
      expect(s.cart.isEmpty, isTrue);
    });

    test('a server error keeps the key too: the outcome is unknown', () async {
      final s = _setup();
      s.orders.createErrors.add(
        const ApiException(statusCode: 500, message: 'boom'),
      );
      await s.checkout.submit();
      expect(s.checkout.failure?.kind, CheckoutFailureKind.unknown);
      expect(s.checkout.pendingKey, 'key-1');
      await s.checkout.submit();
      expect(s.keys, ['key-1']);
    });

    test('a changed cart is a different request: it gets a new key', () async {
      final s = _setup();
      s.orders.createErrors.add(const NetworkException('timeout'));
      await s.checkout.submit();
      expect(s.checkout.pendingKey, 'key-1');

      s.cart.increment(1); // not the same request any more
      await s.checkout.submit();

      expect(s.keys, ['key-1', 'key-2']);
      expect(s.orders.created.map((r) => r.idempotencyKey), ['key-1', 'key-2']);
    });

    test('a changed pickup time is a different request too', () async {
      final s = _setup();
      s.orders.createErrors.add(const NetworkException('timeout'));
      await s.checkout.submit();
      s.checkout.selectSlot(s.checkout.slots[5]);
      await s.checkout.submit();
      expect(s.keys, ['key-1', 'key-2']);
    });

    test(
      'a retry goes out as it was even if the pickup time has since gone stale',
      () async {
        var now = _now;
        final s = _setup(now: () => now);
        s.orders.createErrors.add(const NetworkException('timeout'));
        await s.checkout.submit();
        final slot = s.checkout.selectedSlot!;

        now = slot.subtract(const Duration(minutes: 5)); // too soon by now
        expect(await s.checkout.submit(), isNotNull);

        // Same request, same key: the backend answers with the original order
        // when the first call did get through; it is the authority.
        expect(s.orders.created.map((r) => r.requestedPickupAt), [slot, slot]);
        expect(s.keys, ['key-1']);
      },
    );

    test('a refusal ends the attempt: the next one has a new key', () async {
      final s = _setup();
      s.orders.createErrors.add(
        const ApiException(statusCode: 409, code: 'PRODUCT_UNAVAILABLE'),
      );
      await s.checkout.submit();
      expect(s.checkout.pendingKey, isNull);
    });
  });

  group('errors', () {
    Future<CheckoutFailure?> failWith(
      ({
        CartViewModel cart,
        CheckoutViewModel checkout,
        FakeCustomerOrdersRepository orders,
        FakeCustomerStoresRepository stores,
        List<String> keys,
      })
      s,
      ApiException error,
    ) async {
      s.orders.createErrors.add(error);
      await s.checkout.submit();
      expect(s.cart.isEmpty, isFalse, reason: 'the cart survives a failure');
      return s.checkout.failure;
    }

    test('STORE_CLOSED says the store is closed and blocks sending', () async {
      final s = _setup();
      final failure = await failWith(
        s,
        const ApiException(statusCode: 409, code: 'STORE_CLOSED'),
      );
      expect(failure?.kind, CheckoutFailureKind.storeClosed);
      expect(failure?.message, contains('fermé'));
      expect(s.cart.store?.isOpen, isFalse);
      expect(s.checkout.canSubmit, isFalse);
    });

    test('PRODUCT_UNAVAILABLE explains, refreshes the catalogue and flags the cart', () async {
      final s = _setup();
      s.stores.setProducts(10, [
        fakeCustomerProduct(id: 1, isOrderable: false),
        _milk,
      ]);
      final failure = await failWith(
        s,
        const ApiException(
          statusCode: 409,
          code: 'PRODUCT_UNAVAILABLE',
          body: {
            'lines': [
              {'storeProductId': 1, 'reason': 'OUT_OF_STOCK'},
            ],
          },
        ),
      );
      expect(failure?.kind, CheckoutFailureKind.productUnavailable);
      expect(failure?.message, contains('ne sont plus disponibles'));
      expect(failure?.productIds, [1]);
      expect(s.stores.productCalls, [10]);
      expect(s.cart.lines.first.problem, CartProblem.unavailable);
      expect(s.cart.lines.last.problem, isNull);
      expect(s.checkout.canSubmit, isFalse); // review first
    });

    test(
      'INSUFFICIENT_STOCK names no quantity and refreshes the cart',
      () async {
        final s = _setup();
        final failure = await failWith(
          s,
          const ApiException(
            statusCode: 409,
            code: 'INSUFFICIENT_STOCK',
            body: {'storeProductId': 1},
          ),
        );
        expect(failure?.kind, CheckoutFailureKind.insufficientStock);
        expect(failure?.productIds, [1]);
        expect(failure?.message, isNot(matches(RegExp(r'\d'))));
        expect(s.stores.productCalls, [10]);
      },
    );

    test('INVALID_QUANTITY asks for a correction of the cart', () async {
      final s = _setup();
      s.stores.setProducts(10, [
        fakeCustomerProduct(id: 1, minQuantity: 1000, quantityStep: 500),
        _milk,
      ]);
      final failure = await failWith(
        s,
        const ApiException(statusCode: 400, code: 'INVALID_QUANTITY'),
      );
      expect(failure?.kind, CheckoutFailureKind.invalidQuantity);
      expect(failure?.message, contains('quantité'));
      expect(s.cart.lines.first.problem, CartProblem.invalidQuantity);
      expect(s.checkout.canSubmit, isFalse);
    });

    test('INVALID_PICKUP_TIME recalculates the slots', () async {
      var now = _now;
      final s = _setup(now: () => now);
      final stale = s.checkout.selectedSlot!;
      now = stale.subtract(const Duration(minutes: 10));
      s.orders.createErrors.add(
        const ApiException(statusCode: 400, code: 'INVALID_PICKUP_TIME'),
      );
      await s.checkout.submit();

      expect(s.checkout.failure?.kind, CheckoutFailureKind.invalidPickupTime);
      expect(s.checkout.selectedSlot, isNot(stale));
      expect(s.checkout.slots.first.isAfter(stale), isTrue);
      expect(s.checkout.pendingKey, isNull);
    });

    test(
      'IDEMPOTENCY_KEY_REUSED is a conflict, not a retry: the key is dropped',
      () async {
        final s = _setup();
        final failure = await failWith(
          s,
          const ApiException(statusCode: 409, code: 'IDEMPOTENCY_KEY_REUSED'),
        );
        expect(failure?.kind, CheckoutFailureKind.keyReused);
        expect(failure?.message, contains('conflit'));
        expect(s.checkout.pendingKey, isNull);
        expect(s.orders.created, hasLength(1)); // nothing was re-sent
      },
    );

    test('404 says the store or product is gone', () async {
      final s = _setup();
      final failure = await failWith(s, const ApiException(statusCode: 404));
      expect(failure?.kind, CheckoutFailureKind.notFound);
      expect(failure?.message, contains('n’existe plus'));
    });

    test('401 is a session problem, not a refusal of the order', () async {
      final s = _setup();
      final failure = await failWith(s, const ApiException(statusCode: 401));
      expect(failure?.kind, CheckoutFailureKind.sessionExpired);
      expect(s.checkout.pendingKey, 'key-1'); // the outcome is not settled
    });

    test('an unknown error never shows raw backend text', () async {
      final s = _setup();
      final failure = await failWith(
        s,
        const ApiException(
          statusCode: 500,
          message: 'TypeError: boom at db.ts',
        ),
      );
      expect(failure?.message, 'Une erreur est survenue. Veuillez réessayer.');
      expect(failure?.message, isNot(contains('boom')));
    });

    test(
      'a refusal that needs review clears when the next attempt starts',
      () async {
        final s = _setup();
        s.orders.createErrors.add(const NetworkException('timeout'));
        await s.checkout.submit();
        expect(s.checkout.failure, isNotNull);
        await s.checkout.submit();
        expect(s.checkout.failure, isNull);
      },
    );
  });

  group('a closed store', () {
    test('cannot be ordered from: nothing is sent', () async {
      final s = _setup(open: false);
      expect(s.checkout.storeClosed, isTrue);
      expect(s.checkout.canSubmit, isFalse);

      expect(await s.checkout.submit(), isNull);

      expect(s.orders.created, isEmpty);
      expect(s.checkout.failure?.kind, CheckoutFailureKind.storeClosed);
      expect(s.cart.isEmpty, isFalse);
    });

    test(
      'a store that closed since browsing is known before sending',
      () async {
        final s = _setup();
        s.stores.setStores([fakeCustomerStore(id: 10, isOpen: false)]);
        await s.checkout.refreshStoreState();
        expect(s.checkout.storeClosed, isTrue);
        expect(s.checkout.canSubmit, isFalse);
      },
    );

    test('an offline refresh of the store state changes nothing', () async {
      final s = _setup();
      s.stores.fails = true;
      await s.checkout.refreshStoreState();
      expect(s.checkout.storeClosed, isFalse);
    });
  });

  group('what can be submitted', () {
    test('an empty cart cannot', () async {
      final s = _setup();
      s.cart.clear();
      expect(s.checkout.canSubmit, isFalse);
      expect(await s.checkout.submit(), isNull);
      expect(s.orders.created, isEmpty);
    });

    test('a cart with a flagged line cannot, until it is reviewed', () async {
      final s = _setup();
      s.cart.syncWithCatalog(10, [
        fakeCustomerProduct(id: 1, isOrderable: false),
        _milk,
      ]);
      expect(s.checkout.canSubmit, isFalse);
      expect(await s.checkout.submit(), isNull);
      expect(s.orders.created, isEmpty);
      s.cart.remove(1);
      expect(s.checkout.canSubmit, isTrue);
    });

    test(
      'a stale slot with nothing in flight is replaced instead of sent',
      () async {
        var now = _now;
        final s = _setup(now: () => now);
        final stale = s.checkout.selectedSlot!;
        now = stale.subtract(const Duration(minutes: 10));

        expect(await s.checkout.submit(), isNull);

        expect(s.orders.created, isEmpty);
        expect(s.checkout.failure?.kind, CheckoutFailureKind.invalidPickupTime);
        expect(s.checkout.selectedSlot, isNot(stale));
      },
    );
  });
}
