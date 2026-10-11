import 'package:flutter/foundation.dart';

import '../../../../data/models/store.dart';
import '../../../../data/repositories/store_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../../data/services/image_picker_service.dart';

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

  /// Sets or replaces the store photo and shows it. Throws what the
  /// repository throws.
  Future<void> setPhoto(PickedImage image) async {
    updateStore(await _storeRepository.setPhoto(image));
  }

  /// Removes the store photo. When the backend answers 503 the photo is
  /// cleared all the same (only deleting the stored file failed), so it asks
  /// what is true now before reporting a failure.
  Future<void> removePhoto() async {
    Store store;
    try {
      store = await _storeRepository.removePhoto();
    } on ApiException catch (error) {
      if (error.statusCode != 503) {
        rethrow;
      }
      final current = await _storeRepository.getMine();
      if (current == null || current.photo != null) {
        rethrow;
      }
      store = current;
    }
    updateStore(store);
  }

  /// Takes the store as the backend now has it (after a photo was set or
  /// removed).
  void updateStore(Store store) {
    _store = store;
    notifyListeners();
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
