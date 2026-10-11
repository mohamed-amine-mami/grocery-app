import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/models/catalog_category.dart';
import '../../../../data/models/catalog_product.dart';
import '../../../../data/repositories/catalog_repository.dart';

/// The state of the list for the current search and category.
enum CatalogPickerStatus { loading, ready, failed }

/// The owner's catalog picker. The catalog is far too large to hold on the
/// device, so the backend searches, filters and pages it: this view model
/// asks for one page at a time and appends the next as the owner scrolls.
/// The catalog itself is read-only — the owner only *chooses* existing
/// products to add.
///
/// Changing the search or the category throws away the pages loaded so far and
/// starts again from the first page. A response that belongs to an earlier
/// search or filter is ignored, so a slow reply can never overwrite a newer
/// one or add rows of the wrong search to the list.
class CatalogPickerViewModel extends ChangeNotifier {
  CatalogPickerViewModel({
    required this._catalogRepository,
    this.pageSize = 40,
    this.searchDelay = const Duration(milliseconds: 300),
  });

  final CatalogRepository _catalogRepository;

  /// Products requested per page.
  final int pageSize;

  /// How long typing must pause before the search is sent.
  final Duration searchDelay;

  CatalogPickerStatus _status = CatalogPickerStatus.loading;

  /// The first page for the current search and category.
  CatalogPickerStatus get status => _status;

  /// `true` once a first page was loaded: from then on the search field and
  /// the category chips stay on screen while the list below reloads.
  bool get hasLoadedOnce => _hasLoadedOnce;
  bool _hasLoadedOnce = false;

  List<CatalogItem> _items = const [];

  /// The products loaded so far for the current search and category.
  List<CatalogItem> get items => _items;

  int _total = 0;

  /// How many products match the current search and category, over all pages.
  int get total => _total;

  String? _nextCursor;

  /// The search and category the loaded pages (and so [_nextCursor]) belong
  /// to. The cursor is a position in *that* result set: the next page is
  /// always requested with these, never with a search typed since.
  String? _pageQuery;
  int? _pageCategory;

  /// More pages can be loaded.
  bool get hasMore => _nextCursor != null;

  bool _loadingMore = false;
  bool get isLoadingMore => _loadingMore;

  bool _loadMoreFailed = false;

  /// The last attempt to load the next page failed; [loadMore] retries it.
  bool get loadMoreFailed => _loadMoreFailed;

  String _query = '';
  String get query => _query;

  /// `null` = all categories, otherwise a category id.
  int? _categoryFilter;
  int? get categoryFilter => _categoryFilter;

  /// What is sent to the backend: the text without surrounding blanks, or
  /// nothing when it is blank.
  String? get _searchText {
    final text = _query.trim();
    return text.isEmpty ? null : text;
  }

  bool get hasActiveFilters =>
      _query.trim().isNotEmpty || _categoryFilter != null;

  List<CatalogCategory> _categories = const [];

  /// The categories that have products, alphabetical as the backend sorts
  /// them. Empty if they could not be loaded: the list still works.
  List<CatalogCategory> get categories => _categories;

  Timer? _searchTimer;

  /// Bumped whenever the search, the category or a reload makes the pages in
  /// flight obsolete.
  int _generation = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// First load (and the retry of a failed one): the categories and the first
  /// page, with the list showing its loading state.
  Future<void> load() async {
    _searchTimer?.cancel();
    unawaited(_loadCategories());
    await _loadFirstPage(showLoading: true);
  }

  /// Pull-to-refresh: reloads the first page without a spinner and keeps what
  /// is shown if the reload fails.
  Future<void> refresh() async {
    _searchTimer?.cancel();
    unawaited(_loadCategories());
    await _loadFirstPage(showLoading: false);
  }

  Future<void> _loadCategories() async {
    try {
      final loaded = await _catalogRepository.categories();
      _categories = [
        for (final category in loaded)
          if (category.productCount > 0) category,
      ];
      if (_categoryFilter != null &&
          !_categories.any((c) => c.id == _categoryFilter)) {
        _categoryFilter = null;
        unawaited(_loadFirstPage(showLoading: true));
      }
      _notify();
    } catch (_) {
      // The chips are an extra: the list works without them.
    }
  }

