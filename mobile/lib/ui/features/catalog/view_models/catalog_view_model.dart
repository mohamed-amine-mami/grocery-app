import 'package:flutter/foundation.dart';

import '../../../../data/models/catalog_category.dart';
import '../../../../data/models/store_product.dart';
import '../../../../data/repositories/store_products_repository.dart';
import '../../../../data/services/api_client.dart';

enum CatalogStatus { loading, ready, failed }

/// A run of products shown under one heading (a catalog category).
class ProductGroup {
  const ProductGroup({
    required this.title,
    required this.categoryId,
    required this.products,
  });

  final String title;
  final int categoryId;
  final List<StoreProduct> products;
}

/// The owner's active catalogue: the products the store sells, organized by
/// their (global) category, the category filter, and the availability switch.
/// Archived products are never loaded. Categories are not loaded separately —
/// they are the categories of the products the store sells.
class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({required this._storeProductsRepository});

  final StoreProductsRepository _storeProductsRepository;

  CatalogStatus _status = CatalogStatus.loading;
  CatalogStatus get status => _status;

  List<StoreProduct> _products = const [];
  List<StoreProduct> get products => _products;

  /// `null` = all, or a category id.
  int? _filter;
  int? get filter => _filter;

  final _togglingIds = <int>{};
  bool isToggling(StoreProduct product) => _togglingIds.contains(product.id);

  /// The categories the store sells in, alphabetical.
  List<CategoryRef> get categories {
    final byId = {for (final p in _products) p.category.id: p.category};
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> load() async {
    _status = CatalogStatus.loading;
    notifyListeners();
    try {
      _products = await _storeProductsRepository.listActive();
      _dropStaleFilter();
      _status = CatalogStatus.ready;
    } catch (_) {
      _status = CatalogStatus.failed;
    }
    notifyListeners();
  }

  /// Pull-to-refresh: reloads without replacing the list with a spinner, and
  /// keeps what is already shown if the reload fails.
  Future<void> refresh() async {
    try {
      _products = await _storeProductsRepository.listActive();
      _dropStaleFilter();
    } catch (_) {
      // Keep the current list.
    }
    notifyListeners();
  }

  void _dropStaleFilter() {
    if (_filter != null && !categories.any((c) => c.id == _filter)) {
      _filter = null;
    }
  }

  void selectFilter(int? filter) {
    _filter = filter;
    notifyListeners();
  }

  /// Products grouped by category (alphabetical), narrowed by the current
  /// filter. Within a group the backend's order (by name) is kept.
  List<ProductGroup> get groups {
    final all = [
      for (final category in categories)
        ProductGroup(
          title: category.name,
          categoryId: category.id,
          products: [
            for (final p in _products)
              if (p.category.id == category.id) p,
          ],
        ),
    ];
    return _filter == null
        ? all
        : all.where((g) => g.categoryId == _filter).toList();
  }

  /// Flips the owner's switch. Returns a French error message, or `null` on
  /// success.
  Future<String?> toggleAvailability(StoreProduct product) async {
    if (!_togglingIds.add(product.id)) {
      return null;
    }
    notifyListeners();
    try {
      final updated = await _storeProductsRepository.setAvailability(
        product.id,
        isAvailable: !product.isAvailable,
      );
      _products = [
        for (final p in _products)
          if (p.id == updated.id) updated else p,
      ];
      return null;
    } on ApiException catch (_) {
      return 'Impossible de modifier la disponibilité. Veuillez réessayer.';
    } on NetworkException catch (_) {
      return 'Impossible de contacter le serveur. Vérifiez votre connexion.';
    } finally {
      _togglingIds.remove(product.id);
      notifyListeners();
    }
  }
}
