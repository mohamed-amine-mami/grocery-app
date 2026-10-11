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

  group('CatalogRepository.browse', () {
    Map<String, dynamic> page({
      List<Map<String, dynamic>>? items,
      int total = 2,
      String? next,
    }) => {
      'items': items ?? [_item(12, 'banane', 'Banane', inMyStore: true)],
      'total': total,
      'nextCursor': next,
    };

    test('GETs the first page with no parameters', () async {
      final api = MockedApi.json(page(next: 'abc'));

      final result = await CatalogRepository(api.client).browse();

      expect(api.single.method, 'GET');
      expect(api.single.pathAndQuery, '/owner/catalog/browse');
      expect(api.single.headers['Authorization'], 'Bearer owner-token');
      expect(result.items.single.product.slug, 'banane');
      expect(result.items.single.inMyStore, isTrue);
      expect(result.total, 2);
      expect(result.nextCursor, 'abc');
    });

    test('sends the search, category, cursor and limit', () async {
      final api = MockedApi.json(page());

      await CatalogRepository(api.client).browse(
        query: '  œufs frais ',
        categoryId: 3,
        cursor: 'a-_b',
        limit: 40,
      );

      final uri = Uri.parse('http://x${api.single.pathAndQuery}');
      expect(uri.path, '/owner/catalog/browse');
      expect(uri.queryParameters, {
        'q': 'œufs frais',
        'categoryId': '3',
        'cursor': 'a-_b',
        'limit': '40',
      });
    });

    test('leaves out a blank search', () async {
      final api = MockedApi.json(page());

      await CatalogRepository(api.client).browse(query: '   ');

      expect(api.single.pathAndQuery, '/owner/catalog/browse');
    });

    test('the last page has no cursor', () async {
      final api = MockedApi.json(page(total: 1));

      final result = await CatalogRepository(api.client).browse();

      expect(result.nextCursor, isNull);
    });

    test('an empty result is an empty page', () async {
      final api = MockedApi.json(page(items: [], total: 0));

      final result = await CatalogRepository(api.client).browse(query: 'zzz');

      expect(result.items, isEmpty);
      expect(result.total, 0);
    });

    test('a bad cursor is a 400 the caller can recognise', () async {
      final api = MockedApi(
        (_) => jsonResponse({
          'statusCode': 400,
          'message': 'cursor is not valid',
        }, 400),
      );

      await expectLater(
        CatalogRepository(api.client).browse(cursor: 'x'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });

  group('CatalogRepository.product', () {
    test('GETs one product with the store flags', () async {
      final api = MockedApi.json(
        _item(12, 'banane', 'Banane', inMyStore: true),
      );

      final item = await CatalogRepository(api.client).product(12);

      expect(api.single.pathAndQuery, '/owner/catalog/products/12');
      expect(item!.product.slug, 'banane');
      expect(item.inMyStore, isTrue);
    });

    test('is null when the catalog no longer has it', () async {
      final api = MockedApi(
        (_) => jsonResponse({'statusCode': 404, 'message': 'gone'}, 404),
      );

      expect(await CatalogRepository(api.client).product(12), isNull);
    });

    test('any other failure is thrown', () async {
      final api = MockedApi(
        (_) => jsonResponse({'statusCode': 500, 'message': 'boom'}, 500),
      );

      await expectLater(
        CatalogRepository(api.client).product(12),
        throwsA(isA<ApiException>()),
      );
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

      final pages = MockedApi.json({
        'items': <Object?>[],
        'total': 0,
        'nextCursor': null,
      });
      await CatalogRepository(pages.client).browse(query: 'x', limit: 5);
      final one = MockedApi.json(_item(12, 'banane', 'Banane'));
      await CatalogRepository(one.client).product(12);
      expect(
        [...pages.requests, ...one.requests].map((r) => r.method).toSet(),
        {'GET'},
      );
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
