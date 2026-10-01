import 'package:flutter/foundation.dart';

import '../../../../data/models/product.dart';
import '../../../../data/models/store_category.dart';
import '../../../../data/repositories/category_repository.dart';
import '../../../../data/repositories/product_repository.dart';
import '../../../../data/services/api_client.dart';

/// Backs the product editor (create and edit): the categories to choose from,
/// and the save / archive commands. Commands return a French error message,
/// or `null` on success.
class ProductEditorViewModel extends ChangeNotifier {
  ProductEditorViewModel({
    required this._productRepository,
    required this._categoryRepository,
  });

  final ProductRepository _productRepository;
  final CategoryRepository _categoryRepository;

  List<StoreCategory> _categories = const [];
  List<StoreCategory> get categories => _categories;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  Future<void> loadCategories() async {
    try {
      _categories = await _categoryRepository.list();
    } catch (_) {
      // The category is optional; the editor stays usable without the list.
    }
    notifyListeners();
  }

  /// Creates a product, or updates [productId] when given.
  Future<String?> save(ProductInput input, {int? productId}) => _run(() async {
    if (productId == null) {
      await _productRepository.create(input);
    } else {
      await _productRepository.update(productId, input);
    }
  }, onApiError: _saveError);

  Future<String?> archive(int productId) => _run(
    () => _productRepository.archive(productId),
    onApiError: (_) =>
        'Impossible de supprimer le produit. Veuillez réessayer.',
  );

  static String _saveError(ApiException error) => error.statusCode == 409
      ? 'Un produit avec ce nom existe déjà dans votre catalogue.'
      : 'Impossible d’enregistrer le produit. Vérifiez les informations saisies.';

  Future<String?> _run(
    Future<void> Function() action, {
    required String Function(ApiException) onApiError,
  }) async {
    _isBusy = true;
    notifyListeners();
    try {
      await action();
      return null;
    } on ApiException catch (error) {
      return onApiError(error);
    } on NetworkException catch (_) {
      return 'Impossible de contacter le serveur. Vérifiez votre connexion.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
