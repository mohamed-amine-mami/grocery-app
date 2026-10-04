import 'package:flutter/foundation.dart';

import '../../../../data/models/catalog_category.dart';
import '../../../../data/models/catalog_product.dart';
import '../../../../data/repositories/catalog_repository.dart';
import '../../../core/utils/search_text.dart';

enum CatalogPickerStatus { loading, ready, failed }

/// The owner's catalog picker: the whole global catalog, loaded once and
/// searched and filtered locally (it is a few hundred products). The catalog
/// itself is read-only — the owner only *chooses* existing products to add.
class CatalogPickerViewModel extends ChangeNotifier {
  CatalogPickerViewModel({required this._catalogRepository});

  final CatalogRepository _catalogRepository;

  CatalogPickerStatus _status = CatalogPickerStatus.loading;
  CatalogPickerStatus get status => _status;

  List<CatalogItem> _items = const [];

  /// Every product in the catalog, unfiltered.
  List<CatalogItem> get items => _items;

  String _query = '';
  String get query => _query;

  /// `null` = all categories, otherwise a category id.
  int? _categoryFilter;
  int? get categoryFilter => _categoryFilter;

  bool get hasActiveFilters =>
      _query.trim().isNotEmpty || _categoryFilter != null;

  /// The categories that have products, alphabetical (accents ignored).
  List<CategoryRef> get categories {
    final byId = {
      for (final i in _items) i.product.category.id: i.product.category,
    };
    return byId.values.toList()..sort(
      (a, b) => SearchText.fold(a.name).compareTo(SearchText.fold(b.name)),
    );
  }

  /// The products matching the search words and the category filter, in the
  /// backend's order (by name).
  List<CatalogItem> get visibleItems => [
    for (final item in _items)
      if ((_categoryFilter == null ||
              item.product.category.id == _categoryFilter) &&
          SearchText.matches(
            '${item.product.name} ${item.product.category.name}',
            _query,
          ))
        item,
  ];

  Future<void> load() async {
    _status = CatalogPickerStatus.loading;
    notifyListeners();
    try {
      _items = await _catalogRepository.products();
      _dropStaleFilter();
      _status = CatalogPickerStatus.ready;
    } catch (_) {
      _status = CatalogPickerStatus.failed;
    }
    notifyListeners();
  }

  /// Pull-to-refresh: reloads without a spinner, and keeps what is shown if
  /// the reload fails.
  Future<void> refresh() async {
    try {
      _items = await _catalogRepository.products();
      _dropStaleFilter();
    } catch (_) {
      // Keep the current list.
    }
    notifyListeners();
  }

  void _dropStaleFilter() {
    if (_categoryFilter != null &&
        !categories.any((c) => c.id == _categoryFilter)) {
      _categoryFilter = null;
    }
  }

  /// The picker's row for [productId], if it is in the catalog.
  CatalogItem? itemFor(int productId) {
    for (final item in _items) {
      if (item.product.id == productId) {
        return item;
      }
    }
    return null;
  }

  /// Marks a product as in the store after it was added — locally, with no
  /// refetch, so the owner can carry on adding straight away.
  void markAdded(int productId, int storeProductId) {
    _items = [
      for (final item in _items)
        if (item.product.id == productId)
          CatalogItem(
            product: item.product,
            inMyStore: true,
            storeProductId: storeProductId,
            storeProductArchived: false,
          )
        else
          item,
    ];
    notifyListeners();
  }

  void setQuery(String query) {
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
