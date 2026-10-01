import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/repositories/category_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/store_repository.dart';
import 'core/app_services.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/view_models/auth_scope.dart';
import 'features/auth/view_models/auth_view_model.dart';
import 'splash_gate.dart';

class GroceryApp extends StatelessWidget {
  const GroceryApp({
    required this.authViewModel,
    required this.storeRepository,
    required this.categoryRepository,
    required this.productRepository,
    super.key,
  });

  final AuthViewModel authViewModel;
  final StoreRepository storeRepository;
  final CategoryRepository categoryRepository;
  final ProductRepository productRepository;

  @override
  Widget build(BuildContext context) {
    return AppServices(
      storeRepository: storeRepository,
      categoryRepository: categoryRepository,
      productRepository: productRepository,
      child: AuthScope(
        authViewModel: authViewModel,
        child: MaterialApp(
          title: 'Marché',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashGate(),
        ),
      ),
    );
  }
}
