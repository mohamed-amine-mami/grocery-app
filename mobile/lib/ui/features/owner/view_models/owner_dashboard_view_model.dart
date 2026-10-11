import 'package:flutter/foundation.dart';

import '../../../../data/repositories/store_products_repository.dart';

enum DashboardStatus { loading, ready, failed }

/// What the dashboard knows beyond the store itself. For now that is just
/// enough to drive the setup checklist; order counters ("à confirmer",
/// "prêtes à retirer") will be loaded here too once orders exist.
class OwnerDashboardViewModel extends ChangeNotifier {
  OwnerDashboardViewModel({required this._storeProductsRepository});

  final StoreProductsRepository _storeProductsRepository;

  DashboardStatus _status = DashboardStatus.loading;
  DashboardStatus get status => _status;

  /// Active (non-archived) store products only.
  int _productCount = 0;
  int get productCount => _productCount;

  bool get hasProduct => _productCount > 0;

  /// Active offerings customers can order right now: the backend's own
  /// `isOrderable` verdict on each one (owner switch, stock and catalogue
  /// combined), never recomputed here.
  int _orderableCount = 0;
  int get orderableCount => _orderableCount;

  bool get hasOrderable => _orderableCount > 0;

  /// Reloads the counts. Keeps showing the previous ones while refreshing so
  /// the dashboard doesn't flicker when the owner comes back to the tab.
  /// Returns whether the counts are now known to be up to date.
  Future<bool> refresh() async {
    final isFirstLoad = _status != DashboardStatus.ready;
    if (isFirstLoad) {
      _status = DashboardStatus.loading;
      notifyListeners();
    }
    try {
      final products = await _storeProductsRepository.listActive();
      _productCount = products.length;
      _orderableCount = products.where((p) => p.isOrderable).length;
      _status = DashboardStatus.ready;
      notifyListeners();
      return true;
    } catch (_) {
      // Keep stale-but-valid numbers if we already had some.
      if (isFirstLoad) {
        _status = DashboardStatus.failed;
      }
    }
    notifyListeners();
    return false;
  }
}
