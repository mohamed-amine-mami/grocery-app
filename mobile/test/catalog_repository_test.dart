import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/repositories/catalog_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';

import 'api_test_support.dart';

const _categories = [
  {
    'id': 2,
    'slug': 'fruits',
    'name': 'Fruits',
    'description': null,
    'photo': null,
    'productCount': 2,
  },
  {
    'id': 3,
    'slug': 'produits-laitiers',
    'name': 'Produits laitiers',
    'description': 'Frais',
    'photo': 'https://x.test/l.jpg',
    'productCount': 0,
  },
];

Map<String, dynamic> _item(
  int id,
  String slug,
  String name, {
  bool inMyStore = false,
}) => {
  'id': id,
  'slug': slug,
  'name': name,
  'description': null,
  'photo': null,
  'defaultSaleUnit': 'KG',
  'allowedSaleUnits': ['KG', 'PIECE'],
  'defaultMinQuantity': 100,
  'defaultQuantityStep': 100,
  'defaultMaxQuantity': 10000,
  'category': {'id': 2, 'slug': 'fruits', 'name': 'Fruits'},
  'inMyStore': inMyStore,
  'storeProductId': inMyStore ? 40 + id : null,
  'storeProductArchived': false,
};

void main() {
  group('CatalogRepository.categories', () {
    test(
      'GETs the global categories with the owner token and parses them',
      () async {
        final api = MockedApi.json(_categories);

        final categories = await CatalogRepository(api.client).categories();

        expect(api.single.method, 'GET');
        expect(api.single.path, '/owner/catalog/categories');
        expect(api.single.headers['Authorization'], 'Bearer owner-token');
        expect(categories.map((c) => c.slug), ['fruits', 'produits-laitiers']);
        expect(categories[0].productCount, 2);
        expect(categories[1].description, 'Frais');
      },
    );

    test('an empty catalog is an empty list', () async {
      final categories = await CatalogRepository(MockedApi.json([]).client)
          .categories();

      expect(categories, isEmpty);
    });
  });

  group('CatalogRepository.products', () {
    test('GETs the whole catalog, flagged with what the store sells', () async {
      final api = MockedApi.json([
        _item(12, 'banane', 'Banane', inMyStore: true),
        _item(13, 'pomme', 'Pomme'),
      ]);

      final items = await CatalogRepository(api.client).products();

      expect(api.single.method, 'GET');
      expect(api.single.pathAndQuery, '/owner/catalog/products');
      expect(items.map((i) => i.product.slug), ['banane', 'pomme']);
      expect(items[0].inMyStore, isTrue);
      expect(items[0].storeProductId, 52);
      expect(items[1].inMyStore, isFalse);
      expect(items[0].product.defaultSaleUnit, SaleUnit.kg);
    });

    test('filters by category on the server', () async {
      final api = MockedApi.json([_item(12, 'banane', 'Banane')]);

      await CatalogRepository(api.client).products(categoryId: 2);

      expect(api.single.pathAndQuery, '/owner/catalog/products?categoryId=2');
    });
  });

  group('the catalog is read-only', () {
    test('the repository only ever issues GET requests', () async {
      final api = MockedApi.json([]);
      final repository = CatalogRepository(api.client);

      await repository.categories();
      await repository.products();
      await repository.products(categoryId: 2);

      expect(api.requests.map((r) => r.method).toSet(), {'GET'});
      expect(api.requests.every((r) => r.body == null), isTrue);
    });
  });

  group('error handling', () {
    test(
      'a missing store is an ApiException the caller can recognise',
      () async {
        final api = MockedApi(
          (_) => jsonResponse({
            'statusCode': 404,
            'message': 'No store found for this owner',
            'error': 'Not Found',
          }, 404),
        );

        await expectLater(
          CatalogRepository(api.client).products(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 404)
                .having(
                  (e) => e.message,
                  'message',
                  'No store found for this owner',
                ),
          ),
        );
      },
    );

    test('an expired token is a 401', () async {
      final api = MockedApi(
        (_) =>
            jsonResponse({'statusCode': 401, 'message': 'Unauthorized'}, 401),
      );

      await expectLater(
        CatalogRepository(api.client).categories(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('a non-owner is a 403', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 403,
          'message': 'Forbidden resource',
        }, 403),
      );

      await expectLater(
        CatalogRepository(api.client).categories(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('an unreachable backend is a NetworkException', () async {
      final api = MockedApi.offline();

      await expectLater(
        CatalogRepository(api.client).products(),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
