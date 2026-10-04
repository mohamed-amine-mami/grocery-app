import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/repositories/store_products_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';

import 'api_test_support.dart';

Map<String, dynamic> _storeProduct({
  int id = 7,
  bool trackStock = true,
  int? stockQuantity = 20000,
  bool isAvailable = true,
  String? reason,
  String? archivedAt,
  int priceMillimes = 4500,
}) => {
  'id': id,
  'productId': 12,
  'saleUnit': 'KG',
  'priceMillimes': priceMillimes,
  'minQuantity': 100,
  'quantityStep': 100,
  'maxQuantity': 10000,
  'trackStock': trackStock,
  'stockQuantity': stockQuantity,
  'isAvailable': isAvailable,
  'isOrderable': reason == null,
  'unavailabilityReason': reason,
  'archivedAt': archivedAt,
  'createdAt': '2026-10-03 10:00:00+00',
  'updatedAt': '2026-10-03 10:00:00+00',
  'product': {
    'id': 12,
    'slug': 'banane',
    'name': 'Banane',
    'description': null,
    'photo': null,
    'defaultSaleUnit': 'KG',
    'allowedSaleUnits': ['KG', 'PIECE'],
    'defaultMinQuantity': 100,
    'defaultQuantityStep': 100,
    'defaultMaxQuantity': 10000,
    'isActive': true,
  },
  'category': {'id': 2, 'slug': 'fruits', 'name': 'Fruits', 'isActive': true},
};

StoreProductsRepository _repository(MockedApi api) =>
    StoreProductsRepository(api.client);

