import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/repositories/catalog_repository.dart';
import '../data/repositories/store_products_repository.dart';
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
    required this.catalogRepository,
    required this.storeProductsRepository,
    super.key,
  });

  final AuthViewModel authViewModel;
  final StoreRepository storeRepository;
  final CatalogRepository catalogRepository;
  final StoreProductsRepository storeProductsRepository;

  @override
  Widget build(BuildContext context) {
    return AppServices(
      storeRepository: storeRepository,
      catalogRepository: catalogRepository,
      storeProductsRepository: storeProductsRepository,
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
