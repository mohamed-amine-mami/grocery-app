import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/auth_response.dart';
import 'package:grocery_mobile/data/models/catalog_category.dart';
import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/repositories/catalog_repository.dart';
import 'package:grocery_mobile/data/repositories/store_products_repository.dart';
import 'package:grocery_mobile/data/repositories/store_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/data/services/token_storage.dart';
import 'package:grocery_mobile/ui/app.dart';
import 'package:grocery_mobile/ui/features/auth/view_models/auth_view_model.dart';

/// In-memory stand-ins for the repositories, so widget tests never touch the
/// network. They subclass the real ones and override only what the tests use.

/// A token store that remembers what happened to it. `token: null` means
/// there is no stored session.
class StoredToken extends TokenStorage {
  StoredToken({this.token = 'stored-token'});

  String? token;
  int clearCalls = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async {
    clearCalls++;
    token = null;
  }
}

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository(super.apiClient, this._user, {this.meError});

  final User _user;

  /// While non-null, `me()` throws it (e.g. a [NetworkException] or a 401).
  Object? meError;

  @override
  Future<User> me() async {
    final error = meError;
    if (error != null) {
      throw error;
    }
    return _user;
  }

  @override
  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required UserRole role,
    String? whatsappNumber,
    String? photo,
  }) async => AuthResponse(
    accessToken: 'new-token',
    user: User(
      id: 99,
      name: name,
      email: email,
      phoneNumber: phoneNumber,
      role: role,
    ),
  );
}

class FakeStoreRepository extends StoreRepository {
  FakeStoreRepository(super.apiClient, {this.store, this.fails = false});

  Store? store;
  final bool fails;

  /// What the last `update` call sent, for assertions.
  Map<String, Object?>? lastUpdate;

  @override
  Future<Store?> getMine() async {
    if (fails) {
      throw const NetworkException('offline');
    }
    return store;
  }

  @override
  Future<Store> update({
    required String name,
    required String address,
    String? description,
    String? photo,
    double? latitude,
    double? longitude,
  }) async {
    lastUpdate = {
      'name': name,
      'address': address,
      'description': description,
      'photo': photo,
      'latitude': latitude,
      'longitude': longitude,
    };
    return store = Store(
      id: store!.id,
      name: name,
      address: address,
      description: description,
      photo: photo,
      latitude: latitude,
      longitude: longitude,
      isOpen: store!.isOpen,
      ownerId: store!.ownerId,
    );
  }

  @override
  Future<Store> setOpen({required bool isOpen}) async {
    final current = store!;
    return store = Store(
      id: current.id,
      name: current.name,
      address: current.address,
      isOpen: isOpen,
      ownerId: current.ownerId,
    );
  }
}

/// The global catalog, in memory. Read-only, like the real thing.
class FakeCatalogRepository extends CatalogRepository {
  FakeCatalogRepository(
    super.apiClient, {
    this.categoryList = const [],
    this.items = const [],
    this.fails = false,
    this.gate,
  });

  final List<CatalogCategory> categoryList;
  List<CatalogItem> items;

  /// When true, every call fails like an unreachable backend. Flip it back to
  /// false to let a retry succeed.
  bool fails;

  /// When set, every call waits for it to complete — lets a test look at the
  /// loading state.
  Completer<void>? gate;

  /// How many times the catalog was fetched.
  int productsCalls = 0;

  /// Flags a product as sold by the store, the way the backend would after an
  /// add (or because another device added it).
  void markAdded(int productId, int storeProductId) {
    items = [
      for (final item in items)
        if (item.product.id == productId)
          CatalogItem(
            product: item.product,
            inMyStore: true,
            storeProductId: storeProductId,
            storeProductArchived: false,
          )
        else
          item,
    ];
  }

  /// Flags a product as archived in the store.
  void markArchived(int productId, int storeProductId) {
    items = [
      for (final item in items)
        if (item.product.id == productId)
          CatalogItem(
            product: item.product,
            inMyStore: false,
            storeProductId: storeProductId,
            storeProductArchived: true,
          )
        else
          item,
    ];
  }

  /// Removes a product from the catalog (the catalog archived it).
  void remove(int productId) {
    items = [
      for (final item in items)
        if (item.product.id != productId) item,
    ];
  }

  @override
  Future<List<CatalogCategory>> categories() async {
    if (fails) {
      throw const NetworkException('offline');
    }
    return [...categoryList];
  }

  @override
  Future<List<CatalogItem>> products({int? categoryId}) async {
    productsCalls++;
    await gate?.future;
    if (fails) {
      throw const NetworkException('offline');
    }
    return [
      for (final item in items)
        if (categoryId == null || item.product.category.id == categoryId) item,
    ];
  }
}

