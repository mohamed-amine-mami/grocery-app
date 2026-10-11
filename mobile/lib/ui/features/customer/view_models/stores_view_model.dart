import 'package:flutter/foundation.dart';

import '../../../../data/models/customer_store.dart';
import '../../../../data/repositories/customer_stores_repository.dart';
import '../../../core/utils/search_text.dart';

enum StoresStatus { loading, ready, failed }

/// The stores a customer can browse. Closed stores are listed too: they can
/// be opened and browsed, they just cannot take orders.
class StoresViewModel extends ChangeNotifier {
  StoresViewModel({required this._repository});

  final CustomerStoresRepository _repository;

  StoresStatus _status = StoresStatus.loading;
  StoresStatus get status => _status;

  List<CustomerStore> _stores = const [];
  List<CustomerStore> get stores => _stores;

  /// The stores as the list shows them: open ones first, then closed ones,
  /// each group by name (case and accents ignored), the id breaking a tie.
  /// A copy: the loaded list is left as the backend sent it.
  List<CustomerStore> get orderedStores {
    final sorted = [..._stores];
    sorted.sort((a, b) {
      if (a.isOpen != b.isOpen) {
        return a.isOpen ? -1 : 1;
      }
      final byName = SearchText.fold(a.name).compareTo(SearchText.fold(b.name));
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return sorted;
  }

  bool _refreshFailed = false;

  /// The last refresh failed; what is shown is the previous list.
  bool get refreshFailed => _refreshFailed;

  Future<void> load() async {
    _status = StoresStatus.loading;
    notifyListeners();
    try {
      _stores = await _repository.stores();
      _status = StoresStatus.ready;
      _refreshFailed = false;
    } catch (_) {
      _status = StoresStatus.failed;
    }
    notifyListeners();
  }

  /// Pull-to-refresh: keeps the list on screen if the reload fails.
  Future<void> refresh() async {
    try {
      _stores = await _repository.stores();
      _refreshFailed = false;
    } catch (_) {
      _refreshFailed = true;
    }
    notifyListeners();
  }
}
