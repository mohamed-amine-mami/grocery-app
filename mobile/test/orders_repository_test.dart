import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/repositories/orders_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/orders/order_errors.dart';

import 'api_test_support.dart';

Map<String, dynamic> _order({String status = 'PENDING'}) => {
  'id': 7,
  'code': 'K7M2QX',
  'status': status,
  'requestedPickupAt': '2026-10-05 16:30:00+00',
  'totalMillimes': 900,
  'storeAdjusted': false,
  'items': <Map<String, dynamic>>[],
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
  'customer': {'name': 'Sana', 'phoneNumber': '+21698765432'},
};

Map<String, dynamic> _page(int total, {int page = 1, int limit = 20}) => {
  'items': [_order()],
  'page': page,
  'limit': limit,
  'total': total,
};

Map<String, dynamic> _transition(String status, {bool changed = true}) => {
  'changed': changed,
  'order': _order(status: status),
};

void main() {
  group('list', () {
    test('asks for the first page with the default size', () async {
      final api = MockedApi.json(_page(1));
      final page = await OrdersRepository(api.client).list();

      expect(api.single.method, 'GET');
      expect(api.single.pathAndQuery, '/owner/orders?page=1&limit=20');
      expect(api.single.headers['Authorization'], 'Bearer owner-token');
      expect(page.orders, hasLength(1));
      expect(page.total, 1);
    });

    test('sends the status filter with the API’s own value', () async {
      for (final status in OrderStatus.values) {
        final api = MockedApi.json(_page(1));
        await OrdersRepository(api.client).list(status: status);
        expect(
          api.single.pathAndQuery,
          '/owner/orders?page=1&limit=20&status=${status.apiValue}',
        );
      }
    });

    test('sends page and limit', () async {
      final api = MockedApi.json(_page(45, page: 3, limit: 10));
      final page = await OrdersRepository(api.client).list(page: 3, limit: 10);
      expect(api.single.pathAndQuery, '/owner/orders?page=3&limit=10');
      expect(page.page, 3);
      expect(page.limit, 10);
    });

    test('the backend’s maximum page size is known', () {
      expect(OrdersRepository.maxPageSize, 50);
    });
  });

  group('get', () {
    test('reads one order', () async {
      final api = MockedApi.json(_order(status: 'CONFIRMED'));
      final order = await OrdersRepository(api.client).get(7);
      expect(api.single.pathAndQuery, '/owner/orders/7');
      expect(order.status, OrderStatus.confirmed);
    });
  });

  group('transitions', () {
    test('confirm without removals sends an empty body', () async {
      final api = MockedApi.json(_transition('CONFIRMED'));
      final result = await OrdersRepository(api.client).confirm(7);
      expect(api.single.method, 'POST');
      expect(api.single.path, '/owner/orders/7/confirm');
      expect(api.single.body, <String, dynamic>{});
      expect(result.changed, isTrue);
      expect(result.order.status, OrderStatus.confirmed);
    });

    test('confirm sends only the ids of the lines to remove', () async {
      final api = MockedApi.json(_transition('CONFIRMED'));
      await OrdersRepository(api.client).confirm(7, removeItemIds: [41, 42]);
      expect(api.single.body, {
        'removeItemIds': [41, 42],
      });
    });

    test('ready, complete and no-show are bare POSTs', () async {
      final cases = {
        'ready': ('READY_FOR_PICKUP', (OrdersRepository r) => r.markReady(7)),
        'complete': ('COMPLETED', (OrdersRepository r) => r.complete(7)),
        'no-show': ('NO_SHOW', (OrdersRepository r) => r.markNoShow(7)),
      };
      for (final entry in cases.entries) {
        final api = MockedApi.json(_transition(entry.value.$1));
        await entry.value.$2(OrdersRepository(api.client));
        expect(api.single.method, 'POST');
        expect(api.single.path, '/owner/orders/7/${entry.key}');
        expect(api.single.body, <String, dynamic>{});
      }
    });

    test('cancel sends the reason', () async {
      final api = MockedApi.json(_transition('CANCELLED'));
      await OrdersRepository(api.client).cancel(7, reason: 'Produit épuisé');
      expect(api.single.path, '/owner/orders/7/cancel');
      expect(api.single.body, {'reason': 'Produit épuisé'});
    });

    test('a repeated request answers changed: false', () async {
      final api = MockedApi.json(_transition('CONFIRMED', changed: false));
      final result = await OrdersRepository(api.client).confirm(7);
      expect(result.changed, isFalse);
    });
  });

  group('errors', () {
    test('ORDER_STATE_CHANGED reaches the caller with its code', () async {
      final api = MockedApi.json({
        'statusCode': 409,
        'code': 'ORDER_STATE_CHANGED',
        'message': 'Order is CANCELLED; it cannot move to CONFIRMED',
        'currentStatus': 'CANCELLED',
        'requestedStatus': 'CONFIRMED',
      }, status: 409);
      await expectLater(
        OrdersRepository(api.client).confirm(7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.code, 'code', 'ORDER_STATE_CHANGED')
              .having((e) => e.body?['currentStatus'], 'current', 'CANCELLED'),
        ),
      );
    });

    test('an unreachable backend is a NetworkException', () async {
      final api = MockedApi.offline();
      await expectLater(
        OrdersRepository(api.client).list(),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('French failure messages', () {
    OrderFailure failure(int status, {String? code}) => OrderFailure.from(
      ApiException(statusCode: status, code: code, message: 'English text'),
    );

    test('ORDER_STATE_CHANGED asks to refresh', () {
      final f = failure(409, code: 'ORDER_STATE_CHANGED');
      expect(f.kind, OrderFailureKind.stateChanged);
      expect(
        f.message,
        'La commande a changé d’état. Actualisez les informations.',
      );
    });

    test('STOCK_CHANGED asks to review the order again', () {
      final f = failure(409, code: 'STOCK_CHANGED');
      expect(f.kind, OrderFailureKind.stockChanged);
      expect(f.message, contains('stock a changé'));
    });

    test(
      'network, session, access and missing order each have their words',
      () {
        expect(
          OrderFailure.from(const NetworkException('x')).message,
          'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
        );
        expect(failure(401).kind, OrderFailureKind.sessionExpired);
        expect(failure(403).kind, OrderFailureKind.forbidden);
        expect(failure(404).kind, OrderFailureKind.notFound);
        expect(failure(404).message, 'Cette commande n’est plus disponible.');
        expect(failure(400).kind, OrderFailureKind.invalid);
      },
    );

    test('unknown errors never show raw server text', () {
      for (final f in [
        failure(500),
        failure(502),
        failure(409, code: 'SOMETHING_NEW'),
        OrderFailure.from(StateError('boom')),
      ]) {
        expect(f.kind, OrderFailureKind.unknown);
        expect(f.message, 'Une erreur est survenue. Veuillez réessayer.');
      }
      for (final f in [failure(400), failure(500), failure(409)]) {
        expect(f.message, isNot(contains('English text')));
      }
    });
  });
}
