import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/repositories/catalog_repository.dart';
import '../data/repositories/customer_orders_repository.dart';
import '../data/repositories/customer_stores_repository.dart';
import '../data/repositories/orders_repository.dart';
import '../data/repositories/store_products_repository.dart';
import '../data/repositories/store_repository.dart';
import '../data/services/image_picker_service.dart';
import 'core/app_services.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/view_models/auth_scope.dart';
import 'features/auth/view_models/auth_view_model.dart';
import 'features/customer/view_models/cart_view_model.dart';
import 'features/customer/view_models/customer_scope.dart';
import 'splash_gate.dart';

class GroceryApp extends StatefulWidget {
  const GroceryApp({
    required this.authViewModel,
    required this.storeRepository,
    required this.catalogRepository,
    required this.storeProductsRepository,
    required this.ordersRepository,
    required this.customerStoresRepository,
    required this.customerOrdersRepository,
    this.imagePickerService = const DeviceImagePickerService(),
    super.key,
  });

  final AuthViewModel authViewModel;
  final StoreRepository storeRepository;
  final CatalogRepository catalogRepository;
  final StoreProductsRepository storeProductsRepository;
  final OrdersRepository ordersRepository;
  final CustomerStoresRepository customerStoresRepository;
  final CustomerOrdersRepository customerOrdersRepository;
  final ImagePickerService imagePickerService;

  @override
  State<GroceryApp> createState() => _GroceryAppState();
}

class _GroceryAppState extends State<GroceryApp> {
  // The customer's cart and tab live above the navigator so the screens
  // pushed over the shell (catalogue, checkout, order) share them.
  final _cart = CartViewModel();
  final _navigation = CustomerNavigation();

  @override
  void dispose() {
    _cart.dispose();
    _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      storeRepository: widget.storeRepository,
      catalogRepository: widget.catalogRepository,
      storeProductsRepository: widget.storeProductsRepository,
      ordersRepository: widget.ordersRepository,
      customerStoresRepository: widget.customerStoresRepository,
      customerOrdersRepository: widget.customerOrdersRepository,
      imagePickerService: widget.imagePickerService,
      child: AuthScope(
        authViewModel: widget.authViewModel,
        child: CustomerScope(
          cart: _cart,
          navigation: _navigation,
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
      ),
    );
  }
}
