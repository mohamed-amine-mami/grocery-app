import 'package:flutter/foundation.dart';

import '../../../../data/models/store.dart';
import '../../../../data/repositories/store_repository.dart';
import '../../../../data/services/api_client.dart';

/// The owner's store once it exists: holds the current [store] and the two
/// ways to change it — saving details and the open/closed switch. Commands
/// return a French error message, or `null` on success.
class StoreEditViewModel extends ChangeNotifier {
  StoreEditViewModel({
    required this._storeRepository,
    required Store initialStore,
  }) : _store = initialStore;

  final StoreRepository _storeRepository;

  Store _store;
  Store get store => _store;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  bool _isTogglingOpen = false;
  bool get isTogglingOpen => _isTogglingOpen;

  Future<String?> save({
    required String name,
    required String address,
    String? description,
    String? photo,
    double? latitude,
    double? longitude,
  }) async {
    _isSaving = true;
    notifyListeners();
    try {
      _store = await _storeRepository.update(
        name: name,
        address: address,
        description: description,
        photo: photo,
        latitude: latitude,
        longitude: longitude,
      );
      return null;
    } on ApiException catch (_) {
      return 'Impossible d’enregistrer les modifications. Vérifiez les informations saisies.';
    } on NetworkException catch (_) {
      return _offline;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> setOpen({required bool isOpen}) async {
    _isTogglingOpen = true;
    notifyListeners();
    try {
      _store = await _storeRepository.setOpen(isOpen: isOpen);
      return null;
    } on ApiException catch (_) {
      return 'Impossible de modifier l’état du magasin. Veuillez réessayer.';
    } on NetworkException catch (_) {
      return _offline;
    } finally {
      _isTogglingOpen = false;
      notifyListeners();
    }
  }

  static const _offline =
      'Impossible de contacter le serveur. Vérifiez votre connexion.';
}
