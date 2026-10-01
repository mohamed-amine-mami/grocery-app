import 'package:flutter/foundation.dart';

import '../../../../data/models/store_category.dart';
import '../../../../data/repositories/category_repository.dart';
import '../../../../data/services/api_client.dart';

enum CategoryListStatus { loading, ready, failed }

/// The owner's categories: loading plus the create / rename / delete
/// commands. Mutations return a French error message, or `null` on success.
class CategoryListViewModel extends ChangeNotifier {
  CategoryListViewModel({required this._categoryRepository});

  final CategoryRepository _categoryRepository;

  CategoryListStatus _status = CategoryListStatus.loading;
  CategoryListStatus get status => _status;

  List<StoreCategory> _categories = const [];
  List<StoreCategory> get categories => _categories;

  Future<void> load() async {
    _status = CategoryListStatus.loading;
    notifyListeners();
    try {
      _categories = await _categoryRepository.list();
      _status = CategoryListStatus.ready;
    } catch (_) {
      _status = CategoryListStatus.failed;
    }
    notifyListeners();
  }

  Future<String?> create(String name) =>
      _mutate(() => _categoryRepository.create(name));

  Future<String?> rename(StoreCategory category, String name) =>
      _mutate(() => _categoryRepository.rename(category.id, name));

  Future<String?> delete(StoreCategory category) =>
      _mutate(() => _categoryRepository.delete(category.id));

  /// Runs a write, then refreshes the list so it always mirrors the backend
  /// (which also keeps it sorted).
  Future<String?> _mutate(Future<Object?> Function() write) async {
    try {
      await write();
    } on ApiException catch (error) {
      return switch (error.statusCode) {
        409 => 'Une catégorie avec ce nom existe déjà.',
        404 => 'Cette catégorie n’existe plus.',
        _ => 'Une erreur est survenue. Veuillez réessayer.',
      };
    } on NetworkException catch (_) {
      return 'Impossible de contacter le serveur. Vérifiez votre connexion.';
    }
    try {
      _categories = await _categoryRepository.list();
    } catch (_) {
      // The write succeeded; a failed refresh must not report it as failed.
    }
    notifyListeners();
    return null;
  }
}
