import 'package:flutter/widgets.dart';

import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/store_products_repository.dart';
import '../../data/repositories/store_repository.dart';

/// Exposes stateless service/repository instances that don't need reactive
/// rebuilds (unlike [AuthScope], which wraps a [ChangeNotifier]).
class AppServices extends InheritedWidget {
  const AppServices({
    required this.storeRepository,
    required this.catalogRepository,
    required this.storeProductsRepository,
    required super.child,
    super.key,
  });

  final StoreRepository storeRepository;
  final CatalogRepository catalogRepository;
  final StoreProductsRepository storeProductsRepository;

  static AppServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'No AppServices found in context');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) => false;
}
