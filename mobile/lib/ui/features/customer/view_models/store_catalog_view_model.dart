import 'package:flutter/foundation.dart';

import '../../../../data/models/catalog_category.dart';
import '../../../../data/models/customer_product.dart';
import '../../../../data/repositories/customer_stores_repository.dart';
import '../../../core/utils/search_text.dart';

enum StoreCatalogStatus { loading, ready, failed }

/// A run of products shown under one heading (a category).
class CustomerProductGroup {
  const CustomerProductGroup({required this.category, required this.products});

  final CategoryRef category;
  final List<CustomerProduct> products;
}

/// One store's catalogue for a customer. Search and the category filter run
/// locally over what the backend returned; nothing here decides what can be
/// ordered.
class StoreCatalogViewModel extends ChangeNotifier {
  StoreCatalogViewModel({
    required this._repository,
    required this.storeId,
    this.onLoaded,
  });

  final CustomerStoresRepository _repository;
  final int storeId;

  /// Called with every successful load, e.g. to bring the cart up to date.
  final void Function(List<CustomerProduct> products)? onLoaded;

  StoreCatalogStatus _status = StoreCatalogStatus.loading;
  StoreCatalogStatus get status => _status;

  List<CustomerProduct> _products = const [];
  List<CustomerProduct> get products => _products;

  String _query = '';
  String get query => _query;

  /// `null` = all categories.
  int? _categoryFilter;
  int? get categoryFilter => _categoryFilter;

  bool get hasActiveFilters =>
      _query.trim().isNotEmpty || _categoryFilter != null;

  bool _refreshFailed = false;
  bool get refreshFailed => _refreshFailed;

  /// The categories that have products here, alphabetical (accents ignored).
  List<CategoryRef> get categories {
    final byId = {for (final p in _products) p.category.id: p.category};
    return byId.values.toList()..sort(
      (a, b) => SearchText.fold(a.name).compareTo(SearchText.fold(b.name)),
    );
  }

  /// Search words match the product's name, brand, description and category.
  List<CustomerProduct> get visibleProducts => [
    for (final product in _products)
      if ((_categoryFilter == null || product.category.id == _categoryFilter) &&
          SearchText.matches(
            '${product.name} ${product.brand?.name ?? ''} ${product.description ?? ''} ${product.category.name}',
            _query,
          ))
        product,
  ];

  /// The visible products under their categories, in the backend's order.
  List<CustomerProductGroup> get groups {
    final visible = visibleProducts;
    return [
      for (final category in categories)
        if (visible.any((p) => p.category.id == category.id))
          CustomerProductGroup(
            category: category,
            products: [
              for (final p in visible)
                if (p.category.id == category.id) p,
            ],
          ),
    ];
  }

  Future<void> load() async {
    _status = StoreCatalogStatus.loading;
    notifyListeners();
    try {
      _apply(await _repository.products(storeId));
      _status = StoreCatalogStatus.ready;
    } catch (_) {
      _status = StoreCatalogStatus.failed;
    }
    notifyListeners();
  }

  /// Pull-to-refresh: keeps the catalogue on screen if the reload fails.
  Future<void> refresh() async {
    try {
      _apply(await _repository.products(storeId));
    } catch (_) {
      _refreshFailed = true;
    }
    notifyListeners();
  }

  void _apply(List<CustomerProduct> products) {
    _products = products;
    _refreshFailed = false;
    if (_categoryFilter != null &&
        !categories.any((c) => c.id == _categoryFilter)) {
      _categoryFilter = null;
    }
    onLoaded?.call(products);
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  void selectCategory(int? categoryId) {
    _categoryFilter = categoryId;
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _categoryFilter = null;
    notifyListeners();
  }
}
