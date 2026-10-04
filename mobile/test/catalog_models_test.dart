import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/catalog_category.dart';
import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';

/// JSON exactly as the backend sends it (see the e2e specs).
Map<String, dynamic> _categoryJson({
  String? description,
  String? photo,
  int productCount = 3,
}) => {
  'id': 2,
  'slug': 'fruits',
  'name': 'Fruits',
  'description': description,
  'photo': photo,
  'productCount': productCount,
};

Map<String, dynamic> _catalogProductJson({
  String defaultSaleUnit = 'KG',
  List<String> allowed = const ['KG', 'PIECE'],
  int? max = 10000,
  bool? isActive,
}) => {
  'id': 12,
  'slug': 'banane',
  'name': 'Banane',
  'description': 'Jaune et sucrée',
  'photo': 'https://cdn.example.com/banane.jpg',
  'defaultSaleUnit': defaultSaleUnit,
  'allowedSaleUnits': allowed,
  'defaultMinQuantity': 100,
  'defaultQuantityStep': 100,
  'defaultMaxQuantity': max,
  'isActive': ?isActive,
  'category': {'id': 2, 'slug': 'fruits', 'name': 'Fruits'},
};

Map<String, dynamic> _storeProductJson({
  bool trackStock = true,
  int? stockQuantity = 20000,
  bool isAvailable = true,
  bool isOrderable = true,
  String? reason,
  String? archivedAt,
  int? max = 10000,
  bool productActive = true,
  bool categoryActive = true,
}) => {
  'id': 7,
  'productId': 12,
  'saleUnit': 'KG',
  'priceMillimes': 4500,
  'minQuantity': 100,
  'quantityStep': 100,
  'maxQuantity': max,
  'trackStock': trackStock,
  'stockQuantity': stockQuantity,
  'isAvailable': isAvailable,
  'isOrderable': isOrderable,
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
    'isActive': productActive,
  },
  'category': {
    'id': 2,
    'slug': 'fruits',
    'name': 'Fruits',
    'isActive': categoryActive,
  },
};