/// The store's offerings, in memory. Mirrors the backend's rules closely
/// enough for view-model and widget tests: archive/restore, the owner switch,
/// derived availability, and the stock-changed refusal.
class FakeStoreProductsRepository extends StoreProductsRepository {
  FakeStoreProductsRepository(
    super.apiClient, {
    List<StoreProduct> products = const [],
    this.fails = false,
    this.catalog = const [],
    this.onCreated,
  }) {
    for (final product in products) {
      _products.add(product);
      _nextId = product.id >= _nextId ? product.id + 1 : _nextId;
    }
  }

  final _products = <StoreProduct>[];
  var _nextId = 1;

  /// When true, listing fails like an unreachable backend.
  final bool fails;

  /// The catalog this store can add from (what `create` looks products up in).
  final List<CatalogItem> catalog;

  /// Called after a successful `create` — lets a test keep the fake catalog in
  /// step, the way the real backend's catalog listing follows.
  final void Function(StoreProduct created)? onCreated;

  /// When set, `create` fails with it (an [ApiException], [NetworkException]…).
  /// Clear it to let a retry succeed.
  Object? createError;

  /// What the last create / update sent, for assertions.
  NewStoreProduct? lastCreate;
  int createCalls = 0;
  StoreProductUpdate? lastUpdate;
  int? lastUpdatedId;
  int updateCalls = 0;
  int availabilityCalls = 0;
  int archiveCalls = 0;
  int restoreCalls = 0;

  /// When set, `update` / `setAvailability` / `archive` / `restore` fail with
  /// it. Clear it to let a retry succeed.
  Object? updateError;
  Object? availabilityError;
  Object? archiveError;
  Object? restoreError;

  /// An order (or another device) changes the stock behind the screen's back.
  void changeStockExternally(int id, int stock) {
    _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      stockQuantity: stock,
      keepStock: false,
    );
  }

  List<String> get names => [
    for (final p in _products)
      if (!p.isArchived) p.product.name,
  ];

  StoreProduct byName(String name) =>
      _products.firstWhere((p) => p.product.name == name);

  int _indexOf(int id) => _products.indexWhere((p) => p.id == id);

  @override
  Future<List<StoreProduct>> list({
    StoreProductStatus status = StoreProductStatus.active,
    int? categoryId,
  }) async {
    if (fails) {
      throw const NetworkException('offline');
    }
    return [
      for (final p in _products)
        if ((status == StoreProductStatus.all ||
                p.isArchived == (status == StoreProductStatus.archived)) &&
            (categoryId == null || p.category.id == categoryId))
          p,
    ]..sort((a, b) => a.product.name.compareTo(b.product.name));
  }

  @override
  Future<StoreProduct> get(int id) async => _products[_indexOf(id)];

  @override
  Future<StoreProduct> create(NewStoreProduct input) async {
    createCalls++;
    lastCreate = input;
    final error = createError;
    if (error != null) {
      throw error;
    }
    if (_products.any((p) => p.productId == input.productId)) {
      throw const ApiException(
        statusCode: 409,
        message: 'Your store already sells this product',
      );
    }
    final product = catalog
        .firstWhere((item) => item.product.id == input.productId)
        .product;
    final unit = input.saleUnit ?? product.defaultSaleUnit;
    final created = fakeStoreProduct(
      id: _nextId++,
      product: product,
      saleUnit: unit,
      priceMillimes: input.priceMillimes,
      minQuantity: input.minQuantity ?? product.defaultMinQuantity,
      quantityStep: input.quantityStep ?? product.defaultQuantityStep,
      maxQuantity: input.noMaximum
          ? null
          : (input.maxQuantity ?? product.defaultMaxQuantity),
      trackStock: input.trackStock ?? false,
      stockQuantity: input.trackStock == true ? input.stockQuantity : null,
      isAvailable: input.isAvailable ?? true,
    );
    _products.add(created);
    onCreated?.call(created);
    return created;
  }

  @override
  Future<StoreProduct> setAvailability(
    int id, {
    required bool isAvailable,
  }) async {
    availabilityCalls++;
    if (availabilityError != null) {
      throw availabilityError!;
    }
    return _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      isAvailable: isAvailable,
    );
  }

  @override
  Future<void> archive(int id) async {
    archiveCalls++;
    if (archiveError != null) {
      throw archiveError!;
    }
    _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      isArchived: true,
    );
  }

  @override
  Future<StoreProduct> restore(int id) async {
    restoreCalls++;
    if (restoreError != null) {
      throw restoreError!;
    }
    return _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      isArchived: false,
    );
  }

  @override
  Future<StoreProduct> update(int id, StoreProductUpdate input) async {
    updateCalls++;
    if (updateError != null) {
      throw updateError!;
    }
    lastUpdate = input;
    lastUpdatedId = id;
    final current = _products[_indexOf(id)];
    if (current.isArchived) {
      throw const ApiException(
        statusCode: 409,
        message: 'Archived products cannot be modified',
      );
    }
    final stock = input.stock;
    if (stock != null && stock.expectedStockQuantity != current.stockQuantity) {
      throw StockChangedException(currentStockQuantity: current.stockQuantity);
    }
    final trackStock = stock?.trackStock ?? current.trackStock;
    return _products[_indexOf(id)] = rebuildStoreProduct(
      current,
      priceMillimes: input.priceMillimes,
      saleUnit: input.saleUnit,
      minQuantity: input.minQuantity,
      quantityStep: input.quantityStep,
      maxQuantity: input.clearMaxQuantity ? null : input.maxQuantity,
      clearMaxQuantity: input.clearMaxQuantity,
      trackStock: trackStock,
      stockQuantity: !trackStock ? null : stock?.stockQuantity,
      keepStock: stock == null,
    );
  }
}

