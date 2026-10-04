import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/catalog_picker_view_model.dart';

import 'fakes.dart';

CatalogPickerViewModel _viewModel(FakeCatalogRepository catalog) =>
    CatalogPickerViewModel(catalogRepository: catalog);

FakeCatalogRepository _catalog({bool fails = false, Completer<void>? gate}) =>
    FakeCatalogRepository(
      ApiClient(),
      items: fakeCatalogItems(),
      fails: fails,
      gate: gate,
    );

List<String> _names(CatalogPickerViewModel vm) => [
  for (final item in vm.visibleItems) item.product.name,
];

void main() {
  group('loading', () {
    test('starts loading, then is ready with every product', () async {
      final gate = Completer<void>();
      final vm = _viewModel(_catalog(gate: gate));

      final loading = vm.load();
      expect(vm.status, CatalogPickerStatus.loading);

      gate.complete();
      await loading;

      expect(vm.status, CatalogPickerStatus.ready);
      expect(vm.items, hasLength(6));
      expect(vm.visibleItems, hasLength(6));
    });

    test('fails when the catalog cannot be fetched, and can retry', () async {
      final catalog = _catalog(fails: true);
      final vm = _viewModel(catalog);

      await vm.load();
      expect(vm.status, CatalogPickerStatus.failed);
      expect(vm.items, isEmpty);

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

    test('a refresh picks up changes', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      catalog.items = [
        ...catalog.items,
        fakeCatalogItem(id: 7, name: 'Citron'),
      ];
      await vm.refresh();

      expect(vm.items, hasLength(7));
    });
  });

  group('search', () {
    test('filters locally without refetching', () async {
      final catalog = _catalog();
      final vm = _viewModel(catalog);
      await vm.load();

      vm.setQuery('pomme');

      expect(_names(vm), ['Pomme', 'Pomme de terre']);
      expect(catalog.productsCalls, 1);
    });

    test(
      'ignores accents and case, and matches the category name too',
      () async {
        final vm = _viewModel(_catalog());
        await vm.load();

        vm.setQuery('OEUF');
        expect(_names(vm), ['Œufs']);

        vm.setQuery('laitiers');
        expect(_names(vm), ['Œufs', 'Lait entier 1 L']);
      },
    );

    test('a blank query shows everything', () async {
      final vm = _viewModel(_catalog());
      await vm.load();

      vm.setQuery('   ');

      expect(vm.visibleItems, hasLength(6));
      expect(vm.hasActiveFilters, isFalse);
    });
  });

  group('categories', () {
    test(
      'are the ones that have products, alphabetical ignoring accents',
      () async {
        final vm = _viewModel(_catalog());
        await vm.load();

        expect(vm.categories.map((c) => c.name), [
          'Fruits',
          'Légumes',
          'Produits laitiers',
        ]);
      },
    );

    test('filter the list and combine with the search', () async {
      final vm = _viewModel(_catalog());
      await vm.load();

      vm.selectCategory(fakeVegetables.id);
      expect(_names(vm), ['Pomme de terre', 'Tomate']);

      vm.setQuery('pomme');
      expect(_names(vm), ['Pomme de terre']);

      vm.selectCategory(null);
      expect(_names(vm), ['Pomme', 'Pomme de terre']);
    });

    test(
      'a filter on a category that disappeared is dropped on refresh',
      () async {
        final catalog = _catalog();
        final vm = _viewModel(catalog);
        await vm.load();
        vm.selectCategory(fakeVegetables.id);

        catalog.items = [
          for (final i in catalog.items)
            if (i.product.category.id != fakeVegetables.id) i,
        ];
        await vm.refresh();

        expect(vm.categoryFilter, isNull);
        expect(vm.visibleItems, hasLength(4));
      },
    );
  });

  group('clearing', () {
    test(
      'clearFilters resets search and category, and reports no filters',
      () async {
        final vm = _viewModel(_catalog());
        await vm.load();
        vm.setQuery('zzz');
        vm.selectCategory(fakeDairy.id);
        expect(vm.hasActiveFilters, isTrue);
        expect(vm.visibleItems, isEmpty);

        vm.clearFilters();

        expect(vm.query, isEmpty);
        expect(vm.categoryFilter, isNull);
        expect(vm.hasActiveFilters, isFalse);
        expect(vm.visibleItems, hasLength(6));
      },
    );
  });

  group('already in the store', () {
    test('the flag travels with the item through search and filters', () async {
      final vm = _viewModel(_catalog());
      await vm.load();

      vm.selectCategory(fakePickerFruits.id);
      vm.setQuery('banane');

      final only = vm.visibleItems.single;
      expect(only.product.name, 'Banane');
      expect(only.inMyStore, isTrue);
    });
  });
}
