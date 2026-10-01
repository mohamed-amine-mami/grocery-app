import 'package:flutter/material.dart';

import 'data/repositories/auth_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/store_repository.dart';
import 'data/services/api_client.dart';
import 'data/services/token_storage.dart';
import 'ui/app.dart';
import 'ui/features/auth/view_models/auth_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient();
  final authViewModel = AuthViewModel(
    authRepository: AuthRepository(apiClient),
    tokenStorage: TokenStorage(),
    apiClient: apiClient,
  );
  final storeRepository = StoreRepository(apiClient);

  runApp(
    GroceryApp(
      authViewModel: authViewModel,
      storeRepository: storeRepository,
      categoryRepository: CategoryRepository(apiClient),
      productRepository: ProductRepository(apiClient),
    ),
  );
}