/// A copy of [p] with some fields changed. The derived availability is
/// recomputed the way the backend does it.
StoreProduct rebuildStoreProduct(
  StoreProduct p, {
  bool? isAvailable,
  bool? isArchived,
  int? priceMillimes,
  SaleUnit? saleUnit,
  int? minQuantity,
  int? quantityStep,
  int? maxQuantity,
  bool clearMaxQuantity = false,
  bool? trackStock,
  int? stockQuantity,
  bool keepStock = true,
}) {
  final track = trackStock ?? p.trackStock;
  final stock = keepStock ? p.stockQuantity : stockQuantity;
  final min = minQuantity ?? p.minQuantity;
  final available = isAvailable ?? p.isAvailable;
  final archived = isArchived ?? p.isArchived;
  final reason = archived
      ? UnavailabilityReason.archived
      : !available
      ? UnavailabilityReason.ownerDisabled
      : !p.product.isActive || !p.category.isActive
      ? UnavailabilityReason.catalogArchived
      : track && (stock ?? 0) <= 0
      ? UnavailabilityReason.outOfStock
      : track && stock! < min
      ? UnavailabilityReason.stockBelowMinimum
      : null;
  return StoreProduct(
    id: p.id,
    product: p.product,
    saleUnit: saleUnit ?? p.saleUnit,
    priceMillimes: priceMillimes ?? p.priceMillimes,
    minQuantity: min,
    quantityStep: quantityStep ?? p.quantityStep,
    maxQuantity: clearMaxQuantity ? null : (maxQuantity ?? p.maxQuantity),
    trackStock: track,
    stockQuantity: stock,
    isAvailable: available,
    isOrderable: reason == null,
    unavailabilityReason: reason,
    isArchived: archived,
  );
}

const fakeVegetables = CategoryRef(id: 3, slug: 'legumes', name: 'Légumes');
const fakePickerFruits = CategoryRef(id: 11, slug: 'fruits', name: 'Fruits');
const fakeFruits = CategoryRef(
  id: 1,
  slug: 'fruits-legumes',
  name: 'Fruits et légumes',
);
const fakeDairy = CategoryRef(
  id: 2,
  slug: 'produits-laitiers',
  name: 'Produits laitiers',
);

/// The global catalog product bananas/tomatoes/eggs are offerings of. It has
/// no price, stock or availability — those are the store product's.
CatalogProduct fakeCatalogProduct({
  int id = 1,
  String slug = 'tomate',
  String name = 'Tomate',
  CategoryRef category = fakeFruits,
  SaleUnit unit = SaleUnit.kg,
  int min = 500,
  int step = 100,
  int? max = 10000,
}) => CatalogProduct(
  id: id,
  slug: slug,
  name: name,
  category: category,
  defaultSaleUnit: unit,
  allowedSaleUnits: unit == SaleUnit.piece
      ? const [SaleUnit.piece]
      : [unit, SaleUnit.piece],
  defaultMinQuantity: min,
  defaultQuantityStep: step,
  defaultMaxQuantity: max,
);

/// A row of the catalog picker.
CatalogItem fakeCatalogItem({
  required int id,
  required String name,
  String? slug,
  CategoryRef category = fakePickerFruits,
  SaleUnit unit = SaleUnit.kg,
  bool inMyStore = false,
  bool storeProductArchived = false,
}) => CatalogItem(
  product: fakeCatalogProduct(
    id: id,
    slug: slug ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
    name: name,
    category: category,
    unit: unit,
  ),
  inMyStore: inMyStore,
  storeProductId: inMyStore || storeProductArchived ? 100 + id : null,
  storeProductArchived: storeProductArchived,
);