  Future<void> _loadFirstPage({required bool showLoading}) async {
    final generation = ++_generation;
    _loadingMore = false;
    _loadMoreFailed = false;
    if (showLoading) {
      _status = CatalogPickerStatus.loading;
      _items = const [];
      _total = 0;
      _nextCursor = null;
      _notify();
    }
    final requestedQuery = _searchText;
    final requestedCategory = _categoryFilter;
    try {
      final page = await _catalogRepository.browse(
        query: requestedQuery,
        categoryId: requestedCategory,
        limit: pageSize,
      );
      if (generation != _generation || _disposed) {
        return;
      }
      _pageQuery = requestedQuery;
      _pageCategory = requestedCategory;
      _items = page.items;
      _total = page.total;
      _nextCursor = page.nextCursor;
      _status = CatalogPickerStatus.ready;
      _hasLoadedOnce = true;
    } catch (_) {
      if (generation != _generation || _disposed) {
        return;
      }
      if (showLoading || _items.isEmpty) {
        _status = CatalogPickerStatus.failed;
      }
      // A failed pull-to-refresh keeps the current list.
    }
    _notify();
  }

  /// Loads the page after the last one, if there is one and none is already
  /// on its way. Safe to call on every scroll: extra calls do nothing.
  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null ||
        _loadingMore ||
        _status != CatalogPickerStatus.ready) {
      return;
    }
    final generation = _generation;
    _loadingMore = true;
    _loadMoreFailed = false;
    _notify();
    try {
      final page = await _catalogRepository.browse(
        query: _pageQuery,
        categoryId: _pageCategory,
        cursor: cursor,
        limit: pageSize,
      );
      if (generation != _generation || _disposed) {
        return;
      }
      // Never show a product twice, even if a page overlapped.
      final known = {for (final item in _items) item.product.id};
      _items = [
        ..._items,
        for (final item in page.items)
          if (!known.contains(item.product.id)) item,
      ];
      _total = page.total;
      _nextCursor = page.nextCursor;
    } catch (_) {
      if (generation != _generation || _disposed) {
        return;
      }
      _loadMoreFailed = true;
    }
    _loadingMore = false;
    _notify();
  }

  /// Sets the search text. The list is reloaded from the first page once the
  /// owner has paused typing; an unchanged text does nothing.
  void setQuery(String query) {
    if (query == _query) {
      return;
    }
    _query = query;
    _searchTimer?.cancel();
    // The pages in flight belong to the old text: drop them now.
    _generation++;
    _notify();
    _searchTimer = Timer(searchDelay, () {
      unawaited(_loadFirstPage(showLoading: true));
    });
  }

  /// Empties the search and shows the unfiltered list at once (the clear
  /// button: there is nothing to wait for).
  void clearSearch() {
    _searchTimer?.cancel();
    if (_query.isEmpty) {
      return;
    }
    _query = '';
    unawaited(_loadFirstPage(showLoading: true));
  }

  void selectCategory(int? categoryId) {
    if (categoryId == _categoryFilter) {
      return;
    }
    _categoryFilter = categoryId;
    _searchTimer?.cancel();
    unawaited(_loadFirstPage(showLoading: true));
  }

  void clearFilters() {
    _searchTimer?.cancel();
    if (!hasActiveFilters) {
      return;
    }
    _query = '';
    _categoryFilter = null;
    unawaited(_loadFirstPage(showLoading: true));
  }

  /// The loaded row for [productId], if it is on a page already loaded.
  CatalogItem? itemFor(int productId) {
    for (final item in _items) {
      if (item.product.id == productId) {
        return item;
      }
    }
    return null;
  }

  /// Asks the backend what is true now for [productId] and brings the loaded
  /// row in line with it: updated flags, or removed when the catalog no longer
  /// has it. Returns the current item, `null` if the catalog dropped it, and
  /// rethrows nothing: if the backend cannot be reached the loaded row is
  /// returned as it is.
  Future<CatalogItem?> syncItem(int productId) async {
    try {
      final current = await _catalogRepository.product(productId);
      if (_disposed) {
        return current;
      }
      if (current == null) {
        final before = _items.length;
        _items = [
          for (final item in _items)
            if (item.product.id != productId) item,
        ];
        if (_items.length != before) {
          _total = _total > 0 ? _total - 1 : 0;
        }
      } else {
        _items = [
          for (final item in _items)
            if (item.product.id == productId) current else item,
        ];
      }
      _notify();
      return current;
    } catch (_) {
      return itemFor(productId);
    }
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
    _notify();
  }
}
