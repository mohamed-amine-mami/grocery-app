import 'package:flutter/foundation.dart';

import '../../../../data/models/store.dart';
import '../../../../data/repositories/store_repository.dart';

enum OwnerStoreStatus {
  /// Asking the backend whether this owner already has a store.
  loading,

  /// The owner is authenticated but has no store yet — they must create one.
  noStore,
  ready,

  /// The backend couldn't be reached or answered unexpectedly.
  failed,
}

/// Resolves the signed-in owner's store so the app can decide between the
/// owner shell and store creation. The backend is the source of truth: an
/// owner without a store never reaches the normal owner screens.
class OwnerStoreViewModel extends ChangeNotifier {
  OwnerStoreViewModel({required this._storeRepository});

  final StoreRepository _storeRepository;

  OwnerStoreStatus _status = OwnerStoreStatus.loading;
  OwnerStoreStatus get status => _status;

  Store? _store;
  Store? get store => _store;

  Future<void> load() async {
    _status = OwnerStoreStatus.loading;
    notifyListeners();
    try {
      _store = await _storeRepository.getMine();
      _status = _store == null
          ? OwnerStoreStatus.noStore
          : OwnerStoreStatus.ready;
    } catch (_) {
      _status = OwnerStoreStatus.failed;
    }
    notifyListeners();
  }
}