/// A small catalog: fruits, vegetables and dairy, with Banane already in the
/// store.
List<CatalogItem> fakeCatalogItems() => [
  fakeCatalogItem(id: 1, name: 'Banane', inMyStore: true),
  fakeCatalogItem(id: 2, name: 'Pomme'),
  fakeCatalogItem(id: 3, name: 'Pomme de terre', category: fakeVegetables),
  fakeCatalogItem(id: 4, name: 'Tomate', category: fakeVegetables),
  fakeCatalogItem(
    id: 5,
    name: 'Œufs',
    slug: 'oeufs',
    category: fakeDairy,
    unit: SaleUnit.piece,
  ),
  fakeCatalogItem(
    id: 6,
    name: 'Lait entier 1 L',
    category: fakeDairy,
    unit: SaleUnit.piece,
  ),
];

/// A store's offering of [product].
StoreProduct fakeStoreProduct({
  int id = 1,
  CatalogProduct? product,
  SaleUnit? saleUnit,
  int priceMillimes = 1800,
  int minQuantity = 500,
  int quantityStep = 500,
  int? maxQuantity = 10000,
  bool trackStock = false,
  int? stockQuantity,
  bool isAvailable = true,
  bool isArchived = false,
}) {
  final catalog = product ?? fakeCatalogProduct();
  return rebuildStoreProduct(
    StoreProduct(
      id: id,
      product: catalog,
      saleUnit: saleUnit ?? catalog.defaultSaleUnit,
      priceMillimes: priceMillimes,
      minQuantity: minQuantity,
      quantityStep: quantityStep,
      maxQuantity: maxQuantity,
      trackStock: trackStock,
      stockQuantity: stockQuantity,
      isAvailable: true,
      isOrderable: true,
    ),
    isAvailable: isAvailable,
    isArchived: isArchived,
  );
}

/// A KG product: 1,800 DT/kg, ordered by 500 g up to 10 kg.
StoreProduct fakeTomatoes({
  int id = 1,
  CategoryRef category = fakeFruits,
  bool isAvailable = true,
  bool trackStock = false,
  int? stockQuantity,
}) => fakeStoreProduct(
  id: id,
  product: fakeCatalogProduct(id: id, category: category),
  isAvailable: isAvailable,
  trackStock: trackStock,
  stockQuantity: stockQuantity,
);

/// A PIECE product: 0,350 DT each.
StoreProduct fakeEggs({int id = 2, CategoryRef category = fakeDairy}) =>
    fakeStoreProduct(
      id: id,
      product: fakeCatalogProduct(
        id: id,
        slug: 'oeufs',
        name: 'Œufs',
        category: category,
        unit: SaleUnit.piece,
        min: 1,
        step: 1,
        max: null,
      ),
      priceMillimes: 350,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: null,
    );

const testOwner = User(
  id: 1,
  name: 'Karim',
  email: 'karim@example.com',
  phoneNumber: '+21612345678',
  role: UserRole.owner,
);

const testClient = User(
  id: 2,
  name: 'Sana',
  email: 'sana@example.com',
  phoneNumber: '+21698765432',
  role: UserRole.client,
);

const closedStore = Store(
  id: 10,
  name: 'Menzah Market',
  address: '12 Rue de la Liberté, Tunis',
  isOpen: false,
  ownerId: 1,
);

/// Boots the whole app with an already-stored session for [user].
Future<void> pumpAppSignedInAs(
  WidgetTester tester,
  User user, {
  required StoreRepository Function(ApiClient) storeRepository,
  CatalogRepository Function(ApiClient)? catalogRepository,
  StoreProductsRepository Function(ApiClient)? storeProductsRepository,
  FakeAuthRepository Function(ApiClient)? authRepository,
  TokenStorage? tokenStorage,
}) async {
  final apiClient = ApiClient();
  await tester.pumpWidget(
    GroceryApp(
      authViewModel: AuthViewModel(
        authRepository:
            (authRepository ?? (api) => FakeAuthRepository(api, user))(
              apiClient,
            ),
        tokenStorage: tokenStorage ?? StoredToken(),
        apiClient: apiClient,
      ),
      storeRepository: storeRepository(apiClient),
      catalogRepository: (catalogRepository ?? FakeCatalogRepository.new)(
        apiClient,
      ),
      storeProductsRepository:
          (storeProductsRepository ?? FakeStoreProductsRepository.new)(
            apiClient,
          ),
    ),
  );
  await tester.pumpAndSettle();
}
