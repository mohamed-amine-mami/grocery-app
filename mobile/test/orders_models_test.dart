import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/ui/core/utils/date_formatters.dart';
import 'package:grocery_mobile/ui/features/orders/order_labels.dart';

/// What `GET /owner/orders/:id` returns (the backend's PostgreSQL-style
/// timestamps included).
Map<String, dynamic> _json({
  String status = 'CONFIRMED',
  List<Map<String, dynamic>>? items,
}) => {
  'id': 7,
  'code': 'K7M2QX',
  'status': status,
  'requestedPickupAt': '2026-10-05 16:30:00+00',
  'totalMillimes': 900,
  'storeAdjusted': true,
  'items':
      items ??
      [
        {
          'id': 41,
          'storeProductId': 12,
          'productName': 'Tomate',
          'saleUnit': 'KG',
          'quantity': 500,
          'unitPriceMillimes': 1800,
          'lineTotalMillimes': 900,
          'removedAt': null,
        },
        {
          'id': 42,
          'storeProductId': 13,
          'productName': 'Œufs',
          'saleUnit': 'PIECE',
          'quantity': 6,
          'unitPriceMillimes': 350,
          'lineTotalMillimes': 2100,
          'removedAt': '2026-10-04 14:50:11.5+00',
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
    {
      'fromStatus': 'PENDING',
      'toStatus': 'CONFIRMED',
      'actorType': 'OWNER',
      'reason': null,
      'createdAt': '2026-10-04 14:50:11.5+00',
    },
  ],
  'createdAt': '2026-10-04 14:48:02.454645+00',
  'updatedAt': '2026-10-04 14:50:11.5+00',
  'customer': {'name': 'Sana Ben Ali', 'phoneNumber': '+21698765432'},
};

void main() {
  group('Order.fromJson', () {
    test('parses the owner order, its lines, its history and the customer', () {
      final order = Order.fromJson(_json());

      expect(order.id, 7);
      expect(order.code, 'K7M2QX');
      expect(order.status, OrderStatus.confirmed);
      expect(order.totalMillimes, 900);
      expect(order.storeAdjusted, isTrue);
      expect(order.customerName, 'Sana Ben Ali');
      expect(order.customerPhone, '+21698765432');
      expect(order.items, hasLength(2));
      expect(order.items.first.saleUnit, SaleUnit.kg);
      expect(order.items.first.quantity, 500);
      expect(order.events.map((e) => e.toStatus), [
        OrderStatus.pending,
        OrderStatus.confirmed,
      ]);
      expect(order.events.first.fromStatus, isNull);
      expect(order.events.first.actorType, OrderActorType.client);
      expect(order.events.last.actorType, OrderActorType.owner);
    });

    test('splits kept and removed lines', () {
      final order = Order.fromJson(_json());
      expect(order.activeItems.map((i) => i.productName), ['Tomate']);
      expect(order.removedItems.map((i) => i.productName), ['Œufs']);
      // The removed line keeps its historical values.
      expect(order.removedItems.single.lineTotalMillimes, 2100);
      expect(order.removedItems.single.isRemoved, isTrue);
    });

    test('reads every status the backend has, and nothing else', () {
      for (final status in OrderStatus.values) {
        expect(OrderStatus.fromJson(status.apiValue), status);
      }
      expect(
        OrderStatus.values.map((s) => s.apiValue),
        containsAll([
          'PENDING',
          'CONFIRMED',
          'READY_FOR_PICKUP',
          'COMPLETED',
          'CANCELLED',
          'NO_SHOW',
        ]),
      );
      expect(OrderStatus.values, hasLength(6));
      expect(() => OrderStatus.fromJson('PREPARING'), throwsFormatException);
    });
  });

  group('timestamps', () {
    test('parses the backend’s PostgreSQL-style text into instants', () {
      final micro = parseApiTimestamp('2026-10-04 14:48:02.454645+00');
      expect(micro.isUtc, isTrue);
      expect(micro, DateTime.utc(2026, 10, 4, 14, 48, 2, 454, 645));
      expect(
        parseApiTimestamp('2026-10-04 14:50:11.5+00'),
        DateTime.utc(2026, 10, 4, 14, 50, 11, 500),
      );
      expect(
        parseApiTimestamp('2026-10-04 16:30:00+00'),
        DateTime.utc(2026, 10, 4, 16, 30),
      );
      // Other offsets are honored, ISO is accepted too.
      expect(
        parseApiTimestamp('2026-10-04 17:30:00+01'),
        DateTime.utc(2026, 10, 4, 16, 30),
      );
      expect(
        parseApiTimestamp('2026-10-04T16:30:00.000Z'),
        DateTime.utc(2026, 10, 4, 16, 30),
      );
    });

    test('orders are compared as instants, not as text', () {
      // As strings "…14:50:11.5+00" > "…14:50:11.454645+00" is false-ish and
      // precision differs; as instants the later one is later.
      final a = parseApiTimestamp('2026-10-04 14:50:11.454645+00');
      final b = parseApiTimestamp('2026-10-04 14:50:11.5+00');
      expect(b.isAfter(a), isTrue);
    });

    test('rejects text that is not a timestamp', () {
      expect(() => parseApiTimestamp('demain'), throwsFormatException);
    });
  });

  group('DateFormatFr', () {
    final now = DateTime(2026, 10, 4, 10, 0);

    test('shows pickup times that are quick to scan', () {
      expect(
        DateFormatFr.pickup(DateTime(2026, 10, 4, 16, 30), now: now),
        'Aujourd’hui · 16:30',
      );
      expect(
        DateFormatFr.pickup(DateTime(2026, 10, 5, 9, 5), now: now),
        'Demain · 09:05',
      );
      expect(
        DateFormatFr.pickup(DateTime(2026, 10, 10, 18, 0), now: now),
        'sam. 10 oct. · 18:00',
      );
    });

    test('formats dates and times in French, in local time', () {
      final local = DateTime(2026, 10, 4, 14, 48);
      expect(DateFormatFr.time(local), '14:48');
      expect(DateFormatFr.date(local), '4 oct. 2026');
      expect(DateFormatFr.dateTime(local), '4 oct. 2026 à 14:48');
      // A UTC instant is shown in the device's zone.
      final utc = DateTime.utc(2026, 10, 4, 14, 48);
      expect(DateFormatFr.time(utc), DateFormatFr.time(utc.toLocal()));
    });
  });

  group('French labels', () {
    test('filters use the agreed words', () {
      expect(OrderLabels.filter(null), 'Toutes');
      expect(OrderLabels.filter(OrderStatus.pending), 'En attente');
      expect(OrderLabels.filter(OrderStatus.confirmed), 'Confirmée');
      expect(OrderLabels.filter(OrderStatus.readyForPickup), 'Prête');
      expect(OrderLabels.filter(OrderStatus.completed), 'Terminée');
      expect(OrderLabels.filter(OrderStatus.cancelled), 'Annulée');
      expect(OrderLabels.filter(OrderStatus.noShow), 'Non récupérée');
    });

    test('a ready order reads unambiguously', () {
      expect(OrderLabels.status(OrderStatus.readyForPickup), 'Prête à retirer');
    });
  });
}
