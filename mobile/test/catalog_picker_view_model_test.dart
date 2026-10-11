import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/brand.dart';
import 'package:grocery_mobile/data/models/catalog_category.dart';
import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/catalog_picker_view_model.dart';

import 'fakes.dart';

/// A short debounce so the tests run in real time without waiting long.
const _delay = Duration(milliseconds: 20);

CatalogPickerViewModel _viewModel(
  FakeCatalogRepository catalog, {
  int pageSize = 40,
}) => CatalogPickerViewModel(
  catalogRepository: catalog,
  pageSize: pageSize,
  searchDelay: _delay,
);

FakeCatalogRepository _catalog({
  bool fails = false,
  Completer<void>? gate,
  List<CatalogItem>? items,
}) => FakeCatalogRepository(
  ApiClient(),
  items: items ?? fakeCatalogItems(),
  fails: fails,
  gate: gate,
);

/// Lets the debounce fire and the request that follows complete.
Future<void> _settle() async {
  await Future<void>.delayed(_delay * 3);
  await pumpEventQueue();
}

List<String> _names(CatalogPickerViewModel vm) => [
  for (final item in vm.items) item.product.name,
];

List<CatalogItem> _many(int count) => [
  for (var i = 1; i <= count; i++)
    fakeCatalogItem(id: i, name: 'Produit ${i.toString().padLeft(5, '0')}'),
];