void main() {
  group('CatalogCategory', () {
    test('parses a global category', () {
      final category = CatalogCategory.fromJson(
        _categoryJson(description: 'De saison', photo: 'https://x.test/f.jpg'),
      );

      expect(category.id, 2);
      expect(category.slug, 'fruits');
      expect(category.name, 'Fruits');
      expect(category.description, 'De saison');
      expect(category.photo, 'https://x.test/f.jpg');
      expect(category.productCount, 3);
    });

    test('description and photo are optional', () {
      final category = CatalogCategory.fromJson(_categoryJson(productCount: 0));

      expect(category.description, isNull);
      expect(category.photo, isNull);
      expect(category.productCount, 0);
    });

    test('a category reference defaults to active and reads the flag', () {
      final base = {'id': 2, 'slug': 'fruits', 'name': 'Fruits'};

      expect(CategoryRef.fromJson(base).isActive, isTrue);
      expect(
        CategoryRef.fromJson({...base, 'isActive': false}).isActive,
        isFalse,
      );
    });
  });

  group('CatalogProduct (global)', () {
    test('parses identity, category, image, unit and default rules', () {
      final product = CatalogProduct.fromJson(_catalogProductJson());

      expect(product.id, 12);
      expect(product.slug, 'banane');
      expect(product.name, 'Banane');
      expect(product.description, 'Jaune et sucrée');
      expect(product.photo, 'https://cdn.example.com/banane.jpg');
      expect(product.category.slug, 'fruits');
      expect(product.category.name, 'Fruits');
      expect(product.defaultSaleUnit, SaleUnit.kg);
      expect(product.allowedSaleUnits, [SaleUnit.kg, SaleUnit.piece]);
      expect(product.defaultMinQuantity, 100);
      expect(product.defaultQuantityStep, 100);
      expect(product.defaultMaxQuantity, 10000);
      expect(product.isActive, isTrue);
    });

    test('a piece-counted product can only be sold in pieces', () {
      final product = CatalogProduct.fromJson(
        _catalogProductJson(
          defaultSaleUnit: 'PIECE',
          allowed: const ['PIECE'],
          max: null,
        ),
      );

      expect(product.allowedSaleUnits, [SaleUnit.piece]);
      expect(product.defaultMaxQuantity, isNull);
    });

    test('keeps the catalog state the backend reports', () {
      expect(
        CatalogProduct.fromJson(_catalogProductJson(isActive: false)).isActive,
        isFalse,
      );
    });

    test('an unknown unit is rejected, not guessed', () {
      expect(
        () => CatalogProduct.fromJson(
          _catalogProductJson(defaultSaleUnit: 'DOZEN'),
        ),
        throwsFormatException,
      );
    });
  });

  group('CatalogItem (the picker row)', () {
    Map<String, dynamic> item({
      bool inMyStore = false,
      int? storeProductId,
      bool archived = false,
    }) => {
      ..._catalogProductJson(),
      'inMyStore': inMyStore,
      'storeProductId': storeProductId,
      'storeProductArchived': archived,
    };

    test('a product the store does not have', () {
      final entry = CatalogItem.fromJson(item());

      expect(entry.product.slug, 'banane');
      expect(entry.inMyStore, isFalse);
      expect(entry.storeProductId, isNull);
      expect(entry.storeProductArchived, isFalse);
    });

    test('a product the store sells', () {
      final entry = CatalogItem.fromJson(
        item(inMyStore: true, storeProductId: 7),
      );

      expect(entry.inMyStore, isTrue);
      expect(entry.storeProductId, 7);
    });

    test('a product the store archived can be restored, not added', () {
      final entry = CatalogItem.fromJson(
        item(storeProductId: 7, archived: true),
      );

      expect(entry.inMyStore, isFalse);
      expect(entry.storeProductArchived, isTrue);
      expect(entry.storeProductId, 7);
    });
  });

  group('StoreProduct', () {
    test('parses the store data and the global product with its category', () {
      final storeProduct = StoreProduct.fromJson(_storeProductJson());

      expect(storeProduct.id, 7);
      expect(storeProduct.productId, 12);
      expect(storeProduct.saleUnit, SaleUnit.kg);
      expect(storeProduct.priceMillimes, 4500);
      expect(storeProduct.minQuantity, 100);
      expect(storeProduct.quantityStep, 100);
      expect(storeProduct.maxQuantity, 10000);
      expect(storeProduct.isAvailable, isTrue);
      expect(storeProduct.isArchived, isFalse);
      // The catalog product, rebuilt with the sibling `category`.
      expect(storeProduct.product.slug, 'banane');
      expect(storeProduct.product.name, 'Banane');
      expect(storeProduct.product.allowedSaleUnits, [
        SaleUnit.kg,
        SaleUnit.piece,
      ]);
      expect(storeProduct.category.name, 'Fruits');
      expect(storeProduct.category, same(storeProduct.product.category));
    });

    test('the store can have no maximum', () {
      expect(
        StoreProduct.fromJson(_storeProductJson(max: null)).maxQuantity,
        isNull,
      );
    });

    test('a store can sell by a different unit and rules than the catalog', () {
      final json = _storeProductJson()
        ..['saleUnit'] = 'PIECE'
        ..['minQuantity'] = 1
        ..['quantityStep'] = 1
        ..['maxQuantity'] = null;

      final storeProduct = StoreProduct.fromJson(json);

      expect(storeProduct.saleUnit, SaleUnit.piece);
      expect(storeProduct.product.defaultSaleUnit, SaleUnit.kg);
      expect(storeProduct.quantityStep, 1);
    });

    test('an archived offering is flagged', () {
      final storeProduct = StoreProduct.fromJson(
        _storeProductJson(
          archivedAt: '2026-10-03 12:00:00+00',
          isOrderable: false,
          reason: 'ARCHIVED',
        ),
      );

      expect(storeProduct.isArchived, isTrue);
      expect(storeProduct.unavailabilityReason, UnavailabilityReason.archived);
    });

    test('parses catalog state of the product and category', () {
      final storeProduct = StoreProduct.fromJson(
        _storeProductJson(productActive: false, categoryActive: false),
      );

      expect(storeProduct.product.isActive, isFalse);
      expect(storeProduct.category.isActive, isFalse);
    });
  });

  group('stock parsing', () {
    test('tracked stock is read in base units', () {
      final storeProduct = StoreProduct.fromJson(
        _storeProductJson(stockQuantity: 20000),
      );

      expect(storeProduct.trackStock, isTrue);
      expect(storeProduct.stockQuantity, 20000);
      expect(storeProduct.isOrderable, isTrue);
      expect(storeProduct.unavailabilityReason, isNull);
    });

    test('untracked stock has no quantity', () {
      final storeProduct = StoreProduct.fromJson(
        _storeProductJson(trackStock: false, stockQuantity: null),
      );

      expect(storeProduct.trackStock, isFalse);
      expect(storeProduct.stockQuantity, isNull);
      expect(storeProduct.isOrderable, isTrue);
    });

    test(
      'zero stock is unorderable on its own — the owner switch stays on',
      () {
        final storeProduct = StoreProduct.fromJson(
          _storeProductJson(
            stockQuantity: 0,
            isOrderable: false,
            reason: 'OUT_OF_STOCK',
          ),
        );

        expect(storeProduct.stockQuantity, 0);
        expect(storeProduct.isAvailable, isTrue);
        expect(storeProduct.isOrderable, isFalse);
        expect(
          storeProduct.unavailabilityReason,
          UnavailabilityReason.outOfStock,
        );
      },
    );

    test('stock below the minimum order is its own reason', () {
      final storeProduct = StoreProduct.fromJson(
        _storeProductJson(
          stockQuantity: 50,
          isOrderable: false,
          reason: 'STOCK_BELOW_MINIMUM',
        ),
      );

      expect(
        storeProduct.unavailabilityReason,
        UnavailabilityReason.stockBelowMinimum,
      );
    });

    test('an untracked product the owner switched off', () {
      final storeProduct = StoreProduct.fromJson(
        _storeProductJson(
          trackStock: false,
          stockQuantity: null,
          isAvailable: false,
          isOrderable: false,
          reason: 'OWNER_DISABLED',
        ),
      );

      expect(storeProduct.isAvailable, isFalse);
      expect(
        storeProduct.unavailabilityReason,
        UnavailabilityReason.ownerDisabled,
      );
    });

    test('every backend reason is understood', () {
      const reasons = {
        'ARCHIVED': UnavailabilityReason.archived,
        'OWNER_DISABLED': UnavailabilityReason.ownerDisabled,
        'CATALOG_ARCHIVED': UnavailabilityReason.catalogArchived,
        'OUT_OF_STOCK': UnavailabilityReason.outOfStock,
        'STOCK_BELOW_MINIMUM': UnavailabilityReason.stockBelowMinimum,
      };
      for (final entry in reasons.entries) {
        expect(UnavailabilityReason.fromJson(entry.key), entry.value);
      }
      expect(
        () => UnavailabilityReason.fromJson('SOLD_OUT'),
        throwsFormatException,
      );
    });
  });

  group('what the owner sends', () {
    test('adding a product sends only what was chosen', () {
      expect(
        const NewStoreProduct(productId: 12, priceMillimes: 4500).toJson(),
        {'productId': 12, 'priceMillimes': 4500},
      );
    });

    test('adding can set the unit, rules, stock and availability', () {
      final json = const NewStoreProduct(
        productId: 12,
        priceMillimes: 4500,
        saleUnit: SaleUnit.piece,
        minQuantity: 1,
        quantityStep: 1,
        maxQuantity: 12,
        trackStock: true,
        stockQuantity: 30,
        isAvailable: false,
      ).toJson();

      expect(json, {
        'productId': 12,
        'priceMillimes': 4500,
        'saleUnit': 'PIECE',
        'minQuantity': 1,
        'quantityStep': 1,
        'maxQuantity': 12,
        'trackStock': true,
        'stockQuantity': 30,
        'isAvailable': false,
      });
    });

    test('"no maximum" is sent as null, which differs from leaving it out', () {
      final json = const NewStoreProduct(
        productId: 12,
        priceMillimes: 4500,
        noMaximum: true,
      ).toJson();

      expect(json.containsKey('maxQuantity'), isTrue);
      expect(json['maxQuantity'], isNull);
    });

    test('an edit sends only the fields that change', () {
      expect(const StoreProductUpdate(priceMillimes: 4700).toJson(), {
        'priceMillimes': 4700,
      });
      expect(const StoreProductUpdate().toJson(), isEmpty);
    });

    test('clearing the maximum sends null', () {
      final json = const StoreProductUpdate(clearMaxQuantity: true).toJson();

      expect(json, {'maxQuantity': null});
    });

    test('a stock count always carries the stock the screen loaded', () {
      final json = const StoreProductUpdate(
        stock: StockChange(stockQuantity: 7500, expectedStockQuantity: 20000),
      ).toJson();

      expect(json, {'stockQuantity': 7500, 'expectedStockQuantity': 20000});
    });

    test(
      'turning tracking on expects "not tracked" (null) — and still sends it',
      () {
        final json = const StoreProductUpdate(
          stock: StockChange(
            trackStock: true,
            stockQuantity: 20000,
            expectedStockQuantity: null,
          ),
        ).toJson();

        expect(json.containsKey('expectedStockQuantity'), isTrue);
        expect(json, {
          'trackStock': true,
          'stockQuantity': 20000,
          'expectedStockQuantity': null,
        });
      },
    );

    test('turning tracking off', () {
      expect(
        const StockChange(
          trackStock: false,
          expectedStockQuantity: 7500,
        ).toJson(),
        {'trackStock': false, 'expectedStockQuantity': 7500},
      );
    });

    test('a stock change must actually change something', () {
      expect(
        () => StockChange(expectedStockQuantity: 100),
        throwsA(isA<AssertionError>()),
      );
    });

    test('"no maximum" and a maximum are mutually exclusive', () {
      expect(
        () => NewStoreProduct(
          productId: 1,
          priceMillimes: 1,
          maxQuantity: 5,
          noMaximum: true,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => StoreProductUpdate(maxQuantity: 5, clearMaxQuantity: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('nothing the catalog owns can be sent', () {
      final keys = {
        ...const NewStoreProduct(productId: 1, priceMillimes: 1).toJson().keys,
        ...const StoreProductUpdate(priceMillimes: 1).toJson().keys,
      };
      for (final global in [
        'name',
        'description',
        'photo',
        'categoryId',
        'slug',
      ]) {
        expect(keys, isNot(contains(global)));
      }
    });
  });
}
