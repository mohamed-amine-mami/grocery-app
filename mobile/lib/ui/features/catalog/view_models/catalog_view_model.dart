import 'package:flutter/foundation.dart';

import '../../../../data/models/product.dart';
import '../../../../data/models/store_category.dart';
import '../../../../data/repositories/category_repository.dart';
import '../../../../data/repositories/product_repository.dart';
import '../../../../data/services/api_client.dart';

enum CatalogStatus { loading, ready, failed }

/// A run of products shown under one heading (a category, or "Sans catégorie").
class ProductGroup {
  const ProductGroup({
    required this.title,
    required this.products,
    this.categoryId,
  });

  final String title;
  final int? categoryId;
  final List<Product> products;
}

/// The owner's active catalog: products organized by category, the category
/// filter, and the availability switch. Archived products are never loaded.
class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({
    required this._productRepository,
    required this._categoryRepository,
  });

  /// Filter value meaning "products without a category".
  static const uncategorizedFilter = -1;

  final ProductRepository _productRepository;
  final CategoryRepository _categoryRepository;

  CatalogStatus _status = CatalogStatus.loading;
  CatalogStatus get status => _status;

  List<Product> _products = const [];
  List<Product> get products => _products;

  List<StoreCategory> _categories = const [];
  List<StoreCategory> get categories => _categories;

  /// `null` = all, [uncategorizedFilter], or a category id.
  int? _filter;
  int? get filter => _filter;

  final _togglingIds = <int>{};
  bool isToggling(Product product) => _togglingIds.contains(product.id);

  bool get hasUncategorized => _products.any((p) => p.categoryId == null);

  Future<void> load() async {
    _status = CatalogStatus.loading;
    notifyListeners();
    try {
      final (products, categories) = await (
        _productRepository.listActive(),
        _categoryRepository.list(),
      ).wait;
      _products = products;
      _categories = categories;
      if (_filter != null &&
          _filter != uncategorizedFilter &&
          !categories.any((c) => c.id == _filter)) {
        _filter = null;
      }
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
      final (products, categories) = await (
        _productRepository.listActive(),
        _categoryRepository.list(),
      ).wait;
      _products = products;
      _categories = categories;
      if (_filter != null &&
          _filter != uncategorizedFilter &&
          !categories.any((c) => c.id == _filter)) {
        _filter = null;
      }
    } catch (_) {
      // Keep the current list.
    }
    notifyListeners();
  }

  void selectFilter(int? filter) {
    _filter = filter;
    notifyListeners();
  }

  /// Products grouped by category (alphabetical, as the backend sorts them),
  /// uncategorized last, narrowed by the current filter.
  List<ProductGroup> get groups {
    final all = [
      for (final category in _categories)
        ProductGroup(
          title: category.name,
          categoryId: category.id,
          products: [
            for (final p in _products)
              if (p.categoryId == category.id) p,
          ],
        ),
      ProductGroup(
        title: 'Sans catégorie',
        products: [
          for (final p in _products)
            if (p.categoryId == null) p,
        ],
      ),
    ].where((group) => group.products.isNotEmpty);

    return switch (_filter) {
      null => all.toList(),
      uncategorizedFilter => all.where((g) => g.categoryId == null).toList(),
      final id => all.where((g) => g.categoryId == id).toList(),
    };
  }

  /// Flips availability. Returns a French error message, or `null` on success.
  Future<String?> toggleAvailability(Product product) async {
    if (!_togglingIds.add(product.id)) {
      return null;
    }
    notifyListeners();
    try {
      final updated = await _productRepository.setAvailability(
        product.id,
        isAvailable: !product.isAvailable,
      );
      _products = [
        for (final p in _products)
          if (p.id == updated.id)
            p.copyWith(isAvailable: updated.isAvailable)
          else
            p,
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