void main() {
  group('list', () {
    test('GETs the active store products by default', () async {
      final api = MockedApi.json([_storeProduct(), _storeProduct(id: 8)]);

      final products = await _repository(api).list();

      expect(api.single.method, 'GET');
      expect(api.single.pathAndQuery, '/owner/store-products?status=active');
      expect(api.single.headers['Authorization'], 'Bearer owner-token');
      expect(products.map((p) => p.id), [7, 8]);
      expect(products.first.product.slug, 'banane');
    });

    test('listActive is the default listing', () async {
      final api = MockedApi.json([]);

      await _repository(api).listActive();

      expect(api.single.pathAndQuery, '/owner/store-products?status=active');
    });

    test(
      'asks for archived or all offerings, optionally in one category',
      () async {
        final api = MockedApi.json([]);
        final repository = _repository(api);

        await repository.list(status: StoreProductStatus.archived);
        await repository.list(status: StoreProductStatus.all, categoryId: 3);

        expect(api.requests.map((r) => r.pathAndQuery), [
          '/owner/store-products?status=archived',
          '/owner/store-products?status=all&categoryId=3',
        ]);
      },
    );
  });

  group('get', () {
    test('GETs one offering and parses its stock', () async {
      final api = MockedApi.json(_storeProduct(stockQuantity: 7500));

      final product = await _repository(api).get(7);

      expect(api.single.pathAndQuery, '/owner/store-products/7');
      expect(product.stockQuantity, 7500);
      expect(product.trackStock, isTrue);
    });

    test('an offering of another store is a 404', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 404,
          'message': 'Store product 7 not found',
        }, 404),
      );

      await expectLater(
        _repository(api).get(7),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('create', () {
    test(
      'POSTs only the product and price, and parses the created offering',
      () async {
        final api = MockedApi.json(_storeProduct(), status: 201);

        final created = await _repository(api)
            .create(const NewStoreProduct(productId: 12, priceMillimes: 4500));

        expect(api.single.method, 'POST');
        expect(api.single.path, '/owner/store-products');
        expect(api.single.body, {'productId': 12, 'priceMillimes': 4500});
        expect(created.id, 7);
        expect(created.priceMillimes, 4500);
      },
    );

    test('sends the unit, rules and stock configuration when given', () async {
      final api = MockedApi.json(_storeProduct(), status: 201);

      await _repository(api).create(
        const NewStoreProduct(
          productId: 12,
          priceMillimes: 4500,
          saleUnit: SaleUnit.kg,
          minQuantity: 250,
          quantityStep: 250,
          noMaximum: true,
          trackStock: true,
          stockQuantity: 20000,
        ),
      );

      expect(api.single.body, {
        'productId': 12,
        'priceMillimes': 4500,
        'saleUnit': 'KG',
        'minQuantity': 250,
        'quantityStep': 250,
        'maxQuantity': null,
        'trackStock': true,
        'stockQuantity': 20000,
      });
    });

    test('a duplicate is a 409 with the backend message', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 409,
          'message': 'Your store already sells this product',
          'error': 'Conflict',
        }, 409),
      );

      await expectLater(
        _repository(api)
            .create(const NewStoreProduct(productId: 12, priceMillimes: 4500)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('already sells')),
        ),
      );
    });

    test('a validation failure surfaces the first message', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 400,
          'message': [
            'saleUnit must be one of KG, PIECE for this product',
            'other',
          ],
          'error': 'Bad Request',
        }, 400),
      );

      await expectLater(
        _repository(api).create(
          const NewStoreProduct(
            productId: 12,
            priceMillimes: 4500,
            saleUnit: SaleUnit.l,
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having(
                (e) => e.message,
                'message',
                'saleUnit must be one of KG, PIECE for this product',
              ),
        ),
      );
    });
  });

  group('update', () {
    test('PATCHes only what changed', () async {
      final api = MockedApi.json(_storeProduct(priceMillimes: 4700));

      final updated = await _repository(api)
          .update(7, const StoreProductUpdate(priceMillimes: 4700));

      expect(api.single.method, 'PATCH');
      expect(api.single.path, '/owner/store-products/7');
      expect(api.single.body, {'priceMillimes': 4700});
      expect(updated.priceMillimes, 4700);
    });

    test('a stock count carries the stock it expects, null included', () async {
      final api = MockedApi.json(_storeProduct(stockQuantity: 20000));

      await _repository(api).update(
        7,
        const StoreProductUpdate(
          stock: StockChange(
            trackStock: true,
            stockQuantity: 20000,
            expectedStockQuantity: null,
          ),
        ),
      );

      expect(api.single.body, {
        'trackStock': true,
        'stockQuantity': 20000,
        'expectedStockQuantity': null,
      });
    });

    test(
      'a count that reaches zero comes back unorderable, switch untouched',
      () async {
        final api = MockedApi.json(
          _storeProduct(stockQuantity: 0, reason: 'OUT_OF_STOCK'),
        );

        final updated = await _repository(api).update(
          7,
          const StoreProductUpdate(
            stock: StockChange(stockQuantity: 0, expectedStockQuantity: 500),
          ),
        );

        expect(updated.stockQuantity, 0);
        expect(updated.isAvailable, isTrue);
        expect(updated.isOrderable, isFalse);
        expect(updated.unavailabilityReason, UnavailabilityReason.outOfStock);
      },
    );

    group('when the stock changed since it was loaded', () {
      test('throws StockChangedException carrying the current stock', () async {
        final api = MockedApi(
          (_) => jsonResponse({
            'statusCode': 409,
            'error': 'Conflict',
            'code': 'STOCK_CHANGED',
            'message': 'Stock changed since it was loaded',
            'currentStockQuantity': 17500,
          }, 409),
        );

        await expectLater(
          _repository(api).update(
            7,
            const StoreProductUpdate(
              stock: StockChange(
                stockQuantity: 25000,
                expectedStockQuantity: 20000,
              ),
            ),
          ),
          throwsA(
            isA<StockChangedException>().having(
              (e) => e.currentStockQuantity,
              'currentStockQuantity',
              17500,
            ),
          ),
        );
      });

      test(
        'the current stock is null when tracking was switched off meanwhile',
        () async {
          final api = MockedApi(
            (_) => jsonResponse({
              'statusCode': 409,
              'error': 'Conflict',
              'code': 'STOCK_CHANGED',
              'message': 'Stock changed since it was loaded',
              'currentStockQuantity': null,
            }, 409),
          );

          await expectLater(
            _repository(api).update(
              7,
              const StoreProductUpdate(
                stock: StockChange(
                  stockQuantity: 100,
                  expectedStockQuantity: 20000,
                ),
              ),
            ),
            throwsA(
              isA<StockChangedException>().having(
                (e) => e.currentStockQuantity,
                'currentStockQuantity',
                isNull,
              ),
            ),
          );
        },
      );
    });

    test(
      'any other 409 (an archived offering) stays an ApiException',
      () async {
        final api = MockedApi(
          (_) => jsonResponse({
            'statusCode': 409,
            'message': 'Archived products cannot be modified',
            'error': 'Conflict',
          }, 409),
        );

        await expectLater(
          _repository(api)
              .update(7, const StoreProductUpdate(priceMillimes: 1)),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having((e) => e.code, 'code', isNull)
                .having((e) => e.message, 'message', contains('Archived')),
          ),
        );
      },
    );

    test('a missing expectedStockQuantity (400) is an ApiException, not a stock conflict', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 400,
          'message': 'expectedStockQuantity is required when changing trackStock or stockQuantity',
          'error': 'Bad Request',
        }, 400),
      );

      await expectLater(
        _repository(api).update(
          7,
          const StoreProductUpdate(
            stock: StockChange(stockQuantity: 5, expectedStockQuantity: 1),
          ),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });

  group('setAvailability', () {
    test('PATCHes the owner switch only', () async {
      final api = MockedApi.json(
        _storeProduct(isAvailable: false, reason: 'OWNER_DISABLED'),
      );

      final product = await _repository(api)
          .setAvailability(7, isAvailable: false);

      expect(api.single.method, 'PATCH');
      expect(api.single.path, '/owner/store-products/7/availability');
      expect(api.single.body, {'isAvailable': false});
      expect(product.isAvailable, isFalse);
      expect(product.unavailabilityReason, UnavailabilityReason.ownerDisabled);
    });
  });

  group('archive and restore', () {
    test('archive DELETEs, and a 204 with no body completes', () async {
      final api = MockedApi((_) => jsonResponse(null, 204));

      await _repository(api).archive(7);

      expect(api.single.method, 'DELETE');
      expect(api.single.path, '/owner/store-products/7');
    });

    test(
      'restore POSTs to the explicit endpoint and parses the offering',
      () async {
        final api = MockedApi.json(_storeProduct());

        final restored = await _repository(api).restore(7);

        expect(api.single.method, 'POST');
        expect(api.single.path, '/owner/store-products/7/restore');
        expect(restored.isArchived, isFalse);
      },
    );

    test('an archived offering parses as archived', () async {
      final api = MockedApi.json(
        _storeProduct(archivedAt: '2026-10-03 12:00:00+00', reason: 'ARCHIVED'),
      );

      final product = await _repository(api).get(7);

      expect(product.isArchived, isTrue);
      expect(product.unavailabilityReason, UnavailabilityReason.archived);
    });
  });

  group('error handling', () {
    test(
      'an unreachable backend is a NetworkException on every call',
      () async {
        final api = MockedApi.offline();
        final repository = _repository(api);

        await expectLater(repository.list(), throwsA(isA<NetworkException>()));
        await expectLater(repository.get(1), throwsA(isA<NetworkException>()));
        await expectLater(
          repository.create(
            const NewStoreProduct(productId: 1, priceMillimes: 1),
          ),
          throwsA(isA<NetworkException>()),
        );
        await expectLater(
          repository.update(1, const StoreProductUpdate(priceMillimes: 1)),
          throwsA(isA<NetworkException>()),
        );
        await expectLater(
          repository.archive(1),
          throwsA(isA<NetworkException>()),
        );
      },
    );

    test('an owner without a store is a 404 on the list', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 404,
          'message': 'No store found for this owner',
        }, 404),
      );

      await expectLater(
        _repository(api).list(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('ApiException keeps the code and the whole body', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 409,
          'code': 'STOCK_CHANGED',
          'message': 'Stock changed since it was loaded',
          'currentStockQuantity': 5,
        }, 409),
      );

      try {
        await api.client.patch('/owner/store-products/1', body: {});
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.code, 'STOCK_CHANGED');
        expect(error.body?['currentStockQuantity'], 5);
      }
    });
  });
}
