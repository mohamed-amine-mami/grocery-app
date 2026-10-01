import 'package:flutter/foundation.dart';

import '../../../../data/models/store.dart';
import '../../../../data/repositories/store_repository.dart';
import '../../../../data/services/api_client.dart';

class StoreCreateViewModel extends ChangeNotifier {
  StoreCreateViewModel({required this._storeRepository});

  final StoreRepository _storeRepository;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  /// Returns the created [Store] on success, or a French error message on
  /// failure. The owner is taken from the session token by the backend.
  Future<({Store? store, String? error})> createStore({
    required String name,
    required String address,
    String? description,
    String? photo,
    double? latitude,
    double? longitude,
  }) async {
    _isBusy = true;
    notifyListeners();
    try {
      final store = await _storeRepository.create(
        name: name,
        address: address,
        description: description,
        photo: photo,
        latitude: latitude,
        longitude: longitude,
      );
      return (store: store, error: null);
    } on ApiException catch (error) {
      return (
        store: null,
        error: error.statusCode == 409 ? 'Vous avez déjà créé votre magasin.' : 'Impossible de créer le magasin. Vérifiez les informations saisies.',
      );
    } on NetworkException catch (_) {
      return (
        store: null,
        error: 'Impossible de contacter le serveur. Vérifiez votre connexion.',
      );
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
