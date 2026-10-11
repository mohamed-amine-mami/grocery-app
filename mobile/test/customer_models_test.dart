import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/brand.dart';
import 'package:grocery_mobile/data/models/customer_order.dart';
import 'package:grocery_mobile/data/models/customer_product.dart';
import 'package:grocery_mobile/data/models/customer_store.dart';
import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/ui/core/utils/idempotency_key.dart';
import 'package:grocery_mobile/ui/core/utils/pickup_slots.dart';

void main() {
  group('CustomerStore', () {
    test('parses the customer-safe store', () {
      final store = CustomerStore.fromJson({
        'id': 3,
        'name': 'Menzah Market',
        'description': null,
        'photo': null,
        'address': '12 Rue de la Liberté',
        'latitude': 36.8,
        'longitude': 10.1,
        'isOpen': false,
      });
      expect(store.name, 'Menzah Market');
      expect(store.address, '12 Rue de la Liberté');
      expect(store.isOpen, isFalse);
    });
  });

  group('CustomerProduct', () {
    test('parses the store’s own price, unit and rules, and the verdict', () {
      final product = CustomerProduct.fromJson({
        'id': 12,
        'name': 'Banane',
        'description': null,
        'photo': null,
        'category': {'id': 1, 'name': 'Fruits'},
        'saleUnit': 'KG',
        'priceMillimes': 1800,
        'minQuantity': 500,
        'quantityStep': 100,
        'maxQuantity': 5000,
        'isOrderable': false,
        'unavailabilityReason': 'OUT_OF_STOCK',
      });
      expect(product.id, 12);
      expect(product.category.name, 'Fruits');
      expect(product.saleUnit, SaleUnit.kg);
      expect(product.priceMillimes, 1800);
      expect(product.minQuantity, 500);
      expect(product.quantityStep, 100);
      expect(product.maxQuantity, 5000);
      expect(product.isOrderable, isFalse);
      expect(product.unavailabilityReason, UnavailabilityReason.outOfStock);
    });

    test('has no stock field at all', () {
      // The type itself carries nothing to display or infer stock from.
      final fields = [
        'stockQuantity',
        'stockDecrementedQuantity',
        'trackStock',
      ];
      final source = CustomerProduct.fromJson({
        'id': 1,
        'name': 'x',
        'category': {'id': 1, 'name': 'c'},
        'saleUnit': 'PIECE',
        'priceMillimes': 100,
        'minQuantity': 1,
        'quantityStep': 1,
        'maxQuantity': null,
        'isOrderable': true,
        'unavailabilityReason': null,
      }).toString();
      for (final field in fields) {
        expect(source.contains(field), isFalse);
      }
    });
  });

  group('CustomerProduct brand', () {
    Map<String, dynamic> json([Map<String, dynamic>? extra]) => {
      'id': 12,
      'name': 'Ketchup',
      'description': null,
      'photo': 'https://res.example/f_auto,q_auto/v1/ketchup.jpg',
      'category': {'id': 1, 'name': 'Sauces'},
      'saleUnit': 'PIECE',
      'priceMillimes': 2500,
      'minQuantity': 1,
      'quantityStep': 1,
      'maxQuantity': null,
      'isOrderable': true,
      'unavailabilityReason': null,
      ...?extra,
    };

    test('parses a brand into a typed Brand', () {
      final product = CustomerProduct.fromJson(
        json({
          'brand': {'id': 4, 'slug': 'heinz', 'name': 'Heinz'},
        }),
      );
      expect(product.brand, isA<Brand>());
      expect(product.brand!.id, 4);
      expect(product.brand!.slug, 'heinz');
      expect(product.brand!.name, 'Heinz');
      // Everything else is as before.
      expect(product.name, 'Ketchup');
      expect(product.photo, 'https://res.example/f_auto,q_auto/v1/ketchup.jpg');
      expect(product.priceMillimes, 2500);
      expect(product.isOrderable, isTrue);
    });

    test('a product without a brand has none', () {
      expect(CustomerProduct.fromJson(json({'brand': null})).brand, isNull);
    });

    test('an absent brand key (an older backend) is no brand either', () {
      expect(CustomerProduct.fromJson(json()).brand, isNull);
    });

    test('a malformed brand is refused, like any other malformed field', () {
      expect(
        () => CustomerProduct.fromJson(json({'brand': 'Heinz'})),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => CustomerProduct.fromJson(
          json({
            'brand': {'id': 4, 'name': 'Heinz'},
          }),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('CustomerOrder', () {
    test(
      'parses the server’s order: code, status, snapshots, total, store',
      () {
        final order = CustomerOrder.fromJson({
          'id': 7,
          'code': 'K7M2QX',
          'status': 'READY_FOR_PICKUP',
          'requestedPickupAt': '2026-10-05 16:30:00+00',
          'totalMillimes': 3300,
          'storeAdjusted': false,
          'items': [
            {
              'id': 41,
              'storeProductId': 12,
              'productName': 'Banane',
              'saleUnit': 'KG',
              'quantity': 500,
              'unitPriceMillimes': 1800,
              'lineTotalMillimes': 900,
              'removedAt': null,
            },
          ],
          'events': [
            {
              'fromStatus': null,
              'toStatus': 'PENDING',
              'actorType': 'CLIENT',
              'reason': null,
              'createdAt': '2026-10-04 14:48:02.454645+00',
            },
          ],
          'createdAt': '2026-10-04 14:48:02.454645+00',
          'updatedAt': '2026-10-04 14:48:02.454645+00',
          'store': {'id': 3, 'name': 'Menzah Market', 'address': '12 Rue'},
        });
        expect(order.code, 'K7M2QX');
        expect(order.status, OrderStatus.readyForPickup);
        expect(order.totalMillimes, 3300);
        expect(order.storeName, 'Menzah Market');
        expect(order.items.single.unitPriceMillimes, 1800);
        expect(order.requestedPickupAt, DateTime.utc(2026, 10, 5, 16, 30));
        expect(order.canCancel, isFalse);
        expect(order.isFinished, isFalse);
      },
    );

    test('cancellation is offered for pending and confirmed orders only', () {
      for (final status in OrderStatus.values) {
        final canCancel =
            status == OrderStatus.pending || status == OrderStatus.confirmed;
        expect(_order(status).canCancel, canCancel, reason: status.apiValue);
      }
    });
  });

  group('NewOrderRequest', () {
    test(
      'carries the store, ids, quantities, pickup time and key — nothing else',
      () {
        final request = NewOrderRequest(
          storeId: 3,
          lines: const [
            NewOrderLine(storeProductId: 12, quantity: 500),
            NewOrderLine(storeProductId: 14, quantity: 2),
          ],
          requestedPickupAt: DateTime.utc(2026, 10, 5, 16, 30),
          idempotencyKey: 'key-1',
        );
        expect(request.toJson(), {
          'storeId': 3,
          'lines': [
            {'storeProductId': 12, 'quantity': 500},
            {'storeProductId': 14, 'quantity': 2},
          ],
          'requestedPickupAt': '2026-10-05T16:30:00.000Z',
          'idempotencyKey': 'key-1',
        });
      },
    );
  });

  group('PickupSlots', () {
    final now = DateTime(2026, 10, 4, 10, 10);

    test('are every 30 minutes, on the hour and the half hour', () {
      final slots = PickupSlots.generate(now);
      expect(slots, isNotEmpty);
      for (final slot in slots) {
        expect(slot.minute % 30, 0);
        expect(slot.second, 0);
      }
      for (var i = 1; i < slots.length; i++) {
        expect(slots[i].difference(slots[i - 1]), const Duration(minutes: 30));
      }
    });

    test('start at least 30 minutes from now', () {
      final slots = PickupSlots.generate(now);
      expect(
        slots.first.difference(now),
        greaterThanOrEqualTo(const Duration(minutes: 30)),
      );
      // 10:10 + 30 min (+ margin) → the next half hour is 11:00.
      expect(slots.first, DateTime(2026, 10, 4, 11));
    });

    test('a slot exactly on the minimum is pushed back by the margin', () {
      final onTheHour = DateTime(2026, 10, 4, 10, 0);
      final slots = PickupSlots.generate(onTheHour);
      expect(
        slots.first,
        DateTime(2026, 10, 4, 10, 30).add(const Duration(minutes: 30)),
      );
      expect(
        slots.first.difference(onTheHour),
        greaterThan(const Duration(minutes: 30)),
      );
    });

    test('end at most 48 hours from now', () {
      final slots = PickupSlots.generate(now);
      expect(
        slots.last.difference(now),
        lessThanOrEqualTo(const Duration(hours: 48)),
      );
      expect(
        now.add(const Duration(hours: 48)).difference(slots.last),
        lessThan(const Duration(minutes: 60)),
      );
      expect(slots.length, greaterThan(90));
    });

    test('a slot goes stale once it is less than 30 minutes away', () {
      final slot = DateTime(2026, 10, 4, 11);
      expect(PickupSlots.isStillBookable(slot, now), isTrue);
      expect(
        PickupSlots.isStillBookable(slot, DateTime(2026, 10, 4, 10, 40)),
        isFalse,
      );
    });
  });

  group('idempotency key', () {
    test('is a random version-4 UUID, different every time', () {
      final keys = {for (var i = 0; i < 50; i++) generateIdempotencyKey()};
      expect(keys, hasLength(50));
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (final key in keys) {
        expect(uuid.hasMatch(key), isTrue, reason: key);
        expect(key.length, lessThanOrEqualTo(100)); // the backend's bound
      }
    });
  });
}

CustomerOrder _order(OrderStatus status) => CustomerOrder(
  id: 1,
  code: 'ABC123',
  status: status,
  requestedPickupAt: DateTime.utc(2026, 10, 5),
  totalMillimes: 1000,
  storeAdjusted: false,
  storeName: 'x',
  storeAddress: 'y',
  items: const [],
  events: const [],
  createdAt: DateTime.utc(2026, 10, 4),
  updatedAt: DateTime.utc(2026, 10, 4),
);