void main() {
  group('loading', () {
    test('starts loading, then holds only the first page', () async {
      final gate = Completer<void>();
      final catalog = _catalog(gate: gate);
      final vm = _viewModel(catalog, pageSize: 4);

      final loading = vm.load();
      expect(vm.status, CatalogPickerStatus.loading);
      expect(vm.hasLoadedOnce, isFalse);

      gate.complete();
      await loading;

      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.hasLoadedOnce, isTrue);
      expect(vm.items, hasLength(4));
      expect(vm.total, 6);
      expect(vm.hasMore, isTrue);
      expect(catalog.browseCalls.single.limit, 4);
      expect(catalog.browseCalls.single.cursor, isNull);
    });

    test('fails when the catalog cannot be fetched, and can retry', () async {
      final catalog = _catalog(fails: true);
      final vm = _viewModel(catalog);

      await vm.load();
      expect(vm.status, CatalogPickerStatus.failed);
      expect(vm.items, isEmpty);
      expect(vm.hasLoadedOnce, isFalse);

      catalog.fails = false;
      await vm.load();
      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.items, hasLength(6));
    });

    test('a failed refresh keeps what is already shown', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      catalog.fails = true;
      await vm.refresh();

      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.items, hasLength(6));
    });

    test('a refresh picks up changes, back from the first page', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog, pageSize: 4);
      await vm.load();
      await vm.loadMore();
      expect(vm.items, hasLength(6));

      catalog.items = [
        ...catalog.items,
        fakeCatalogItem(id: 7, name: 'Citron'),
      ];
      await vm.refresh();

      expect(vm.items, hasLength(4)); // first page again
      expect(vm.total, 7);
      expect(vm.hasMore, isTrue);
    });

    test('an empty catalog is ready with nothing in it', () async {
      final vm = _viewModel(_catalog(items: const []));
      await vm.load();

      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.items, isEmpty);
      expect(vm.total, 0);
      expect(vm.hasMore, isFalse);
      expect(vm.hasActiveFilters, isFalse);
    });
  });

  group('paging', () {
    test('loadMore appends the next page, in order, until the end', () async {
      final catalog = _catalog(items: _many(10));
      final vm = _viewModel(catalog, pageSize: 4);
      await vm.load();
      expect(vm.items.map((i) => i.product.id), [1, 2, 3, 4]);

      await vm.loadMore();
      expect(vm.items.map((i) => i.product.id), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(vm.hasMore, isTrue);

      await vm.loadMore();
      expect(vm.items.map((i) => i.product.id), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);
      expect(vm.hasMore, isFalse);
      expect(vm.total, 10);

      // Nothing more to ask for.
      final calls = catalog.browseCalls.length;
      await vm.loadMore();
      expect(catalog.browseCalls, hasLength(calls));
    });

    test('an exact multiple of the page size has no extra page', () async {
      final catalog = _catalog(items: _many(8));
      final vm = _viewModel(catalog, pageSize: 4);
      await vm.load();
      await vm.loadMore();

      expect(vm.items, hasLength(8));
      expect(vm.hasMore, isFalse);
      expect(catalog.browseCalls, hasLength(2));
    });

    test('a single page has no more to load', () async {
      final vm = _viewModel(_catalog(items: _many(3)), pageSize: 40);
      await vm.load();
      expect(vm.hasMore, isFalse);
      expect(vm.items, hasLength(3));
    });

    test('calls while a page is on its way ask for it only once', () async {
      final catalog = _catalog(items: _many(10));
      final vm = _viewModel(catalog, pageSize: 4);
      await vm.load();

      final gate = Completer<void>();
      catalog.gate = gate;
      final a = vm.loadMore();
      final b = vm.loadMore();
      final c = vm.loadMore();
      expect(vm.isLoadingMore, isTrue);
      gate.complete();
      await Future.wait([a, b, c]);

      expect(catalog.browseCalls, hasLength(2)); // first page + one more
      expect(vm.items, hasLength(8));
      expect(vm.isLoadingMore, isFalse);
    });

    test('never shows a product twice, even if a page overlaps', () async {
      final catalog = _catalog(items: _many(10));
      final vm = _viewModel(catalog, pageSize: 4);
      await vm.load();
      // The backend repeats row 4 at the start of the next page.
      catalog.onBrowse = (call) async {
        if (call.cursor != null) {
          catalog.items = [catalog.items[0], ...catalog.items];
        }
      };
      await vm.loadMore();

      final ids = vm.items.map((i) => i.product.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('a failed page keeps the loaded rows and can be retried', () async {
      final catalog = _catalog(items: _many(10));
      final vm = _viewModel(catalog, pageSize: 4);
      await vm.load();

      catalog.fails = true;
      await vm.loadMore();
      expect(vm.loadMoreFailed, isTrue);
      expect(vm.isLoadingMore, isFalse);
      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.items, hasLength(4));

      catalog.fails = false;
      await vm.loadMore();
      expect(vm.loadMoreFailed, isFalse);
      expect(vm.items, hasLength(8));
    });

    test('a large catalog is fetched a page at a time', () async {
      final catalog = _catalog(items: _many(5700));
      final vm = _viewModel(catalog, pageSize: 40);

      await vm.load();
      expect(vm.items, hasLength(40)); // not 5,700
      expect(vm.total, 5700);
      expect(catalog.browseCalls, hasLength(1));

      var guard = 0;
      while (vm.hasMore) {
        await vm.loadMore();
        expect(++guard, lessThan(200));
      }
      expect(vm.items, hasLength(5700));
      expect(
        vm.items.map((i) => i.product.id).toSet(),
        hasLength(5700),
        reason: 'no duplicate across 143 pages',
      );
      expect(vm.items.map((i) => i.product.id), [
        for (var i = 1; i <= 5700; i++) i,
      ], reason: 'no skipped row, in order');
      expect(catalog.browseCalls, hasLength(143)); // ceil(5700 / 40)
    });
  });

  group('search', () {
    test('is sent to the backend, after a pause in typing', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      expect(catalog.browseCalls, hasLength(1));

      vm.setQuery('p');
      vm.setQuery('po');
      vm.setQuery('pomme');
      expect(catalog.browseCalls, hasLength(1)); // still typing
      expect(vm.query, 'pomme');

      await _settle();
      expect(catalog.browseCalls, hasLength(2)); // one request for the word
      expect(catalog.browseCalls.last.query, 'pomme');
      expect(_names(vm), ['Pomme', 'Pomme de terre']);
      expect(vm.total, 2);
    });

    test('starts again from the first page', () async {
      final catalog = _catalog(items: _many(30));
      final vm = _viewModel(catalog, pageSize: 5);
      await vm.load();
      await vm.loadMore();
      await vm.loadMore();
      expect(vm.items, hasLength(15));

      vm.setQuery('Produit 0000'); // matches 1..9
      await _settle();

      expect(catalog.browseCalls.last.cursor, isNull);
      expect(vm.items.map((i) => i.product.id), [1, 2, 3, 4, 5]);
      expect(vm.total, 9);
      expect(vm.hasMore, isTrue);

      await vm.loadMore();
      expect(vm.items.map((i) => i.product.id), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(catalog.browseCalls.last.query, 'Produit 0000');
    });

    test('ignores accents and case, and matches the category name', () async {
      final vm = _viewModel(_catalog());
      await vm.load();

      vm.setQuery('OEUF');
      await _settle();
      expect(_names(vm), ['Œufs']);

      vm.setQuery('laitiers');
      await _settle();
      expect(_names(vm), ['Œufs', 'Lait entier 1 L']);
    });

    test('a blank query shows everything and is not a filter', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      vm.setQuery('   ');
      await _settle();

      expect(vm.items, hasLength(6));
      expect(vm.hasActiveFilters, isFalse);
      expect(catalog.browseCalls.last.query, isNull);
    });

    test('an unchanged text does not search again', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      vm.setQuery('pomme');
      await _settle();
      final calls = catalog.browseCalls.length;

      vm.setQuery('pomme');
      await _settle();

      expect(catalog.browseCalls, hasLength(calls));
    });

    test('a reply to an earlier search never replaces a newer one', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      // The first search ("pomme") is held back; "tomate" answers first.
      final slow = Completer<void>();
      catalog.onBrowse = (call) async {
        if (call.query == 'pomme') {
          await slow.future;
        }
      };
      vm.setQuery('pomme');
      await Future<void>.delayed(_delay * 2);
      vm.setQuery('tomate');
      await _settle();
      expect(_names(vm), ['Tomate']);

      slow.complete();
      await pumpEventQueue();

      expect(_names(vm), ['Tomate']);
      expect(vm.total, 1);
      expect(vm.status, CatalogPickerStatus.ready);
    });

    test('a page of an earlier search is not added to the new list', () async {
      final catalog = _catalog(items: _many(20));
      final vm = _viewModel(catalog, pageSize: 5);
      await vm.load();

      final slow = Completer<void>();
      catalog.onBrowse = (call) async {
        if (call.cursor != null && call.query == null) {
          await slow.future;
        }
      };
      final pending = vm.loadMore(); // page 2 of the unfiltered list
      await pumpEventQueue();
      vm.setQuery('Produit 00019');
      await _settle();
      expect(vm.items.map((i) => i.product.id), [19]);

      slow.complete();
      await pending;

      expect(vm.items.map((i) => i.product.id), [19]);
      expect(vm.total, 1);
    });

    test('the next page uses the search the loaded pages belong to, never '
        'one typed since', () async {
      final catalog = _catalog(items: _many(30));
      final vm = _viewModel(catalog, pageSize: 5);
      await vm.load();

      // The owner types while a prefetch of page 2 fires: the debounce has not
      // run yet, so the list on screen is still the unfiltered one.
      vm.setQuery('Produit 0002');
      await vm.loadMore();

      final nextPage = catalog.browseCalls.last;
      expect(nextPage.cursor, isNotNull);
      expect(nextPage.query, isNull); // not 'Produit 0002'
      expect(nextPage.categoryId, isNull);
      expect(vm.items.map((i) => i.product.id), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);

      // Then the debounce fires and the list restarts for the new search.
      await _settle();
      expect(catalog.browseCalls.last.cursor, isNull);
      expect(catalog.browseCalls.last.query, 'Produit 0002');
      expect(vm.items.map((i) => i.product.id).first, 2);
      expect(vm.total, 11); // 2, 20..29
    });

    test('the next page keeps the category of the loaded pages when the '
        'filter changes', () async {
      final catalog = _catalog(
        items: [
          ..._many(12),
          for (var i = 0; i < 12; i++)
            fakeCatalogItem(
              id: 100 + i,
              name: 'Legume ${i.toString().padLeft(2, '0')}',
              category: fakeVegetables,
            ),
        ],
      );
      final vm = _viewModel(catalog, pageSize: 5);
      await vm.load();
      vm.selectCategory(fakeVegetables.id);
      await pumpEventQueue();
      expect(vm.items, hasLength(5));

      await vm.loadMore();
      expect(catalog.browseCalls.last.categoryId, fakeVegetables.id);
      expect(catalog.browseCalls.last.cursor, isNotNull);
      expect(
        vm.items.every((i) => i.product.category.id == fakeVegetables.id),
        isTrue,
      );
    });

    test('a failed search shows the error, and a retry recovers', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      catalog.fails = true;
      vm.setQuery('pomme');
      await _settle();
      expect(vm.status, CatalogPickerStatus.failed);
      expect(vm.hasLoadedOnce, isTrue);

      catalog.fails = false;
      await vm.load();
      expect(vm.status, CatalogPickerStatus.ready);
      expect(_names(vm), ['Pomme', 'Pomme de terre']); // the query is kept
    });
  });

  group('categories', () {
    test('are the ones that have products, from the backend', () async {
      final vm = _viewModel(_catalog());
      await vm.load();
      await pumpEventQueue();

      expect(vm.categories.map((c) => c.name), [
        'Fruits',
        'Légumes',
        'Produits laitiers',
      ]);
    });

    test('a category with no product is not offered', () async {
      final catalog = FakeCatalogRepository(
        ApiClient(),
        items: fakeCatalogItems(),
        categoryList: const [
          // Same shape the backend returns, one of them empty.
        ],
      );
      final vm = _viewModel(catalog);
      await vm.load();
      await pumpEventQueue();
      expect(vm.categories.every((c) => c.productCount > 0), isTrue);
    });

    test('a failed categories request still leaves a working list', () async {
      final catalog = _catalog();
      final vm = CatalogPickerViewModel(
        catalogRepository: _OnlyCategoriesFail(catalog),
        searchDelay: _delay,
      );
      await vm.load();
      await pumpEventQueue();

      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.items, hasLength(6));
      expect(vm.categories, isEmpty);
    });

    test(
      'filter the list, reset the pages, and combine with the search',
      () async {
        final catalog = _catalog(
          items: [
            ..._many(12),
            fakeCatalogItem(id: 100, name: 'Tomate', category: fakeVegetables),
            fakeCatalogItem(
              id: 101,
              name: 'Pomme de terre',
              category: fakeVegetables,
            ),
          ],
        );
        final vm = _viewModel(catalog, pageSize: 5);
        await vm.load();
        await vm.loadMore();

        vm.selectCategory(fakeVegetables.id);
        await pumpEventQueue();
        expect(catalog.browseCalls.last.categoryId, fakeVegetables.id);
        expect(catalog.browseCalls.last.cursor, isNull);
        expect(_names(vm), ['Tomate', 'Pomme de terre']);
        expect(vm.total, 2);

        vm.setQuery('pomme');
        await _settle();
        expect(_names(vm), ['Pomme de terre']);
        expect(catalog.browseCalls.last.categoryId, fakeVegetables.id);
        expect(catalog.browseCalls.last.query, 'pomme');

        vm.selectCategory(null);
        await pumpEventQueue();
        expect(catalog.browseCalls.last.categoryId, isNull);
        expect(catalog.browseCalls.last.query, 'pomme'); // search kept
      },
    );

    test('choosing the same category again does nothing', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      vm.selectCategory(fakeVegetables.id);
      await pumpEventQueue();
      final calls = catalog.browseCalls.length;

      vm.selectCategory(fakeVegetables.id);
      await pumpEventQueue();

      expect(catalog.browseCalls, hasLength(calls));
    });

    test(
      'a filter on a category that disappeared is dropped on refresh',
      () async {
        final catalog = _catalog();
        final vm = _viewModel(catalog);
        await vm.load();
        vm.selectCategory(fakeVegetables.id);
        await pumpEventQueue();
        expect(vm.categoryFilter, fakeVegetables.id);

        catalog.items = [
          for (final i in catalog.items)
            if (i.product.category.id != fakeVegetables.id) i,
        ];
        await vm.refresh();
        await pumpEventQueue();

        expect(vm.categoryFilter, isNull);
        expect(vm.items, hasLength(4));
      },
    );
  });

  group('clearing', () {
    test('clearFilters resets search and category, and reloads', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      vm.setQuery('zzz');
      vm.selectCategory(fakeDairy.id);
      await _settle();
      expect(vm.hasActiveFilters, isTrue);
      expect(vm.items, isEmpty);

      vm.clearFilters();
      await pumpEventQueue();

      expect(vm.query, isEmpty);
      expect(vm.categoryFilter, isNull);
      expect(vm.hasActiveFilters, isFalse);
      expect(vm.items, hasLength(6));
    });

    test('with nothing to clear, nothing is requested', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      final calls = catalog.browseCalls.length;

      vm.clearFilters();
      await pumpEventQueue();

      expect(catalog.browseCalls, hasLength(calls));
    });
  });

  group('already in the store', () {
    test('the flag travels with the item through search and filters', () async {
      final vm = _viewModel(_catalog());
      await vm.load();

      vm.selectCategory(fakePickerFruits.id);
      vm.setQuery('banane');
      await _settle();

      final only = vm.items.single;
      expect(only.product.name, 'Banane');
      expect(only.inMyStore, isTrue);
    });

    test('markAdded flags the loaded row locally, without a request', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      final calls = catalog.browseCalls.length;

      vm.markAdded(2, 99);

      final row = vm.itemFor(2)!;
      expect(row.inMyStore, isTrue);
      expect(row.storeProductId, 99);
      expect(catalog.browseCalls, hasLength(calls));
    });

    test('syncItem brings one row in line with the backend', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      expect(vm.itemFor(2)!.inMyStore, isFalse);

      catalog.markAdded(2, 55); // another device added it
      final current = await vm.syncItem(2);

      expect(current!.inMyStore, isTrue);
      expect(vm.itemFor(2)!.storeProductId, 55);
      expect(vm.items, hasLength(6)); // the list was not reloaded
    });

    test('syncItem drops a product the catalog no longer has', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      catalog.remove(2);
      final current = await vm.syncItem(2);

      expect(current, isNull);
      expect(vm.itemFor(2), isNull);
      expect(vm.items, hasLength(5));
      expect(vm.total, 5);
    });

    test('syncItem keeps the row when the backend cannot be reached', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      catalog.fails = true;
      final current = await vm.syncItem(2);

      expect(current!.product.id, 2);
      expect(vm.items, hasLength(6));
    });
  });

  group('search by brand', () {
    const danone = Brand(id: 1, slug: 'delice-danone', name: 'DÉLICE DANONE');
    const sodeen = Brand(id: 2, slug: 'sodeen', name: 'Sodeen');

    CatalogPickerViewModel loaded() => _viewModel(
      FakeCatalogRepository(
        ApiClient(),
        items: [
          fakeCatalogItem(id: 1, name: 'Yaourt nature', brand: danone),
          fakeCatalogItem(id: 2, name: 'Yaourt nature', brand: sodeen),
          fakeCatalogItem(id: 3, name: 'Yaourt nature'),
          fakeCatalogItem(
            id: 4,
            name: 'Crème dessert',
            brand: danone,
            category: fakeDairy,
          ),
        ],
      ),
    );

    test('finds products by brand, case and accents ignored', () async {
      final vm = loaded();
      await vm.load();

      vm.setQuery('danone');
      await _settle();
      expect(vm.items.map((i) => i.product.id), [1, 4]);
      vm.setQuery('DELICE');
      await _settle();
      expect(vm.items.map((i) => i.product.id), [1, 4]);
      vm.setQuery('yaourt danone');
      await _settle();
      expect(vm.items.map((i) => i.product.id), [1]);
    });

    test('brandless products are found by name and category', () async {
      final vm = loaded();
      await vm.load();

      vm.setQuery('yaourt');
      await _settle();
      expect(vm.items, hasLength(3));
      vm.setQuery('produits laitiers');
      await _settle();
      expect(vm.items.single.product.id, 4);
      vm.setQuery('introuvable');
      await _settle();
      expect(vm.items, isEmpty);
    });
  });

  group('disposal', () {
    test('a pending search does nothing once the view model is gone', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();
      final calls = catalog.browseCalls.length;

      vm.setQuery('pomme');
      vm.dispose();
      await _settle();

      expect(catalog.browseCalls, hasLength(calls));
    });

    test('a reply that arrives after disposal is ignored', () async {
      final gate = Completer<void>();
      final catalog = _catalog(gate: gate);
      final vm = _viewModel(catalog);
      final loading = vm.load();
      vm.dispose();
      gate.complete();
      await loading; // must not throw
    });
  });
}

/// A repository whose categories request fails while the products load.
class _OnlyCategoriesFail extends FakeCatalogRepository {
  _OnlyCategoriesFail(FakeCatalogRepository source)
    : super(ApiClient(), items: source.items);

  @override
  Future<List<CatalogCategory>> categories() async =>
      throw const NetworkException('offline');
}
