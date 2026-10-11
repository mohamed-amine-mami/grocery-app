import 'package:flutter/widgets.dart';

import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/customer_orders_repository.dart';
import '../../data/repositories/customer_stores_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/store_products_repository.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/services/image_picker_service.dart';

/// Exposes stateless service/repository instances that don't need reactive
/// rebuilds (unlike [AuthScope], which wraps a [ChangeNotifier]).
class AppServices extends InheritedWidget {
  const AppServices({
    required this.storeRepository,
    required this.catalogRepository,
    required this.storeProductsRepository,
    required this.ordersRepository,
    required this.customerStoresRepository,
    required this.customerOrdersRepository,
    required super.child,
    this.imagePickerService = const DeviceImagePickerService(),
    super.key,
  });

  final StoreRepository storeRepository;
  final CatalogRepository catalogRepository;
  final StoreProductsRepository storeProductsRepository;
  final OrdersRepository ordersRepository;
  final CustomerStoresRepository customerStoresRepository;
  final CustomerOrdersRepository customerOrdersRepository;

  /// Chooses a photo from the camera or library (replaced by a fake in tests).
  final ImagePickerService imagePickerService;

  static AppServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'No AppServices found in context');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) => false;
}
